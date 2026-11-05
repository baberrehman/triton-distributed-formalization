import TTIRFormal.Lowering

namespace TTIRFormal

def exampleEnv : Environment where
  input := fun _ _ _ => 0
  empty := fun _ _ => 99

def negativeRange : Source.Expr 4 := .makeRange 4 (-2) (by unfold RangeValid; decide)
def zeroRange : Source.Expr 4 := .makeRange 4 0 (by unfold RangeValid; decide)
def composed : Source.Expr 4 := .add negativeRange (.splat 4 7)

macro "check_example" : tactic => `(tactic|
    (simp [composed, negativeRange, zeroRange, lower, lowerSplat, lowerRange,
        Target.eval, Source.eval, exampleEnv]
     <;> decide))

theorem negative_start_example :
    (Target.eval exampleEnv (lower negativeRange) ⟨0, by decide⟩).toInt = -2 := by check_example

theorem range_last_lane_example :
    (Target.eval exampleEnv (lower negativeRange) ⟨3, by decide⟩).toInt = 1 := by check_example

theorem zero_start_example :
    (Target.eval exampleEnv (lower zeroRange) ⟨3, by decide⟩).toNat = 3 := by check_example

theorem singleton_splat_example :
    (Target.eval exampleEnv (lower (.splat 1 7)) ⟨0, by decide⟩).toNat = 7 := by check_example

theorem composed_example :
    (Target.eval exampleEnv (lower composed) ⟨3, by decide⟩).toNat = 8 := by check_example

theorem wrapping_add_example :
    (Source.eval exampleEnv (.add (.splat 1 4294967295) (.splat 1 1))
    ⟨0, by decide⟩).toNat = 0 := by check_example

/-- A hypothetical dropped-offset lowering is observably incorrect. Not a compiler bug report. -/
theorem dropped_offset_counterexample :
    Target.eval exampleEnv (.index 4) ⟨0, by decide⟩ ≠
    Source.eval exampleEnv negativeRange ⟨0, by decide⟩ := by check_example

/-- Applying the singleton optimization to a larger tensor leaves unwritten lanes. -/
theorem oversized_insert_counterexample :
    Target.eval exampleEnv (.insertZero 4 7) ⟨1, by decide⟩ ≠
    Source.eval exampleEnv (.splat 4 7) ⟨1, by decide⟩ := by check_example

theorem empty_range_rejected : ¬ RangeValid 0 0 := by unfold RangeValid; decide
theorem overflowing_range_rejected : ¬ RangeValid 2147483647 2 := by unfold RangeValid; decide

end TTIRFormal