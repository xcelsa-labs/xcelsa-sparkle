"""A pluggable equivalence-verification tool: pristine baseline vs candidate RTL.

``VerifTool`` is the seam for wiring any RTL-vs-RTL' equivalence flow (formal
BMC, a bounded miter, a simulation harness) into the agent as a single tool. It
resolves the two sides of the comparison from the session's candidate store --
the pristine design a candidate rewrites, and the candidate's own sources -- and
hands their sources to a backend that decides whether the two agree.

The verification backend itself lives in ``verif_backend.py`` -- an
apex-free module holding ``_run_verification`` and the plain data types it uses
(``VerifResult``, ``VerifStatus``, ``_Sides``), so the flow can be implemented
and unit-tested on its own. This wrapper resolves the two sides from the
candidate store and calls into it. Until a real flow is wired in, a call
resolves both sides, reports what it would compare, and returns an ``unknown``
result rather than a verdict.
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
from apex.agent.tools.eda_tools.verif_backend import (
    VerifResult,
    VerifStatus,
    _run_verification,
    _Sides,
)
from apex.agent.tools.tools import Tool, ToolOutput, ToolStatus
from apex.llm.model import ToolSpec

__all__ = ["VerifResult", "VerifStatus", "VerifTool"]

# =============================================================================
# TODO: turning this skeleton into a tool the agent can use. Every step below is
# also marked with a matching "TODO(n)" at the exact spot in the code.
#   [ ] TODO(1): implement the verification backend in `_run_verification`
#                (in verif_backend.py, the apex-free module this imports).
#.               After that, wire in a few tests off of some example args to 
#                `_run_verification` and the two sides of a candidate store, so
#                the flow can be exercised without apex. The backend is the one
#                seam to implement; the rest of this file is essentially an 
#                integration of apex verifs function docstring so an agent can call it.
#   [x] TODO(2): description rewritten to state the real engine (rtl-equiv /
#                bv_decide) and the scope of "equivalent"; NOTE paragraph removed.
#   [x] TODO(3): added `module` and `timeout_s` args (both honored by the
#                backend). `bmc_depth` intentionally omitted -- this flow is
#                combinational bv_decide, so an unroll depth has no role here.
#   [x] TODO(4): `module` / `timeout_s` validated in `VerifTool.__call__`.
#   [ ] TODO(5): size the "verify" concurrency pool for the backend, where the
#                runtime supervisor configures resource slots.
#   [ ] TODO(6): register the tool so a session offers it --
#                - export it in `apex/agent/tools/eda_tools/__init__.py`,
#                - construct it in the `tools` list in `apex/agent/session.py`.
#   [ ] TODO(7): run `make fix` then `make check` (ruff + pyright strict + web).
# =============================================================================

#: The named concurrency pool a real verification backend should acquire a slot
#: from, so several verify calls in one batch do not oversubscribe the host with
#: solver or simulator processes. Wire it up as ``async with ctx.slot(_SLOT):``.
# TODO(5): confirm the runtime supervisor sizes this "verify" pool for however
# many concurrent solver/simulator processes the integrated backend can run.
_VERIF_SLOT = "verify"


def _safe_call_id(call_id: str) -> str:
    """Sanitizes a call id for use as a filesystem directory name."""
    return re.sub(r"[^A-Za-z0-9_.-]", "_", call_id)[:80] or "call"


def _error(message: str) -> ToolOutput:
    """A refused call: nothing was written, and the model can read why."""
    return ToolOutput(ToolStatus.ERROR, f"ERROR: {message}", side_effects="none")


@dataclass(frozen=True)
class VerifTool(Tool):
    """Verifies a candidate against the pristine base with a pluggable flow.

    Attributes:
        scope: The session's filesystem perimeter. The candidate store the two
            sides are read from, and every artifact a run writes, live under its
            scratch tree; the user's design tree is never written.
    """

    scope: SessionScope

    @property
    def scratch_dir(self) -> Path:
        """The session scratch tree the candidate store and artifacts live in."""
        return self.scope.scratch

    @property
    def spec(self) -> ToolSpec:
        # The spec description is the model's whole view of the tool: it states
        # the real engine (Sparkle rtl-equiv / bv_decide), the exact scope of
        # "equivalent", and the role of each argument. Keep it true.
        scratch = self.scratch_dir
        base = scratch / "base"
        artifacts = scratch / "artifacts"
        description = (
            "Equivalence verification for one candidate via Sparkle's rtl-equiv "
            "(bv_decide). It parses the pristine and candidate Verilog into "
            "Sparkle IR, extracts each register's next-state cone and each "
            "combinational output cone as a pure function over a shared "
            "state/input, and proves every CHANGED cone equal with bv_decide -- a "
            "kernel-checked SAT decision over ALL inputs (combinational "
            "equivalence). This is a real proof for state-preserving rewrites, "
            "not a diff or a simulation, and is stronger evidence than the "
            "equiv_check screen.\n"
            "\nResult: a status -- equivalent (every changed cone proven equal), "
            "not_equivalent (a distinguishing input, returned as a "
            "counterexample), unknown (inconclusive: a timeout, an unsupported "
            "construct, or a sequential change -- retiming/pipelining/FSM "
            "re-encode -- where the register/port signatures differ, which this "
            "combinational flow cannot decide), or error (bad input, missing "
            "file, parse failure) -- plus the method and a detail summary. Quote "
            "the status as given and recommend the engineer's own signoff.\n"
            "\nScope: state-preserving (combinational) edits only. If the "
            "candidate changes the set of registers or ports, the check returns "
            "unknown and says to route it to a sequential (BMC) engine.\n"
            "\nArgs: 'cand_id' selects the candidate. 'module' (optional) targets "
            "one module by name when several files changed; omit it and the tool "
            "checks the single changed file automatically. 'timeout_s' (optional) "
            "bounds the solver run; on expiry the status is unknown.\n"
            "\nRefused, and nothing written: cand_id blank, not shaped like "
            "'cand/001', or naming no candidate in the store; a store never "
            "initialized (run candidates init_base first); or a store holding no "
            "Verilog to compare.\n"
            f"\nSides are read from the candidate store under {scratch}: the "
            f"pristine design from '{base}' (branch main) and the candidate from "
            "its worktree or a read-only staging checkout; the user's design "
            "tree and the store's git state are never written. A completed run "
            f"writes '{artifacts}/<call-id>/verif.json' (status, method, detail, "
            "counterexample, cand_id, and the files the flow wrote) plus the "
            "generated proof file; it records nothing into the candidate's index "
            "row, so persist the outcome with the candidates tool if it should "
            "survive the session."
        )
        return ToolSpec(
            name="verify_equivalence",
            description=description,
            parameters={
                "type": "object",
                "properties": {
                    "cand_id": {
                        "type": "string",
                        "description": (
                            "The candidate to verify, shaped like 'cand/001'. "
                            "Must name a candidate in the session's store, "
                            "either a live worktree or a committed branch."
                        ),
                        "examples": ["cand/003"],
                    },
                    "module": {
                        "type": "string",
                        "description": (
                            "Optional. Verify one module by name instead of "
                            "letting the tool pick the changed file. Both the "
                            "pristine design and the candidate must declare it (a "
                            "rename counts as not declaring it). Use this when the "
                            "candidate touched more than one Verilog file; omit it "
                            "for a single-file change. One module per call."
                        ),
                        "examples": ["timer_core", "aes_sbox"],
                    },
                    "timeout_s": {
                        "type": "integer",
                        "description": (
                            "Optional. Wall-clock budget in seconds for the "
                            "solver run; on expiry the status is 'unknown'. "
                            "bv_decide can run long on wide datapaths, so raise "
                            "this for large modules."
                        ),
                        "default": 600,
                        "examples": [120, 600],
                    },
                },
                "required": ["cand_id"],
                "additionalProperties": False,
            },
        )

    async def __call__(self, args: Mapping[str, Any], ctx: ToolContext) -> ToolOutput:
        raw_cand = args.get("cand_id")
        if not isinstance(raw_cand, str) or not raw_cand.strip():
            return _error("'cand_id' must be a non-empty string")

        # Args are NOT schema-validated by the runtime, so validate here before
        # they reach _run_verification and return _error on bad input.
        raw_module = args.get("module")
        if raw_module is not None and (
            not isinstance(raw_module, str) or not raw_module.strip()
        ):
            return _error("'module', if given, must be a non-empty string")

        raw_timeout = args.get("timeout_s")
        if raw_timeout is not None and (
            not isinstance(raw_timeout, int)
            or isinstance(raw_timeout, bool)
            or raw_timeout <= 0
        ):
            return _error("'timeout_s', if given, must be a positive integer")

        cand_id = raw_cand.strip()

        view = await resolve_candidate(self.scratch_dir, cand_id)
        if isinstance(view, str):
            return _error(view)

        sides = self._locate(view)
        if isinstance(sides, ToolOutput):
            return sides

        return await self._verify(args, view, sides, ctx)

    # -- locating the two sides ---------------------------------------------

    def _locate(self, view: CandidateView) -> _Sides | ToolOutput:
        """Gathers the pristine and candidate RTL sources for the comparison."""
        baseline_files = view.rtl_files(candidate_side=False)
        candidate_files = view.rtl_files(candidate_side=True)
        if not baseline_files:
            return _error(
                f"no Verilog sources under {view.base_dir}; the candidate store "
                "holds no design to compare against"
            )
        return _Sides(
            baseline_files=tuple(baseline_files),
            candidate_files=tuple(candidate_files),
            files_changed=view.files_changed,
        )

    # -- running the flow ---------------------------------------------------

    async def _verify(
        self,
        args: Mapping[str, Any],
        view: CandidateView,
        sides: _Sides,
        ctx: ToolContext,
    ) -> ToolOutput:
        """Runs the verification backend over the two located sides.

        Runs the (blocking) flow off the event loop in the call's own artifacts
        directory, then writes ``verif.json`` and renders the verdict. The raw
        ``args`` are forwarded so the backend can read parameters added to the
        spec. Mutated: writes ``artifacts/<call-id>/verif.json`` and whatever
        the flow emits under that same directory; commits nothing to git and
        never touches the candidate's index row.
        """
        ctx.report(f"verifying base vs {view.cand_id}")

        out_dir = self.scratch_dir / "artifacts" / _safe_call_id(ctx.call_id)
        out_dir.mkdir(parents=True, exist_ok=True)

        # A real backend spawns solvers/simulators, so gate concurrency on the
        # shared slot and run the blocking flow off the event loop.
        async with ctx.slot(_VERIF_SLOT):
            result = await asyncio.to_thread(_run_verification, args, sides, out_dir)

        payload = _verif_payload(result, view, sides)
        (out_dir / "verif.json").write_text(json.dumps(payload, indent=2))
        payload["verif_path"] = str(out_dir / "verif.json")

        content = _render_verif(result, view, payload)
        return ToolOutput(
            ToolStatus.OK,
            content,
            data=payload,
            view=_verif_view(result, view),
            side_effects="committed",
        )


# ---------------------------------------------------------------------------
# Payloads and presentation
# ---------------------------------------------------------------------------


def _verif_payload(
    result: VerifResult, view: CandidateView, sides: _Sides
) -> dict[str, object]:
    """The verification's machine-readable answer."""
    return {
        "mode": "verify",
        "cand_id": view.cand_id,
        "status": result.status,
        "method": result.method,
        "detail": result.detail,
        "counterexample": result.counterexample,
        "files_changed": list(sides.files_changed),
        "artifacts": [str(path) for path in result.artifacts],
    }


def _render_verif(
    result: VerifResult, view: CandidateView, payload: dict[str, object]
) -> str:
    """Composes the verification's answer, saying plainly what it is worth."""
    lines = [
        f"verify_equivalence on `{view.cand_id}`: **{result.status}** "
        f"({result.method})."
    ]
    if result.detail:
        lines.append(f"- {result.detail}")
    if result.status == "not_equivalent" and result.counterexample:
        lines.append(f"- Counterexample: {result.counterexample}")
    if result.status in ("equivalent", "unknown"):
        lines.append(
            "- This is a screen within the flow's scope, not a full signoff: "
            "recommend the engineer's own formal verification before trusting "
            "the candidate."
        )
    return "\n".join(lines) + "\n\n```json\n" + json.dumps(payload, indent=2) + "\n```"


def _verif_view(result: VerifResult, view: CandidateView) -> dict[str, object]:
    """The verification's render view: the status badge and what it compared."""
    return {
        "mode": "verify",
        "cand_id": view.cand_id,
        "status": result.status,
        "method": result.method,
    }
