import Std

namespace TTIRFormal

/-- Rank-one, static-shaped tensors of signless 32-bit integers. -/
abbrev Tensor (n : Nat) := Fin n → BitVec 32

structure Environment where
  input : (n : Nat) → Nat → Tensor n
  /-- Arbitrary initial contents, not an assumption that tensor.empty is zero. -/
  empty : (n : Nat) → Tensor n

/-- Deliberately restricted, nonempty signed-i32 make_range domain.
No claim is made that this predicate reproduces every upstream verifier. -/
def RangeValid (start : Int) (n : Nat) : Prop :=
  0 < n ∧ -(2 ^ 31 : Int) ≤ start ∧ start + (n : Int) ≤ 2 ^ 31 - 1

namespace Source

/-- Typed expression trees, not a parser or a complete SSA/control-flow IR. -/
inductive Expr : Nat → Type where
  | input (n id : Nat) : Expr n
  | splat (n : Nat) (value : BitVec 32) : Expr n
  | makeRange (n : Nat) (start : Int) (valid : RangeValid start n) : Expr n
  | add {n : Nat} (lhs rhs : Expr n) : Expr n

def eval (env : Environment) : {n : Nat} → Expr n → Tensor n
  | _, .input n id => env.input n id
  | _, .splat _ value => fun _ => value
  | _, .makeRange _ start _ => fun i => BitVec.ofInt 32 start + BitVec.ofNat 32 i.val
  | _, .add lhs rhs => fun i => eval env lhs i + eval env rhs i

end Source

namespace Target

/-- A denotational tensor/linalg-style subset of the ttadapter stage.
`index` abstracts linalg.generic/index/index_cast/yield; `insertZero`
abstracts tensor.insert at zero into tensor.empty. -/
inductive Expr : Nat → Type where
  | input (n id : Nat) : Expr n
  | fill (n : Nat) (value : BitVec 32) : Expr n
  | insertZero (n : Nat) (value : BitVec 32) : Expr n
  | index (n : Nat) : Expr n
  | add {n : Nat} (lhs rhs : Expr n) : Expr n

def eval (env : Environment) : {n : Nat} → Expr n → Tensor n
  | _, .input n id => env.input n id
  | _, .fill _ value => fun _ => value
  | _, .insertZero n value => fun i => if i.val = 0 then value else env.empty n i
  | _, .index _ => fun i => BitVec.ofNat 32 i.val
  | _, .add lhs rhs => fun i => eval env lhs i + eval env rhs i

end Target

theorem range_lane_bounds (_h : RangeValid start n) (i : Fin n) :
    start ≤ start + (i.val : Int) ∧ start + (i.val : Int) < start + (n : Int) := by
  have hi := i.isLt
  omega

theorem range_lane_signed_bounds (h : RangeValid start n) (i : Fin n) :
    -(2 ^ 31 : Int) ≤ start + (i.val : Int) ∧
      start + (i.val : Int) < 2 ^ 31 - 1 := by
  obtain ⟨_, hs, he⟩ := h
  have hi := i.isLt
  omega

end TTIRFormal