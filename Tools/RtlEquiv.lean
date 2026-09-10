/-
  RtlEquiv — RTL↔RTL' equivalence check driver (experiment).

  Given two Verilog files (a golden RTL and a candidate RTL), this:

    1. Parses + lowers both into Sparkle IR   (Tools.SVParser.parseAndLower).
    2. Takes the top module of each.
    3. Extracts the per-register next-state cones and the combinational
       output cones, rendering each as a pure `BitVec`-returning Lean
       expression over a SHARED `State`/`Input` (reuses the SVParser
       `Verify` renderer internals).
    4. Diffs cone-by-cone. Identical cones are provably equal (skipped);
       differing cones get a generated `#verify_eq <name>_gold <name>_cand`.
    5. Emits a self-contained `.lean` file you run with `lake env lean`
       (bv_decide must run in the interpreter, not `lake build` — see
       docs/known-issues/KnownIssues.md Issue 2).

  Scope / preconditions (this is a first cut — see the report it prints):
    * Only handles designs the SVParser subset can parse+lower.
    * `#verify_eq` requires the STATE + INPUT signatures to match between
      the two RTLs (state-preserving / combinational edits). If they differ
      (pipelining, retiming, FSM re-encode, reg dup) the tool reports the
      delta and stops — that case needs the sequential engine (SMT/BMC),
      not `#verify_eq`.
    * bv_decide SAT-scales with width×arity; big datapaths won't close.

  Usage:
      lake env lean --run Tools/RtlEquiv.lean gold.v candidate.v [out.lean]
-/

import Tools.SVParser
import Tools.SVParser.Verify
import Sparkle.Backend.CSim

open Sparkle.IR.AST
open Sparkle.IR.Type
open Sparkle.Backend.CSim   -- inferExprWidth, lookupWidth, TypeMap, sanitizeName
open Tools.SVParser
open Tools.SVParser.Lower
open Tools.SVParser.Verify

namespace RtlEquiv

/-- One combinational cone: a single `BitVec width` output, rendered as a
    Lean expression over `s : State` and `i : Input`. -/
structure Cone where
  name  : String   -- sanitized register/output name
  width : Nat
  lean  : String   -- rendered RHS
  deriving Repr, BEq

/-- Flat view of a module: its state (registers), inputs, and all cones. -/
structure ModView where
  modName : String
  regs    : List (String × Nat)   -- State fields (sanitized name, width)
  inputs  : List (String × Nat)   -- Input fields
  cones   : List Cone

/-- Zero-extend / truncate a rendered term from width `src` to `dst`.
    `BitVec.setWidth` truncates when `dst < src` and zero-extends otherwise —
    exactly the SMT `coerce` (`zero_extend` / low-bit `extract`). -/
def coerceL (t : String) (src dst : Nat) : String :=
  if src == dst then t else s!"(BitVec.setWidth {dst} {t})"

/-- Width-correct IR `Expr` → Lean `BitVec {w}` renderer.

    This is the Lean-BitVec twin of `Sparkle.Backend.Smt.emitW`: it emits `e`
    coerced to EXACTLY `w` bits, applying Verilog's operand-width rules via
    `CSim.inferExprWidth`.  Ring ops (add/sub/mul/bitwise/shl, mux, not/neg)
    push the target width down to their operands (truncation commutes);
    comparisons, shr/asr, slice and concat evaluate at natural width, then
    coerce.  `regs`/`inputs` are RAW IR names: refs to them become `s.<f>` /
    `i.<f>` struct fields (sanitized by `leanName`), everything else is a
    literal ref (wires are already inlined before rendering).  Anything
    unhandled (memory `.index`, `.sliceDim`) renders to `sorry` so the cone
    is reported as unsupported rather than crashing. -/
partial def renderW (tm : TypeMap) (regs inputs : List String) : Expr → Nat → String
  | .const v _, w =>
      let m : Int := Int.ofNat (2 ^ w)
      let x := ((((v % m) + m) % m)).toNat
      s!"({x}#{w})"
  | .ref n, w =>
      let base :=
        if regs.contains n then s!"s.{leanName n}"
        else if inputs.contains n then s!"i.{leanName n}"
        else leanName n
      coerceL base (lookupWidth tm n) w
  | .op .mux [c, t, f], w =>
      let cw := max (inferExprWidth tm c) 1
      s!"(if {renderW tm regs inputs c cw} == (0#{cw}) then \
         {renderW tm regs inputs f w} else {renderW tm regs inputs t w})"
  | .op .not [a], w => s!"(~~~ {renderW tm regs inputs a w})"
  | .op .neg [a], w => s!"(- {renderW tm regs inputs a w})"
  | .op .add [a, b], w => s!"({renderW tm regs inputs a w} + {renderW tm regs inputs b w})"
  | .op .sub [a, b], w => s!"({renderW tm regs inputs a w} - {renderW tm regs inputs b w})"
  | .op .mul [a, b], w => s!"({renderW tm regs inputs a w} * {renderW tm regs inputs b w})"
  | .op .and [a, b], w => s!"({renderW tm regs inputs a w} &&& {renderW tm regs inputs b w})"
  | .op .or  [a, b], w => s!"({renderW tm regs inputs a w} ||| {renderW tm regs inputs b w})"
  | .op .xor [a, b], w => s!"({renderW tm regs inputs a w} ^^^ {renderW tm regs inputs b w})"
  | .op .shl [a, b], w => s!"({renderW tm regs inputs a w} <<< {renderW tm regs inputs b w})"
  | .op .shr [a, b], w =>
      let wa := max (inferExprWidth tm a) 1
      coerceL s!"({renderW tm regs inputs a wa} >>> {renderW tm regs inputs b wa})" wa w
  | .op .asr [a, b], w =>
      let wa := max (inferExprWidth tm a) 1
      coerceL s!"(BitVec.sshiftRight' {renderW tm regs inputs a wa} {renderW tm regs inputs b wa})" wa w
  | .op cmp [a, b], w =>
      -- Comparisons: common natural width, 1-bit result zero-extended to `w`
      -- (extending {0,1} = `if bool then 1 else 0` at width `w`).
      let wm := max (max (inferExprWidth tm a) (inferExprWidth tm b)) 1
      let as_ := renderW tm regs inputs a wm
      let bs := renderW tm regs inputs b wm
      let bool? : Option String := match cmp with
        | .eq   => some s!"({as_} == {bs})"
        | .lt_u => some s!"({as_}).ult {bs}"
        | .lt_s => some s!"({as_}).slt {bs}"
        | .le_u => some s!"({as_}).ule {bs}"
        | .le_s => some s!"({as_}).sle {bs}"
        | .gt_u => some s!"({bs}).ult {as_}"
        | .gt_s => some s!"({bs}).slt {as_}"
        | .ge_u => some s!"({bs}).ule {as_}"
        | .ge_s => some s!"({bs}).sle {as_}"
        | _     => none
      match bool? with
      | some b => s!"(if {b} then (1#{w}) else (0#{w}))"
      | none   => s!"(sorry /- unsupported op -/ : BitVec {w})"
  | .concat args, w =>
      if args.isEmpty then s!"(0#{w})"
      else
        let parts := args.map (fun a =>
          renderW tm regs inputs a (max (inferExprWidth tm a) 1))
        let total := args.foldl (fun acc a => acc + max (inferExprWidth tm a) 1) 0
        let joined := match parts with
          | [s] => s
          | many => "(" ++ String.intercalate " ++ " many ++ ")"
        coerceL joined total w
  | .slice inner hi lo, w =>
      let wi := max (inferExprWidth tm inner) 1
      let s := renderW tm regs inputs inner wi
      coerceL s!"(BitVec.extractLsb' {lo} {hi - lo + 1} {s})" (hi - lo + 1) w
  | _, w => s!"(sorry /- unsupported expr -/ : BitVec {w})"

/-- Build a `ModView` from an IR module, reusing the SVParser Verify
    renderer for the hard part (IR Expr → Lean BitVec string). -/
def viewOf (m : Module) : ModView :=
  let model      := extractModel m
  let regNames   := model.registers.map (·.name)
  let regWidths  := model.registers.map (fun r => (r.name, r.width))
  let inputWidths := model.inputs.map (fun i => (i.name, i.width))
  let wireWidths := m.wires.map (fun w => (w.name, w.ty.bitWidth))
  let portWidths := m.inputs.map (fun p => (p.name, p.ty.bitWidth))
  let allWidths  := wireWidths ++ portWidths ++ regWidths ++ inputWidths
  let inputNames := model.inputs.map (·.name)
  -- Width environment for `inferExprWidth` / `lookupWidth`, from every
  -- wire/port/reg/input width the module declares.
  let tm : TypeMap := allWidths.foldl (fun acc (n, w) => acc.insert n (.bitVector w)) {}
  -- assigns for wire-inlining, minus the registers (they are state, not wires)
  let assigns := (collectAssigns m.body).filter (fun (n, _) => !regNames.contains n)
  let render (e : Expr) (w : Nat) : String :=
    renderW tm regNames inputNames (inlineAssigns assigns e) w
  -- Register cones: next-state expression per register.
  let regCones : List Cone := model.registers.map (fun r =>
    { name := leanName r.name, width := r.width, lean := render r.nextExpr r.width })
  -- Combinational output cones: outputs driven by an assign (not a register).
  let outCones : List Cone := m.outputs.filterMap (fun p =>
    if regNames.contains p.name then none
    else match (collectAssigns m.body).find? (·.1 == p.name) with
      | some (_, rhs) => some { name := leanName p.name, width := p.ty.bitWidth, lean := render rhs p.ty.bitWidth }
      | none => none)
  { modName := m.name
    regs   := model.registers.map (fun r => (leanName r.name, r.width))
    inputs := model.inputs.map (fun i => (leanName i.name, i.width))
    cones  := regCones ++ outCones }

/-- Multiset-ish equality on signature lists (order-insensitive). -/
def sameSig (a b : List (String × Nat)) : Bool :=
  a.length == b.length && a.all (b.contains ·) && b.all (a.contains ·)

def structFields (fields : List (String × Nat)) : String :=
  String.intercalate "\n" (fields.map (fun (n, w) => s!"  {n} : BitVec {w}"))

/-- Render the generated equivalence-check `.lean` file, or an explanatory
    message if the two modules' signatures don't line up. -/
def generate (gold cand : ModView) : Except String String := do
  unless sameSig gold.regs cand.regs do
    throw s!"STATE signature differs — registers changed between gold and candidate.\n\
             gold regs: {gold.regs}\n  cand regs: {cand.regs}\n\
             This is a sequential change (pipelining/retiming/reg-dup/FSM re-encode).\n\
             #verify_eq is not applicable; route this module to the SMT/BMC engine."
  unless sameSig gold.inputs cand.inputs do
    throw s!"INPUT signature differs — port interface changed.\n\
             gold inputs: {gold.inputs}\n  cand inputs: {cand.inputs}\n\
             Interface not preserved; equivalence is ill-posed until you map ports."
  -- Diff cones by name (state signature matches, so register cones align).
  let mut changed : List (String × Nat × String × String) := []  -- name, w, goldLean, candLean
  let mut unchanged := 0
  let mut unsupported : List String := []
  let mut onlyGold : List String := []
  for c in gold.cones do
    match cand.cones.find? (·.name == c.name) with
    | none => onlyGold := onlyGold ++ [c.name]
    | some c2 =>
      if (c.lean.splitOn "sorry").length > 1 then unsupported := unsupported ++ [c.name]
      else if (c2.lean.splitOn "sorry").length > 1 then unsupported := unsupported ++ [c2.name]
      else if c.lean == c2.lean then unchanged := unchanged + 1
      else changed := changed ++ [(c.name, c.width, c.lean, c2.lean)]
  let onlyCand := cand.cones.filter (fun c => !(gold.cones.any (·.name == c.name))) |>.map (·.name)

  -- NB: emitted at TOP LEVEL (no `namespace`). `#verify_eq`'s success-check
  -- looks up the generated theorem by its UNQUALIFIED name, so wrapping it in
  -- a namespace makes it report a false ❌ even when bv_decide succeeds.
  let header := s!"/- AUTO-GENERATED by Tools/RtlEquiv.lean — module `{gold.modName}` vs `{cand.modName}` -/\n\
    import Sparkle.Verification.Equivalence\n\n\
    structure RE_State where\n{structFields gold.regs}\n  deriving DecidableEq, Repr, BEq, Inhabited\n\n\
    structure RE_Input where\n{structFields gold.inputs}\n  deriving DecidableEq, Repr, BEq, Inhabited\n"

  -- Emit a DIRECT theorem per changed cone rather than `#verify_eq`: a
  -- counterexample then becomes a hard elaboration error (nonzero exit),
  -- which is the reliable pass/fail signal from a subprocess. (`#verify_eq`
  -- prints a misleading ✅ because its log-check races bv_decide's deferred
  -- error.) `#print axioms` confirms a clean (no-sorry) proof on success.
  let mkThm (n : String) (w : Nat) (gl cl : String) : String :=
    String.intercalate "\n"
      [ s!"def {n}_gold (s : RE_State) (i : RE_Input) : BitVec {w} := {gl}",
        s!"def {n}_cand (s : RE_State) (i : RE_Input) : BitVec {w} := {cl}",
        s!"theorem {n}_equiv : {n}_gold = {n}_cand := by",
        s!"  funext s i",
        s!"  unfold {n}_gold {n}_cand",
        s!"  bv_decide",
        s!"#print axioms {n}_equiv" ]
  let defs := String.intercalate "\n\n" (changed.map (fun (n, w, gl, cl) => mkThm n w gl cl))

  let summary := s!"\n/- SUMMARY\n\
    changed cones (checked): {changed.length}  →  {changed.map (·.1)}\n\
    unchanged cones (skipped, provably equal): {unchanged}\n\
    unsupported (rendered to `sorry`, NOT checked): {unsupported}\n\
    cones only in gold: {onlyGold}\n\
    cones only in candidate: {onlyCand}\n\
    -/\n"

  pure (header ++ defs ++ "\n" ++ summary)

/-- Parse a file, lower it, return the top module. -/
def topModuleOf (path : String) : IO Module := do
  let src ← IO.FS.readFile path
  match parseAndLower src with
  | .error e => throw (IO.userError s!"parse/lower failed for {path}:\n{e}")
  | .ok design =>
    match design.findModule design.topModule with
    | some m => pure m
    | none => throw (IO.userError s!"no top module `{design.topModule}` in {path}")

/-- Main entry: transpile both, diff cones, write the check file, and try to
    run it through `lake env lean`. Returns a machine-readable exit code:

      0  EQUIVALENT       — every changed cone proven equal
      1  NOT_EQUIVALENT   — bv_decide found a counterexample
      2  INCONCLUSIVE      — check did not complete cleanly (timeout/sorry/lake err)
      3  UNSUPPORTED      — state/input signatures differ (retiming/pipeline/…)
      4  USAGE / IO error — (handled in `main`)
-/
def equivCheck (goldPath candPath outPath : String) : IO UInt8 := do
  IO.println s!"[rtl-equiv] gold = {goldPath}"
  IO.println s!"[rtl-equiv] cand = {candPath}"
  let gm ← topModuleOf goldPath
  let cm ← topModuleOf candPath
  IO.println s!"[rtl-equiv] top modules: `{gm.name}` vs `{cm.name}`"
  match generate (viewOf gm) (viewOf cm) with
  | .error msg =>
    IO.println "[rtl-equiv] ✗ cannot use #verify_eq for this pair:\n"
    IO.println msg
    pure 3
  | .ok content =>
    IO.FS.writeFile outPath content
    IO.println s!"[rtl-equiv] wrote check file: {outPath}"
    IO.println "[rtl-equiv] running it through `lake env lean` (bv_decide) ...\n"
    let out ← IO.Process.output { cmd := "lake", args := #["env", "lean", outPath] }
    IO.print out.stdout
    unless out.stderr.isEmpty do IO.eprint out.stderr
    let combined := out.stdout ++ out.stderr
    let hasCex := (combined.splitOn "counterexample").length > 1
    IO.println "\n[rtl-equiv] ─────────────── VERDICT ───────────────"
    if out.exitCode == 0 && !hasCex then
      IO.println "[rtl-equiv] ✅ EQUIVALENT — every changed cone proven equal (bv_decide, no sorry)."
      pure 0
    else if hasCex then
      IO.println "[rtl-equiv] ❌ NOT EQUIVALENT — bv_decide found a counterexample (see assignment above)."
      pure 1
    else
      IO.println s!"[rtl-equiv] ⚠ INCONCLUSIVE — check did not complete cleanly (exit {out.exitCode}); see errors above."
      pure 2

def main (args : List String) : IO Unit := do
  match args with
  | gold :: cand :: rest =>
    let code ← try equivCheck gold cand (rest.head?.getD "RtlEquivGen.lean")
      catch e => do
        IO.eprintln s!"[rtl-equiv] ✗ error: {e}"
        pure (4 : UInt8)
    IO.Process.exit code
  | _ =>
    IO.eprintln "usage: lake env lean --run Tools/RtlEquiv.lean <gold.v> <candidate.v> [out.lean]"
    IO.Process.exit 4

end RtlEquiv

def main (args : List String) : IO Unit := RtlEquiv.main args
