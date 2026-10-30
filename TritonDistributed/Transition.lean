import TritonDistributed.Core

namespace TritonDistributed

/-- A token records the signal observation that orders a later load. -/
structure OrderingWitness where
  signalRank : Rank
  signalAddr : Addr
  expected : Nat
  scope : Scope
  ordering : Ordering
  deriving DecidableEq, Repr

structure ConsumedOrdering where
  valueVar : Var
  tokenVar : Var
  signalAddr : Addr
  rank : Rank
  deriving DecidableEq, Repr

structure PendingToken where
  tokenVar : Var
  signalRank : Rank
  signalAddr : Addr
  expected : Nat
  scope : Scope
  ordering : Ordering
  deriving DecidableEq, Repr

structure Machine where
  state : State
  env : Env
  witnesses : List OrderingWitness
  pending : List PendingToken
  consumed : List ConsumedOrdering

inductive Action where
  | notify (rank addr value : Nat) (isAdd : Bool) (scope : Scope)
  | wait (rank addr expected : Nat) (tokenVar : Var) (scope : Scope) (ordering : Ordering)
  | consume (valueVar tokenVar : Var)
  | load (ptrVar : Var)
  deriving DecidableEq, Repr

def setSignal (s : State) (rank addr value : Nat) : State :=
  { s with signals := fun r a => if r = rank ∧ a = addr then value else s.signals r a }

def addSignal (s : State) (rank addr value : Nat) : State :=
  { s with signals := fun r a =>
      if r = rank ∧ a = addr then s.signals r a + value else s.signals r a }

inductive Step : Machine → Action → Machine → Prop where
  | notifySet {m rank addr value scope} :
      rank < m.state.world →
      Step m (.notify rank addr value false scope)
        { m with state := setSignal m.state rank addr value }
  | notifyAdd {m rank addr value scope} :
      rank < m.state.world →
      Step m (.notify rank addr value true scope)
        { m with state := addSignal m.state rank addr value }
  | wait {m rank addr expected tokenVar scope ordering} :
      expected ≤ m.state.signals rank addr →
      NotificationVisible m.state rank addr scope →
        Step m (.wait rank addr expected tokenVar scope ordering)
        { m with
          witnesses := (⟨rank, addr, expected, scope, ordering⟩ :: m.witnesses),
          pending := (⟨tokenVar, rank, addr, expected, scope, ordering⟩ :: m.pending) }
  | consume {m valueVar tokenVar ty rank addr tokenAddr observed scope ordering} :
      m.env valueVar = some (.pointer ty rank addr true) →
      m.env tokenVar = some (.token tokenAddr observed scope ordering) →
      tokenAddr = addr →
      (∃ p ∈ m.pending, p.tokenVar = tokenVar ∧ p.signalRank = rank ∧
        p.signalAddr = addr ∧ p.scope = scope ∧ p.ordering = ordering) →
      Step m (.consume valueVar tokenVar)
        { m with
          pending := m.pending.filter (fun p => p.tokenVar ≠ tokenVar),
          consumed := ⟨valueVar, tokenVar, tokenAddr, rank⟩ :: m.consumed }
  | load {m ptrVar ty rank addr} :
      m.env ptrVar = some (.pointer ty rank addr true) →
      (∃ c ∈ m.consumed, c.valueVar = ptrVar ∧ c.rank = rank ∧ c.signalAddr = addr) →
      Step m (.load ptrVar) m

def SignalReady (s : State) (rank addr expected : Nat) : Prop :=
  expected ≤ s.signals rank addr

def WellTypedMachine (Γ : Ctx) (m : Machine) : Prop :=
  Γ.world = m.state.world ∧
  EnvHasType Γ m.env ∧
  StoreWellTyped m.state

theorem notify_set_preserves_signals (m m' : Machine) (rank addr value : Nat) (scope : Scope)
    (h : Step m (.notify rank addr value false scope) m') :
    m'.state.signals rank addr = value := by
  cases h
  simp [setSignal]

theorem notify_add_preserves_signals (m m' : Machine) (rank addr value : Nat) (scope : Scope)
    (h : Step m (.notify rank addr value true scope) m') :
    m'.state.signals rank addr = m.state.signals rank addr + value := by
  cases h
  simp [addSignal]

theorem wait_step_adds_witness (m m' : Machine) (rank addr expected : Nat)
  (tokenVar : Var) (scope : Scope) (ordering : Ordering)
  (h : Step m (.wait rank addr expected tokenVar scope ordering) m') :
    ∃ w ∈ m'.witnesses,
      w.signalRank = rank ∧ w.signalAddr = addr ∧ w.expected = expected := by
  cases h
  exact ⟨_, List.mem_cons_self, rfl, rfl, rfl⟩

theorem load_requires_ordering_witness (m m' : Machine) (ptrVar : Var)
    (h : Step m (.load ptrVar) m') :
    ∃ ty rank addr, m.env ptrVar = some (.pointer ty rank addr true) ∧
      ∃ c ∈ m.consumed, c.valueVar = ptrVar ∧ c.rank = rank ∧ c.signalAddr = addr := by
  cases h with
  | load hptr hc =>
      obtain ⟨c, hcmem, hvar, hrank, haddr⟩ := hc
      exact ⟨_, _, _, hptr, c, hcmem, hvar, hrank, haddr⟩

theorem load_requires_consume_token (m m' : Machine) (ptrVar : Var)
    (h : Step m (.load ptrVar) m') :
    ∃ c ∈ m.consumed, c.valueVar = ptrVar := by
  rcases load_requires_ordering_witness m m' ptrVar h with
    ⟨ty, rank, addr, hptr, c, hc, hvar, hrank, haddr⟩
  exact ⟨c, hc, hvar⟩

theorem consume_requires_wait_token (m m' : Machine) (valueVar tokenVar : Var)
    (h : Step m (.consume valueVar tokenVar) m') :
    ∃ p ∈ m.pending, p.tokenVar = tokenVar := by
  cases h with
  | consume _ _ _ hp =>
      obtain ⟨p, hpmem, htoken, _, _, _, _⟩ := hp
      exact ⟨p, hpmem, htoken⟩

def PendingTokenHasWait (history : List Action) (p : PendingToken) : Prop :=
  ∃ before after,
    history = before ++
      [.wait p.signalRank p.signalAddr p.expected p.tokenVar p.scope p.ordering] ++ after

def ConsumedOrderingHasWaitConsume (history : List Action) (c : ConsumedOrdering) : Prop :=
  ∃ before middle after expected scope ordering,
    history = before ++
      [.wait c.rank c.signalAddr expected c.tokenVar scope ordering] ++ middle ++
      [.consume c.valueVar c.tokenVar] ++ after

def PendingTokensHaveOrigins (history : List Action) (pending : List PendingToken) : Prop :=
  ∀ p, p ∈ pending → PendingTokenHasWait history p

def ConsumedOrderingsHaveOrigins (history : List Action)
    (consumed : List ConsumedOrdering) : Prop :=
  ∀ c, c ∈ consumed → ConsumedOrderingHasWaitConsume history c

theorem pending_token_origin_append (history actions : List Action) (p : PendingToken)
    (h : PendingTokenHasWait history p) :
    PendingTokenHasWait (history ++ actions) p := by
  rcases h with ⟨before, after, rfl⟩
  exact ⟨before, after ++ actions, by simp [List.append_assoc]⟩

theorem consumed_ordering_origin_append (history actions : List Action) (c : ConsumedOrdering)
    (h : ConsumedOrderingHasWaitConsume history c) :
    ConsumedOrderingHasWaitConsume (history ++ actions) c := by
  rcases h with ⟨before, middle, after, expected, scope, ordering, rfl⟩
  exact ⟨before, middle, after ++ actions, expected, scope, ordering,
    by simp [List.append_assoc]⟩

inductive Trace : Machine → List Action → Machine → Prop where
  | nil (m : Machine) : Trace m [] m
  | cons {m₁ m₂ m₃ action actions} :
      Step m₁ action m₂ → Trace m₂ actions m₃ → Trace m₁ (action :: actions) m₃

theorem trace_preserves_capability_origins
  (historyPrefix : List Action) (m₁ m₂ : Machine) (actions : List Action)
  (hpending : PendingTokensHaveOrigins historyPrefix m₁.pending)
  (hconsumed : ConsumedOrderingsHaveOrigins historyPrefix m₁.consumed)
    (htrace : Trace m₁ actions m₂) :
    PendingTokensHaveOrigins (historyPrefix ++ actions) m₂.pending ∧
      ConsumedOrderingsHaveOrigins (historyPrefix ++ actions) m₂.consumed := by
  induction htrace generalizing historyPrefix with
  | nil => simpa using And.intro hpending hconsumed
  | cons hstep htail ih =>
      cases hstep with
        | notifySet hrank =>
          rename_i rank addr value scope
          let a : Action := .notify rank addr value false scope
          let one : List Action := [a]
          simpa [one, List.append_assoc] using
            (ih (historyPrefix ++ one)
              (by intro p hp; exact pending_token_origin_append historyPrefix one p (hpending p hp))
              (by intro c hc; exact consumed_ordering_origin_append historyPrefix one c (hconsumed c hc)))
        | notifyAdd hrank =>
          rename_i rank addr value scope
          let a : Action := .notify rank addr value true scope
          let one : List Action := [a]
          simpa [one, List.append_assoc] using
            (ih (historyPrefix ++ one)
              (by intro p hp; exact pending_token_origin_append historyPrefix one p (hpending p hp))
              (by intro c hc; exact consumed_ordering_origin_append historyPrefix one c (hconsumed c hc)))
        | @wait rank addr expected tokenVar scope ordering hready hvisible =>
          let a : Action := .wait rank addr expected tokenVar scope ordering
          have hrec := ih (historyPrefix ++ [a])
            (by
              intro p hp
              simp only [List.mem_cons] at hp
              rcases hp with rfl | hp
              · exact ⟨historyPrefix, [], by simp [a]⟩
              · exact pending_token_origin_append historyPrefix [a] p (hpending p hp))
            (by
              intro c hc
              exact consumed_ordering_origin_append historyPrefix [a] c (hconsumed c hc))
          simpa [a, List.append_assoc] using hrec
        | @consume valueVar tokenVar ty rank addr tokenAddr observed scope ordering
            hptr htoken haddr hp =>
          let a : Action := .consume valueVar tokenVar
          have hrec := ih (historyPrefix ++ [a])
            (by
              intro p hp'
              exact pending_token_origin_append historyPrefix [a] p
                (hpending p ((List.mem_filter.mp hp').1)))
            (by
              intro c hc
              simp only [List.mem_cons] at hc
              rcases hc with rfl | hc
              · rcases hp with ⟨p, hp, htokenVar, hrank, hpaddr, hscope, hordering⟩
                rcases hpending p hp with ⟨before, after, hhistory⟩
                subst hhistory
                refine ⟨before, after, [], p.expected, p.scope, p.ordering, ?_⟩
                simp [a, htokenVar, hrank, hpaddr, hscope, hordering,
                  List.append_assoc, haddr]
              · exact consumed_ordering_origin_append historyPrefix [a] c
                  (hconsumed c hc))
          simpa [a, List.append_assoc] using hrec
        | @load ptrVar ty rank addr hptr hc =>
          let a : Action := .load ptrVar
          have hrec := ih (historyPrefix ++ [a])
            (by
              intro p hp
              exact pending_token_origin_append historyPrefix [a] p (hpending p hp))
            (by
              intro c hc
              exact consumed_ordering_origin_append historyPrefix [a] c (hconsumed c hc))
          simpa [a, List.append_assoc] using hrec

theorem load_has_prior_wait_and_consume
  (initial final : Machine) (actions : List Action)
    (hpending : initial.pending = []) (hconsumed : initial.consumed = [])
    (htrace : Trace initial actions final)
    (hload : Step final (.load ptrVar) final) :
    ∃ before middle after ty rank addr tokenVar expected scope ordering,
      actions = before ++
        [.wait rank addr expected tokenVar scope ordering] ++ middle ++
        [.consume ptrVar tokenVar] ++ after ∧
      final.env ptrVar = some (.pointer ty rank addr true) := by
  have horig := trace_preserves_capability_origins [] initial final actions
    (by intro p hp; simp [hpending] at hp)
    (by intro c hc; simp [hconsumed] at hc) htrace
  rcases load_requires_ordering_witness final final ptrVar hload with
    ⟨ty, rank, addr, hptr, c, hc, hvar, hrank, haddr⟩
  rcases horig.2 c hc with ⟨before, middle, after, expected, scope, ordering, hdecomp⟩
  have hptr' : final.env ptrVar = some (.pointer ty c.rank c.signalAddr true) := by
    simpa [hvar, hrank, haddr] using hptr
  refine ⟨before, middle, after, ty, c.rank, c.signalAddr, c.tokenVar,
    expected, scope, ordering, ?_, hptr'⟩
  simpa [hvar, hrank, haddr] using hdecomp

theorem trace_preserves_world (Γ : Ctx) (m₁ m₂ : Machine) (actions : List Action)
    (hwm : m₁.state.world = Γ.world)
    (h : Trace m₁ actions m₂) : m₂.state.world = Γ.world := by
  induction h with
  | nil => exact hwm
  | cons hstep htrace ih =>
      cases hstep <;> simp_all [setSignal, addSignal]

theorem step_preserves_well_typed (Γ : Ctx) (m m' : Machine) (action : Action)
    (hwt : WellTypedMachine Γ m) (hstep : Step m action m') :
    WellTypedMachine Γ m' := by
    rcases hwt with ⟨hworld, henv, hstore⟩
    cases hstep with
    | notifySet hrank =>
        exact ⟨by simpa [setSignal] using hworld, henv, by simpa [setSignal] using hstore⟩
    | notifyAdd hrank =>
        exact ⟨by simpa [addSignal] using hworld, henv, by simpa [addSignal] using hstore⟩
    | wait hready hvisible =>
      exact ⟨hworld, henv, hstore⟩
    | consume hptr htoken haddr hp =>
      exact ⟨hworld, henv, hstore⟩
    | load hptr hc =>
      exact ⟨hworld, henv, hstore⟩

theorem trace_preserves_well_typed (Γ : Ctx) (m₁ m₂ : Machine) (actions : List Action)
    (hwt : WellTypedMachine Γ m₁) (htrace : Trace m₁ actions m₂) :
    WellTypedMachine Γ m₂ := by
  induction htrace with
  | nil => exact hwt
  | cons hstep htrace ih =>
      exact ih (step_preserves_well_typed Γ _ _ _ hwt hstep)

theorem wait_progress (m : Machine) (rank addr expected tokenVar : Rank)
    (scope : Scope) (ordering : Ordering)
    (hvisible : NotificationVisible m.state rank addr scope) :
    (∃ m', Step m (.wait rank addr expected tokenVar scope ordering) m') ∨
      m.state.signals rank addr < expected := by
  by_cases hready : expected ≤ m.state.signals rank addr
  · left
    exact ⟨{m with
      witnesses := (⟨rank, addr, expected, scope, ordering⟩ :: m.witnesses),
      pending := (⟨tokenVar, rank, addr, expected, scope, ordering⟩ :: m.pending)},
      Step.wait hready hvisible⟩
  · right
    exact Nat.lt_of_not_ge hready

end TritonDistributed
