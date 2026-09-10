"""The testable core of the equivalence-check tool, decoupled from the apex agent.

This module holds the one function an equivalence backend must implement --
``_run_verification``, which performs the screen through ``_screen`` -- plus the
plain data types it consumes and returns. It imports nothing from the apex agent,
so it can be unit-tested on its own: the enclosing ``equiv_check_tool.py`` (which
does import apex) is only a thin wrapper that resolves the module's two sides from
the candidate store and calls in here.

It is the equiv_check counterpart of ``verif_backend.py``: same integration
pattern, but scoped to one named module and returning the equiv_check verdict
vocabulary (``equiv`` / ``not_equiv`` / ``unsure``) plus the concerns worth
testing. ``_screen`` carries an example LLM call over the gold and candidate RTL,
mirroring how the apex agent's screener (``apex/verify/equiv_screener.py``) asks a
model to judge a rewrite -- wire your own model client into the marked seam.

Integration path: complete ``_screen`` and its tests here, then drop this file
into ``apex/agent/tools/eda_tools/`` and have ``equiv_check_tool.py`` call
``_run_verification`` in place of its screening step, mapping ``ScreenOutcome``
onto the tool's result.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

__all__ = ["ScreenOutcome", "ScreenVerdict", "_Sides", "_run_verification", "_screen"]


ScreenVerdict = Literal["equiv", "not_equiv", "unsure"]
"""The equivalence-check verdict.

``equiv`` and ``not_equiv`` are the backend's decisions; ``unsure`` is an
inconclusive check (no distinguishing behavior found, but not proven equal, or a
bound/timeout reached, or no backend integrated yet). Never a formal proof on its
own -- the tool always recommends the engineer's own signoff.
"""


@dataclass(frozen=True)
class ScreenOutcome:
    """An equivalence backend's answer for one module comparison.

    Attributes:
        verdict: The decision, or ``unsure`` when undecided.
        confidence: How strongly the check backs the verdict, 0..1.
        detail: A human-readable summary of what the check did and found.
        concerns: Concrete situations worth turning into stimulus -- what a
            reviewer should test even when the verdict is ``equiv``.
        counterexample: A distinguishing input/trace when ``not_equiv``, empty
            otherwise.
        artifacts: Files the backend wrote for the run, for the agent to read
            back with bash. Paths under the call's own scratch directory.
    """

    verdict: ScreenVerdict
    confidence: float
    detail: str
    concerns: tuple[str, ...] = ()
    counterexample: str = ""
    artifacts: tuple[Path, ...] = ()


@dataclass(frozen=True)
class _Sides:
    """The two versions of one module an equivalence check compares.

    Attributes:
        module: The module being checked.
        gold_path: The pristine source declaring it.
        candidate_path: The rewritten source declaring it.
        gold_deps: The pristine design's other sources, needed to elaborate it.
        candidate_deps: The candidate's other sources.
        deps_changed: Whether the candidate changed anything besides the
            module's own file, which a single-module check does not exercise.
    """

    module: str
    gold_path: Path
    candidate_path: Path
    gold_deps: tuple[Path, ...]
    candidate_deps: tuple[Path, ...]
    deps_changed: bool


def _screen(
    args: Mapping[str, Any],
    sides: _Sides,
    workdir: Path,
) -> ScreenOutcome:
    """Screens the module's two versions for equivalence with an LLM.

    Example implementation of the equivalence screen: it reads the gold and
    candidate RTL declaring ``sides.module`` and asks a model whether the two are
    logically equivalent, the same inputs the apex agent's screener sends a
    model. Wire a real model client into the marked seam and parse its reply into
    a ``ScreenOutcome``. It must not touch anything outside ``workdir``.

    Args:
        args: The call's raw, already-validated arguments, keyed by the tool
            spec's parameter names. Read any backend-specific parameter (an
            engine choice, a bound) straight from here.
        sides: The two versions of the module and their dependency sources.
        workdir: A private directory for this run's scratch and artifacts.

    Returns:
        The backend's ``ScreenOutcome``. Any artifact paths it names should live
        under ``workdir`` so the agent can read them back.
    """
    gold_code = sides.gold_path.read_text(errors="replace")
    candidate_code = sides.candidate_path.read_text(errors="replace")

    # Build the prompt from the two module sources -- the same inputs the apex
    # agent's equivalence screener sends a model: the gold (pristine) RTL and the
    # candidate rewrite of the same module. Add the unified diff or the dependency
    # sources here too if the check needs them.
    prompt = (
        f"You are checking whether two Verilog modules named {sides.module!r} are "
        "logically equivalent -- their primary outputs agree for every input "
        "sequence.\n\n"
        f"GOLD (pristine) RTL:\n{gold_code}\n\n"
        f"CANDIDATE RTL:\n{candidate_code}\n\n"
        'Answer as JSON: {"verdict": "equiv|not_equiv|unsure", '
        '"confidence": <0..1>, "concerns": ["..."], "counterexample": "..."}.'
    )

    # =========================================================================
    # Example implementation in apex central wires:
    #
    #   reply = call_model(prompt)                 # <-- your provider/client here
    #   parsed = json.loads(reply)                 # (import json at module top)
    #   (workdir / "screen_reply.txt").write_text(reply)   # keep the raw reply
    #   return ScreenOutcome(
    #       verdict=parsed["verdict"],
    #       confidence=float(parsed["confidence"]),
    #       detail=parsed.get("detail", ""),
    #       concerns=tuple(parsed.get("concerns", ())),
    #       counterexample=parsed.get("counterexample", ""),
    #       artifacts=(workdir / "screen_reply.txt",),
    #   )
    #
    # Until the model is wired in, return unsure.
    # =========================================================================
    _ = (args, workdir, prompt)
    return ScreenOutcome(
        verdict="unsure",
        confidence=0.0,
        detail="example LLM screen not wired in; implement _screen in equiv_check_backend.py.",
    )


def _run_verification(
    args: Mapping[str, Any],
    sides: _Sides,
    workdir: Path,
) -> ScreenOutcome:
    """Runs the equivalence check for one module and returns its verdict.

    The entry point the apex wrapper calls. It performs the screen through
    ``_screen`` and returns its ``ScreenOutcome`` unchanged; put any
    orchestration a backend needs around the screen (a fast interface pre-check,
    result post-processing) here, and the screening logic itself in ``_screen``.

    Args:
        args: The call's raw, already-validated arguments.
        sides: The two versions of the module and their dependency sources.
        workdir: A private directory for this run's scratch and artifacts.

    Returns:
        The screen's ``ScreenOutcome``.
    """
    return _screen(args, sides, workdir)
