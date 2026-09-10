"""The agent's equivalence screen: a pluggable LLM (or formal) equivalence check.

``equiv_check`` compares one candidate rewrite against the pristine module it
rewrites and returns a verdict (equiv / not_equiv / unsure) plus the behaviors
worth testing. The check itself lives in ``equiv_check_backend.py`` -- an
apex-free module holding ``_run_verification`` / ``_screen`` and their data types
(``ScreenOutcome``, ``ScreenVerdict``, ``_Sides``), so the screen can be
implemented and unit-tested on its own. This wrapper resolves the module's two
sides from the candidate store and calls into it.

The verdict is a screen, never a proof: on its own it is neither evidence that
two modules agree nor grounds to discard a candidate, so it is always quoted as a
screen with a recommendation of the engineer's own formal signoff.
"""

from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from apex.agent.runtime.context import ToolContext
from apex.agent.scope import SessionScope
from apex.agent.tools.candidate_paths import CandidateView, resolve_candidate
from apex.agent.tools.eda_tools.equiv_check_backend import (
    ScreenOutcome,
    _run_verification,
    _Sides,
)
from apex.agent.tools.tools import Tool, ToolOutput, ToolStatus
from apex.llm.model import ToolSpec
from apex.verify.equiv_screener import declaring_file

__all__ = ["EquivCheckTool"]

#: How many concerns the answer spells out before it defers to the JSON block.
_MAX_CONCERNS_SHOWN = 12


def _safe_call_id(call_id: str) -> str:
    """Sanitizes a call id for use as a filesystem directory name."""
    return re.sub(r"[^A-Za-z0-9_.-]", "_", call_id)[:80] or "call"


def _error(message: str) -> ToolOutput:
    """A refused call: nothing was written, and the model can read why."""
    return ToolOutput(ToolStatus.ERROR, f"ERROR: {message}", side_effects="none")


@dataclass(frozen=True)
class EquivCheckTool(Tool):
    """Screens a candidate against the module it rewrites, via a pluggable backend.

    Attributes:
        scope: The session's filesystem perimeter. The candidate store the two
            sides are read from, and every artifact a screen writes, live under
            its scratch tree; the user's design tree is never written.
    """

    scope: SessionScope

    @property
    def scratch_dir(self) -> Path:
        """The session scratch tree the candidate store and artifacts live in."""
        return self.scope.scratch

    @property
    def spec(self) -> ToolSpec:
        scratch = self.scratch_dir
        base = scratch / "base"
        artifacts = scratch / "artifacts"
        description = (
            "The equivalence screen: compares one candidate rewrite against the "
            "pristine module it replaces and returns a verdict plus the behaviors "
            "worth testing. It is a screen, not a proof -- quote the verdict as "
            "the tool gives it and recommend the engineer's own formal signoff; "
            "never call a candidate verified or equivalent on this alone.\n"
            "\nResult: a verdict -- equiv, not_equiv, or unsure -- a confidence "
            "in 0..1, a detail summary, the concerns worth turning into stimulus, "
            "and, for not_equiv, a distinguishing counterexample. Equivalence "
            "means the primary outputs agree for every input sequence; internal "
            "state may differ.\n"
            "\nOne module per call, named by 'module'; both the pristine design "
            "and the candidate must declare it -- a candidate that renamed it is "
            "refused, because a rename is itself an interface difference. A "
            "rewrite that touched several modules is screened one module at a "
            "time, bottom up.\n"
            "\nRefused with an error (nothing written): cand_id or module blank; "
            "a store that was never initialized (run candidates init_base first); "
            "an initialized store holding no Verilog sources to compare; a cand_id "
            "not shaped like 'cand/001', or naming no live worktree and no "
            "committed branch; or a module neither side declares.\n"
            f"\nSides are read from the candidate store under {scratch}: the "
            f"pristine source from '{base}' (branch main) and the candidate's "
            "from its worktree or a read-only staging checkout; the user's design "
            "tree and the store's git state are never written. A completed screen "
            f"writes '{artifacts}/<call-id>/screen.json' (verdict, confidence, "
            "detail, concerns, counterexample, cand_id, module, and the files the "
            "check wrote). It records nothing into the candidate's index row, so "
            "persist the outcome with the candidates tool if it should survive "
            f"the session. The model-facing text lists at most {_MAX_CONCERNS_SHOWN} "
            "concerns; screen.json always holds every one.\n"
            "\nNOTE: the example LLM screen is not wired in yet, so a call "
            "resolves both sides and returns verdict 'unsure' rather than a real "
            "decision. Remove this note once the backend is implemented.\n"
            "\nValid: {cand_id:'cand/012', module:'aes_sbox'} screens that module "
            "of that candidate. Refused: {cand_id:'cand/012'} omits module; "
            "{cand_id:'cand/012', module:'nope'} names a module neither side "
            "declares."
        )
        return ToolSpec(
            name="equiv_check",
            description=description,
            parameters={
                "type": "object",
                "properties": {
                    "cand_id": {
                        "type": "string",
                        "description": (
                            "The candidate to check, shaped like 'cand/001'. Must "
                            "name a candidate in the session's store, either a "
                            "live worktree or a committed branch."
                        ),
                        "examples": ["cand/003"],
                    },
                    "module": {
                        "type": "string",
                        "description": (
                            "The module to compare, by name. Both the pristine "
                            "design and the candidate must declare it; a rename is "
                            "refused, being itself an interface change. One module "
                            "per call. Use rtl_hierarchy to list declared names."
                        ),
                        "examples": ["aes_sbox"],
                    },
                },
                "required": ["cand_id", "module"],
                "additionalProperties": False,
            },
        )

    async def __call__(self, args: Mapping[str, Any], ctx: ToolContext) -> ToolOutput:
        raw_cand = args.get("cand_id")
        if not isinstance(raw_cand, str) or not raw_cand.strip():
            return _error("'cand_id' must be a non-empty string")
        raw_module = args.get("module")
        if not isinstance(raw_module, str) or not raw_module.strip():
            return _error("'module' must be a non-empty string")

        view = await resolve_candidate(self.scratch_dir, raw_cand.strip())
        if isinstance(view, str):
            return _error(view)

        sides = await self._locate(view, raw_module.strip())
        if isinstance(sides, ToolOutput):
            return sides

        return await self._screen(args, view, sides, ctx)

    # -- locating the two sides ---------------------------------------------

    async def _locate(self, view: CandidateView, module: str) -> _Sides | ToolOutput:
        """Finds the file declaring one module on each side of the comparison."""
        gold_files = view.rtl_files(candidate_side=False)
        cand_files = view.rtl_files(candidate_side=True)
        if not gold_files:
            return _error(
                f"no Verilog sources under {view.base_dir}; the candidate store "
                "holds no design to compare against"
            )

        gold_path = declaring_file(gold_files, module)
        if gold_path is None:
            return _error(
                f"the pristine design declares no module named {module!r}. Use "
                "rtl_hierarchy to see what it does declare."
            )
        candidate_path = declaring_file(cand_files, module)
        if candidate_path is None:
            return _error(
                f"{view.cand_id} declares no module named {module!r}; the "
                "rewrite may have renamed it, which is itself a difference."
            )

        return _Sides(
            module=module,
            gold_path=gold_path,
            candidate_path=candidate_path,
            gold_deps=tuple(p for p in gold_files if p != gold_path),
            candidate_deps=tuple(p for p in cand_files if p != candidate_path),
            deps_changed=view.touches_other_than(candidate_path),
        )

    # -- the screener -------------------------------------------------------

    async def _screen(
        self,
        args: Mapping[str, Any],
        view: CandidateView,
        sides: _Sides,
        ctx: ToolContext,
    ) -> ToolOutput:
        """Runs the equivalence backend over the two located sides.

        Runs the (blocking) screen off the event loop in the call's own artifacts
        directory, then writes ``screen.json`` and renders the verdict. The raw
        ``args`` are forwarded so the backend can read parameters added to the
        spec. Mutated: writes ``artifacts/<call-id>/screen.json`` and whatever
        the backend emits under that same directory; commits nothing to git and
        never touches the candidate's index row.
        """
        ctx.report(f"screening {sides.module} for {view.cand_id}")

        out_dir = self.scratch_dir / "artifacts" / _safe_call_id(ctx.call_id)
        out_dir.mkdir(parents=True, exist_ok=True)

        outcome = await asyncio.to_thread(_run_verification, args, sides, out_dir)

        payload = _screen_payload(outcome, view, sides)
        (out_dir / "screen.json").write_text(json.dumps(payload, indent=2))
        payload["screen_path"] = str(out_dir / "screen.json")

        content, truncated = _render_screen(outcome, sides, payload)
        return ToolOutput(
            ToolStatus.OK,
            content,
            data={**payload, "truncated": truncated},
            view=_screen_view(outcome, view, sides),
            side_effects="committed",
        )


# ---------------------------------------------------------------------------
# Payloads and presentation
# ---------------------------------------------------------------------------


def _screen_payload(
    outcome: ScreenOutcome, view: CandidateView, sides: _Sides
) -> dict[str, object]:
    """The screen's machine-readable answer."""
    return {
        "mode": "screener",
        "cand_id": view.cand_id,
        "module": sides.module,
        "verdict": outcome.verdict,
        "confidence": round(outcome.confidence, 3),
        "detail": outcome.detail,
        "concerns": list(outcome.concerns),
        "counterexample": outcome.counterexample,
        "deps_changed": sides.deps_changed,
        "artifacts": [str(path) for path in outcome.artifacts],
    }


def _render_screen(
    outcome: ScreenOutcome, sides: _Sides, payload: dict[str, object]
) -> tuple[str, bool]:
    """Composes the screen's answer, saying plainly what it is worth."""
    lines = [
        f"equiv_check on `{sides.module}`: **{outcome.verdict}** "
        f"(confidence {outcome.confidence:.2f})."
    ]
    if outcome.detail:
        lines.append(f"- {outcome.detail}")
    if outcome.verdict == "not_equiv" and outcome.counterexample:
        lines.append(f"- Counterexample: {outcome.counterexample}")

    truncated = len(outcome.concerns) > _MAX_CONCERNS_SHOWN
    if outcome.concerns:
        lines.append("- Concerns worth reasoning through:")
        for concern in outcome.concerns[:_MAX_CONCERNS_SHOWN]:
            lines.append(f"  * {concern}")
    lines.append(
        "- This is a screen, not a proof: it is not evidence the two modules "
        "agree, so recommend the engineer's own formal signoff."
    )
    if sides.deps_changed:
        lines.append(
            "- The candidate changed files besides this module; screen each "
            "touched module on its own."
        )

    content = (
        "\n".join(lines) + "\n\n```json\n" + json.dumps(payload, indent=2) + "\n```"
    )
    if truncated:
        content += (
            f"\n\nBounded view: {_MAX_CONCERNS_SHOWN} concerns shown. "
            f"All of them are at {payload.get('screen_path')}."
        )
    return content, truncated


def _screen_view(
    outcome: ScreenOutcome, view: CandidateView, sides: _Sides
) -> dict[str, object]:
    """The screener's render view: the verdict badge and what it compared."""
    return {
        "mode": "screener",
        "module": sides.module,
        "cand_id": view.cand_id,
        "verdict": outcome.verdict,
        "confidence": round(outcome.confidence, 3),
        "deps_changed": sides.deps_changed,
    }
