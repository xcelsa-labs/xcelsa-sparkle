"""The testable core of the verification tool, decoupled from the apex agent.

This module holds the one function a verification backend must implement --
``_run_verification`` -- plus the plain data types it consumes and returns. It
imports nothing from the apex agent, so it can be unit-tested on its own: the
enclosing ``verif_tool.py`` (which does import apex) is only a thin wrapper that
resolves the two sides from the candidate store and calls into here.

Integration path: complete ``_run_verification`` and its tests here, then drop
this file into ``apex/agent/tools/eda_tools/`` and have ``verif_tool.py`` import
``VerifStatus``, ``VerifResult``, ``_Sides``, and ``_run_verification`` from it.
The apex-side TODOs (the tool spec's description, its argument schema and
validation, the concurrency pool, and registration) stay in ``verif_tool.py``
and are handled at integration -- they are not part of this file.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

__all__ = ["VerifResult", "VerifStatus", "_Sides", "_run_verification"]

#: Env var naming the `bin/rtl-equiv` wrapper (see the Sparkle repo). Lets this
#: apex-free module locate the tool without knowing the repo layout; falls back
#: to `rtl-equiv` on PATH.
_TOOL_ENV = "RTL_EQUIV_BIN"

#: The verification flow this backend drives, reported as `VerifResult.method`.
_METHOD = "sparkle-rtl-equiv (bv_decide CEC)"

#: Default subprocess wall-clock budget; overridable via `args["timeout_s"]`.
#: bv_decide can run long on wide datapaths, so this is generous.
_DEFAULT_TIMEOUT_S = 600

#: File extensions the pairing logic treats as Verilog/SystemVerilog RTL.
_RTL_SUFFIXES = (".v", ".sv")


VerifStatus = Literal["equivalent", "not_equivalent", "unknown", "error"]
"""How a verification ended.

``equivalent`` and ``not_equivalent`` are verdicts the backend stands behind;
``unknown`` is an inconclusive run (a bound reached, a timeout, or no backend
integrated yet); ``error`` is a flow that could not run to a conclusion at all.
"""


@dataclass(frozen=True)
class VerifResult:
    """A verification backend's answer for one baseline-vs-candidate comparison.

    Attributes:
        status: The verdict, or why there is none.
        method: The flow that produced it (e.g. ``'symbiyosys-bmc'``), or
            ``'none'`` when no backend ran.
        detail: A human-readable summary of what the flow did and found.
        counterexample: A distinguishing input/trace when ``status`` is
            ``not_equivalent``, empty otherwise.
        artifacts: Files the backend wrote for the run, for the agent to read
            back with bash. Paths under the call's own scratch directory.
    """

    status: VerifStatus
    method: str
    detail: str
    counterexample: str = ""
    artifacts: tuple[Path, ...] = ()


@dataclass(frozen=True)
class _Sides:
    """The two versions of a design a verification compares.

    Attributes:
        baseline_files: The pristine design's RTL sources.
        candidate_files: The candidate's RTL sources.
        files_changed: Paths the candidate changed, relative to its tree.
    """

    baseline_files: tuple[Path, ...]
    candidate_files: tuple[Path, ...]
    files_changed: tuple[str, ...]


def _find_tool() -> Path | None:
    """Locates the ``bin/rtl-equiv`` wrapper: ``$RTL_EQUIV_BIN`` then PATH."""
    env = os.environ.get(_TOOL_ENV)
    if env:
        p = Path(env)
        return p if p.exists() else None
    which = shutil.which("rtl-equiv")
    return Path(which) if which else None


def _rtl_files(paths: tuple[Path, ...]) -> list[Path]:
    """The Verilog/SystemVerilog sources among ``paths``, order preserved."""
    return [p for p in paths if p.suffix.lower() in _RTL_SUFFIXES]


def _match(files: list[Path], rel: str) -> Path | None:
    """Finds the file in ``files`` corresponding to changed path ``rel``.

    Prefers a full path-suffix match (``.../rtl/foo.v`` for ``rtl/foo.v``); falls
    back to a basename match so a differently-rooted candidate tree still lines
    up with the baseline.
    """
    rel_norm = rel.replace("\\", "/")
    for p in files:
        if p.as_posix().endswith(rel_norm):
            return p
    name = Path(rel).name
    for p in files:
        if p.name == name:
            return p
    return None


def _declares_module(path: Path, name: str) -> bool:
    """Whether the Verilog file ``path`` declares a ``module <name>``."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return False
    return re.search(rf"\bmodule\s+{re.escape(name)}\b", text) is not None


def _select_pair(sides: _Sides, module: str | None = None) -> tuple[Path, Path] | str:
    """Chooses the single (gold, candidate) file rtl-equiv should compare.

    rtl-equiv checks one file pair (top module vs top module) per call, so this
    resolves the candidate's change to exactly one baseline/candidate file pair.
    When ``module`` is given, the pair is the file declaring it on each side;
    otherwise it is inferred from ``files_changed``. Returns the pair, or an
    explanatory string when no single pair is well defined (which the caller
    surfaces as an ``error`` result).
    """
    base_v = _rtl_files(sides.baseline_files)
    cand_v = _rtl_files(sides.candidate_files)
    if not base_v:
        return "no Verilog sources on the baseline side to compare"
    if not cand_v:
        return "no Verilog sources on the candidate side to compare"

    if module:
        gold = next((p for p in base_v if _declares_module(p, module)), None)
        cand = next((p for p in cand_v if _declares_module(p, module)), None)
        if gold is None:
            return f"module {module!r} is not declared in any baseline Verilog source"
        if cand is None:
            return f"module {module!r} is not declared in any candidate Verilog source"
        return (gold, cand)

    changed = [c for c in sides.files_changed if c.lower().endswith(_RTL_SUFFIXES)]
    if len(changed) == 1:
        gold = _match(base_v, changed[0])
        cand = _match(cand_v, changed[0])
        if gold is None or cand is None:
            return f"changed file {changed[0]!r} is not present on both sides"
        return (gold, cand)
    if not changed:
        # No RTL recorded as changed: only unambiguous when each side has one
        # file (the reference rv_timer shape).
        if len(base_v) == 1 and len(cand_v) == 1:
            return (base_v[0], cand_v[0])
        return "no changed Verilog file identified; cannot pick a pair to compare"
    return (
        f"multiple changed Verilog files {changed}; rtl-equiv checks one pair per "
        "call -- narrow the change or add per-file selection"
    )


def _extract_counterexample(text: str) -> str:
    """Pulls the bv_decide counterexample block out of the tool's output."""
    idx = text.lower().find("counterexample")
    if idx == -1:
        return ""
    return text[idx : idx + 2000].strip()


def _summary_line(lean_text: str) -> str:
    """The 'changed cones (checked): ...' line from a generated proof file."""
    for line in lean_text.splitlines():
        if "changed cones" in line:
            return line.strip()
    return ""


def _run_verification(
    args: Mapping[str, Any],
    sides: _Sides,
    workdir: Path,
) -> VerifResult:
    """Runs the equivalence flow over the two sides and returns its verdict.

    Drives the Sparkle ``bin/rtl-equiv`` wrapper: it parses both Verilog files
    into Sparkle IR, extracts each register's next-state cone and each
    combinational output cone as a pure BitVec function over a shared state/input,
    diffs them, and proves every *changed* cone equal with ``bv_decide`` (a
    kernel-checked SAT decision over all inputs -- combinational equivalence).

    The tool's exit code is the verdict and maps onto ``VerifResult`` as:
      0 EQUIVALENT     -> equivalent
      1 NOT_EQUIVALENT -> not_equivalent (with the bv_decide counterexample)
      2 INCONCLUSIVE   -> unknown (timeout / sorry / lake error)
      3 UNSUPPORTED    -> unknown (register/input signatures differ, e.g.
                          retiming/pipelining -- out of scope for this CEC flow)
      4/other          -> error (bad args, missing file, parse/lower failure)

    Args:
        args: The call's raw, already-validated arguments. ``module`` (str)
            optionally selects the file pair by the module it declares;
            ``timeout_s`` (int) optionally overrides the subprocess budget.
        sides: The pristine and candidate sources, and the candidate's changes.
        workdir: A private directory for this run's scratch and artifacts.

    Returns:
        The backend's ``VerifResult``, with the generated proof file and a run
        log listed under ``artifacts``.
    """
    tool = _find_tool()
    if tool is None:
        return VerifResult(
            status="error",
            method=_METHOD,
            detail=(
                f"rtl-equiv tool not found; set ${_TOOL_ENV} to the bin/rtl-equiv "
                "wrapper or put it on PATH"
            ),
        )

    raw_module = args.get("module")
    module = raw_module if isinstance(raw_module, str) and raw_module.strip() else None
    pair = _select_pair(sides, module)
    if isinstance(pair, str):
        return VerifResult(status="error", method=_METHOD, detail=pair)
    gold, cand = pair

    out_lean = workdir / "equiv.lean"
    raw_timeout = args.get("timeout_s")
    timeout = raw_timeout if isinstance(raw_timeout, int) and raw_timeout > 0 else _DEFAULT_TIMEOUT_S

    try:
        proc = subprocess.run(
            [str(tool), str(gold), str(cand), str(out_lean)],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return VerifResult(
            status="unknown",
            method=_METHOD,
            detail=f"rtl-equiv timed out after {timeout}s on {gold.name} vs {cand.name}",
        )
    except OSError as exc:
        return VerifResult(
            status="error",
            method=_METHOD,
            detail=f"could not run rtl-equiv ({tool}): {exc}",
        )

    combined = proc.stdout + proc.stderr
    log = workdir / "rtl_equiv.log"
    log.write_text(combined)
    artifacts = tuple(p for p in (out_lean, log) if p.exists())

    summary = _summary_line(out_lean.read_text()) if out_lean.exists() else ""
    where = f"{gold.name} vs {cand.name}"
    code = proc.returncode

    if code == 0:
        detail = f"bv_decide proved every changed cone equal ({where})."
        return VerifResult(
            status="equivalent",
            method=_METHOD,
            detail=f"{detail} {summary}".strip(),
            artifacts=artifacts,
        )
    if code == 1:
        return VerifResult(
            status="not_equivalent",
            method=_METHOD,
            detail=f"bv_decide found a distinguishing input ({where}). {summary}".strip(),
            counterexample=_extract_counterexample(combined),
            artifacts=artifacts,
        )
    if code == 2:
        return VerifResult(
            status="unknown",
            method=_METHOD,
            detail=f"rtl-equiv did not complete cleanly ({where}); "
            "timeout, unsupported cone (sorry), or lake error -- see the log.",
            artifacts=artifacts,
        )
    if code == 3:
        return VerifResult(
            status="unknown",
            method=_METHOD,
            detail=(
                f"register/input signatures differ ({where}); this is a sequential "
                "change (retiming/pipelining/FSM re-encode) outside the combinational "
                "CEC flow -- route to a sequential (BMC) engine."
            ),
            artifacts=artifacts,
        )
    return VerifResult(
        status="error",
        method=_METHOD,
        detail=f"rtl-equiv failed to run ({where}); "
        f"bad args, missing file, or parse/lower failure (exit {code}) -- see the log.",
        artifacts=artifacts,
    )
