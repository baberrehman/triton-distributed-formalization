import TTIRFormal.Core

namespace TTIRFormal

/-- The rank-one specialization of SplatConverter's all-dimensions-one test. -/
def lowerSplat (n : Nat) (value : BitVec 32) : Target.Expr n :=
  if n = 1 then .insertZero n value else .fill n value

/-- MakeRangeConverter: index generation, optionally followed by offset addition. -/
def lowerRange (n : Nat) (start : Int) : Target.Expr n :=
  if start = 0 then .index n
  else .add (.index n) (.fill n (BitVec.ofInt 32 start))

def lower : {n : Nat} → Source.Expr n → Target.Expr n
  | _, .input n id => .input n id
  | _, .splat n value => lowerSplat n value
  | _, .makeRange n start _ => lowerRange n start
  | _, .add lhs rhs => .add (lower lhs) (lower rhs)

theorem lower_splat_correct (env : Environment) (n : Nat) (value : BitVec 32) :
    Target.eval env (lowerSplat n value) = Source.eval env (.splat n value) := by
  funext i
  unfold lowerSplat
  split
  · rename_i hn
    have hi : i.val = 0 := by have hb := i.isLt; omega
    simp [Target.eval, Source.eval, hi]
  · simp [Target.eval, Source.eval]

theorem lower_range_correct (env : Environment) (n : Nat) (start : Int)
    (valid : RangeValid start n) :
    Target.eval env (lowerRange n start) = Source.eval env (.makeRange n start valid) := by
  funext i
  unfold lowerRange
  split
  · rename_i hz
    subst start
    simp [Target.eval, Source.eval]
  · simp [Target.eval, Source.eval, BitVec.add_comm]

/-- Universal semantic preservation for every modeled expression and environment,
including every choice of initial contents for tensor.empty. -/
theorem lowering_correct (env : Environment) (e : Source.Expr n) :
    Target.eval env (lower e) = Source.eval env e := by
  induction e with
  | input id => simp [lower, Target.eval, Source.eval]
  | splat value => simpa only [lower] using lower_splat_correct env _ value
  | makeRange start valid => simpa only [lower] using lower_range_correct env _ start valid
  | add lhs rhs ihl ihr =>
    funext i
    simp only [lower, Target.eval, Source.eval, ihl, ihr]

theorem lowering_lane_correct (env : Environment) (e : Source.Expr n) (i : Fin n) :
    Target.eval env (lower e) i = Source.eval env e i := by
  rw [lowering_correct]

theorem source_ignores_empty (env₁ env₂ : Environment)
    (h : env₁.input = env₂.input) (e : Source.Expr n) :
    Source.eval env₁ e = Source.eval env₂ e := by
  induction e with
  | input id => simp only [Source.eval, h]
  | splat value => simp only [Source.eval]
  | makeRange start valid => simp only [Source.eval]
  | add lhs rhs ihl ihr =>
    funext i
    simp only [Source.eval, ihl, ihr]

theorem lowering_ignores_empty (env₁ env₂ : Environment)
    (h : env₁.input = env₂.input) (e : Source.Expr n) :
    Target.eval env₁ (lower e) = Target.eval env₂ (lower e) := by
  rw [lowering_correct, lowering_correct]
  exact source_ignores_empty env₁ env₂ h e

end TTIRFormal