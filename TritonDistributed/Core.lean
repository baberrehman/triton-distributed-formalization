import Std

namespace TritonDistributed

inductive DType where
  | i32 | i64 | f16 | f32
  deriving DecidableEq, Repr

structure Ty where
  dtype : DType
  size : Nat
  deriving DecidableEq, Repr

abbrev Rank := Nat
abbrev Var := Nat
abbrev Addr := Nat

inductive Scope where
  | gpu | system
  deriving DecidableEq, Repr

inductive Ordering where
  | relaxed | acquire | release | acqRel
  deriving DecidableEq, Repr

structure Ctx where
  world : Nat
  vars : Var → Option Ty

inductive Expr where
  | var (id : Var)
  | rank (axis : Int)
  | numRanks (axis : Int)
  | symmAt (ptr : Expr) (target : Rank)
  | notify (signalPtr rank signalValue : Expr) (isAdd : Bool) (scope : Scope)
  | wait (signalPtr count waitValue : Expr) (scope : Scope) (ordering : Ordering)
  | consumeToken (value token : Expr)
  | load (ptr : Expr)
  | store (ptr value : Expr)
  deriving Repr

inductive Value where
  | tile (ty : Ty) (payload : List Int)
  | i32 (value : Int)
  | i64 (value : Int)
  | pointer (ty : Ty) (owner : Rank) (addr : Addr) (symmetric : Bool)
  | token (signalAddr : Addr) (observed : Nat) (scope : Scope) (ordering : Ordering)
  | unit
  deriving DecidableEq, Repr

structure State where
  world : Nat
  currentRank : Rank
  memory : Rank → Addr → Option Value
  cellType : Rank → Addr → Option Ty
  signals : Rank → Addr → Nat
  signalOwner : Rank → Addr → Rank

inductive Result where
  | value (value : Value)
  | blocked
  deriving DecidableEq, Repr

def Env := Var → Option Value

def ValueHasType (world : Nat) (value : Value) (ty : Ty) : Prop :=
  match value with
  | .tile actual payload => actual = ty ∧ payload.length = ty.size
  | .i32 _ => ty = ⟨.i32, 1⟩
  | .i64 _ => ty = ⟨.i64, 1⟩
  | .pointer actual owner _ _ => actual = ty ∧ owner < world
  | .token _ _ _ _ => ty = ⟨.i32, 1⟩
  | .unit => ty = ⟨.i32, 0⟩

def EnvHasType (Γ : Ctx) (env : Env) : Prop :=
  ∀ id ty value, Γ.vars id = some ty → env id = some value →
    ValueHasType Γ.world value ty

def StoreWellTyped (s : State) : Prop :=
  ∀ rank addr ty value,
    rank < s.world → s.cellType rank addr = some ty →
    s.memory rank addr = some value → ValueHasType s.world value ty

/-- Abstract condition supplied by the synchronization and memory model. -/
def NotificationVisible (s : State) (rank : Rank) (addr : Addr) (scope : Scope) : Prop :=
  s.signals rank addr > 0 ∧ s.signalOwner rank addr < s.world ∧
    (scope = .gpu ∨ scope = .system)

inductive HasType : Ctx → Expr → Ty → Prop where
  | var {Γ id ty} : Γ.vars id = some ty → HasType Γ (.var id) ty
  | rank {Γ axis} : HasType Γ (.rank axis) ⟨.i32, 1⟩
  | numRanks {Γ axis} : HasType Γ (.numRanks axis) ⟨.i32, 1⟩
    | symmAt {Γ ptr target ty} :
      HasType Γ ptr ty → target < Γ.world → HasType Γ (.symmAt ptr target) ty
  | notify {Γ p r v add scope} :
      HasType Γ p ⟨.i64, 1⟩ → HasType Γ r ⟨.i32, 1⟩ →
      HasType Γ v ⟨.i64, 1⟩ → HasType Γ (.notify p r v add scope) ⟨.i32, 0⟩
  | wait {Γ p n v scope ord} :
      HasType Γ p ⟨.i64, 1⟩ → HasType Γ n ⟨.i32, 1⟩ →
      HasType Γ v ⟨.i64, 1⟩ → HasType Γ (.wait p n v scope ord) ⟨.i32, 1⟩
  | consumeToken {Γ value token ty} :
      HasType Γ value ty → HasType Γ token ⟨.i32, 1⟩ →
      HasType Γ (.consumeToken value token) ty
  | load {Γ ptr ty} : HasType Γ ptr ty → HasType Γ (.load ptr) ty
  | store {Γ ptr value ty} :
      HasType Γ ptr ty → HasType Γ value ty →
      HasType Γ (.store ptr value) ⟨.i32, 0⟩

inductive Eval (s : State) (env : Env) : Expr → Result → Prop where
  | var {id value} : env id = some value → Eval s env (.var id) (.value value)
  | rank {axis} : s.currentRank < s.world →
      Eval s env (.rank axis) (.value (.i32 s.currentRank))
  | numRanks {axis} : Eval s env (.numRanks axis) (.value (.i32 s.world))
    | symmAt {id ty owner addr target} :
      env id = some (.pointer ty owner addr true) → target < s.world →
      Eval s env (.symmAt (.var id) target)
        (.value (.pointer ty target addr true))
  | notify {id rank signalAddr signalValue isAdd scope} :
      env id = some (.pointer ⟨.i64, 1⟩ rank signalAddr true) →
      rank < s.world →
      Eval s env (.notify (.var id) (.rank rank) (.var signalValue) isAdd scope)
        (.value .unit)
  | waitReady {id rank addr count expected scope ordering} :
      env id = some (.pointer ⟨.i64, 1⟩ rank addr true) →
      count > 0 → expected ≤ s.signals rank addr →
      NotificationVisible s rank addr scope →
      Eval s env (.wait (.var id) (.var count) (.var expected) scope ordering)
        (.value (.token addr expected scope ordering))
  | waitBlocked {id rank addr count expected scope ordering} :
      env id = some (.pointer ⟨.i64, 1⟩ rank addr true) →
      count > 0 → s.signals rank addr < expected →
      Eval s env (.wait (.var id) (.var count) (.var expected) scope ordering) .blocked
  | consumeToken {id tokenId value addr observed scope ordering} :
      env id = some value → env tokenId = some (.token addr observed scope ordering) →
      Eval s env (.consumeToken (.var id) (.var tokenId)) (.value value)
  | load {id ty rank addr value} :
      env id = some (.pointer ty rank addr true) → rank < s.world →
      s.cellType rank addr = some ty → s.memory rank addr = some value →
      Eval s env (.load (.var id)) (.value value)
  | store {pId vId ty rank addr value} :
      env pId = some (.pointer ty rank addr true) → rank < s.world →
      env vId = some value →
      Eval s env (.store (.var pId) (.var vId)) (.value .unit)

theorem eval_deterministic (s : State) (env : Env) (e : Expr)
    (r₁ r₂ : Result) (h₁ : Eval s env e r₁) (h₂ : Eval s env e r₂) : r₁ = r₂ := by
  cases h₁ <;> cases h₂ <;> simp_all <;> omega

theorem eval_var_preservation (Γ : Ctx) (s : State) (env : Env)
    (hworld : Γ.world = s.world) (henv : EnvHasType Γ env)
    (id : Var) (ty : Ty) (value : Value)
    (ht : HasType Γ (.var id) ty) (he : Eval s env (.var id) (.value value)) :
    ValueHasType s.world value ty := by
  cases ht with
  | var hlookup =>
      cases he with
      | var hvalue => simpa [hworld] using henv id ty value hlookup hvalue

theorem eval_rank_preservation (s : State) (env : Env) (axis : Int)
    (he : Eval s env (.rank axis) (.value (.i32 s.currentRank))) :
    ValueHasType s.world (.i32 s.currentRank) ⟨.i32, 1⟩ := by
  rfl

theorem eval_wait_preservation (s : State) (env : Env)
    (id : Var) (count expected : Nat) (scope : Scope) (ordering : Ordering)
    (he : Eval s env
      (.wait (.var id) (.var count) (.var expected) scope ordering)
      (.value (.token addr expected scope ordering))) :
    ValueHasType s.world (.token addr expected scope ordering) ⟨.i32, 1⟩ := by
  rfl

theorem eval_symmAt_safe (s : State) (env : Env) (id : Var)
  (ty : Ty) (owner addr target : Rank)
  (he : Eval s env (.symmAt (.var id) target)
      (.value (.pointer ty target addr true))) :
    ValueHasType s.world (.pointer ty target addr true) ty := by
  cases he with
  | symmAt hptr hbound => exact ⟨rfl, hbound⟩

theorem eval_load_preservation (s : State) (env : Env)
    (hstore : StoreWellTyped s) (id : Var)
    (value : Value)
    (he : Eval s env (.load (.var id)) (.value value)) :
  ∃ (ty : Ty) (rank : Rank) (addr : Addr), ValueHasType s.world value ty := by
  cases he with
  | @load id' ty' rank' addr' value' hptr hbound hcell hmem =>
      exact ⟨ty', rank', addr', hstore rank' addr' ty' value hbound hcell hmem⟩

theorem wait_success_has_visible_notification (s : State) (env : Env)
    (id : Var) (count expected : Nat) (scope : Scope) (ordering : Ordering)
    (he : Eval s env
      (.wait (.var id) (.var count) (.var expected) scope ordering)
      (.value (.token addr expected scope ordering))) :
    ∃ rank, NotificationVisible s rank addr scope := by
  cases he with
  | waitReady hptr hcount hready hvisible => exact ⟨_, hvisible⟩

theorem wait_blocked_below_expected (s : State) (env : Env)
    (id : Var) (count expected : Nat) (scope : Scope) (ordering : Ordering)
    (he : Eval s env
      (.wait (.var id) (.var count) (.var expected) scope ordering) .blocked) :
    ∃ rank addr, s.signals rank addr < expected := by
  cases he with
  | waitBlocked hptr hcount hbelow => exact ⟨_, _, hbelow⟩

end TritonDistributed
