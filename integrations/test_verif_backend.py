"""Test for the equivalence-verification backend (``verif_backend.py``).

Drives ``_run_verification`` over the reference rv_timer pair -- the same check as

    lake env lean --run Tools/RtlEquiv.lean \\
        sample_designs/rv_timer/timer_core.v \\
        sample_designs/rv_timer_cand-001/timer_core.v out.lean

pointing ``$RTL_EQUIV_BIN`` at the repo's ``bin/rtl-equiv`` wrapper. Runs under
pytest, or standalone: ``python3 integrations/test_verif_backend.py``.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from verif_backend import _run_verification, _Sides, _TOOL_ENV  # noqa: E402

_REPO = Path(__file__).resolve().parent.parent
_WRAPPER = _REPO / "bin" / "rtl-equiv"
_GOLD = _REPO / "sample_designs" / "rv_timer" / "timer_core.v"
_CAND = _REPO / "sample_designs" / "rv_timer_cand-001" / "timer_core.v"


def test_equivalent_rv_timer() -> None:
    """The rv_timer PPA carry-split rewrite verifies as equivalent."""
    os.environ[_TOOL_ENV] = str(_WRAPPER)
    with tempfile.TemporaryDirectory() as td:
        sides = _Sides(
            baseline_files=(_GOLD,),
            candidate_files=(_CAND,),
            files_changed=("timer_core.v",),
        )
        result = _run_verification({}, sides, Path(td))
    assert result.status == "equivalent", result.detail
    assert any(p.name == "equiv.lean" for p in result.artifacts)


if __name__ == "__main__":
    test_equivalent_rv_timer()
    print("PASS test_equivalent_rv_timer")
