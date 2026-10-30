import TritonDistributed.Transition

namespace TritonDistributed

inductive ProtocolStatus where
  | safe
  | blocked
  | invalid
  deriving DecidableEq, Repr

def initialState : State :=
  { world := 2
    currentRank := 0
    memory := fun _ _ => none
    cellType := fun _ _ => none
    signals := fun _ _ => 0
    signalOwner := fun _ _ => 0 }

def producerState : State :=
  { initialState with
    memory := fun rank addr =>
      if rank = 1 ∧ addr = 7 then some (.i32 42) else none
    cellType := fun rank addr =>
      if rank = 1 ∧ addr = 7 then some ⟨.i32, 1⟩ else none
    signalOwner := fun rank _ => rank }

def producerMachine : Machine :=
  { state := { producerState with signals := fun rank addr =>
      if rank = 1 ∧ addr = 7 then 1 else 0 }
    env := fun id =>
      if id = 0 then some (.pointer ⟨.i64, 1⟩ 1 7 true)
      else if id = 1 then some (.pointer ⟨.i32, 1⟩ 1 7 true)
      else if id = 2 then some (.token 7 1 .system .acquire)
      else none
    witnesses := [],
    pending := [],
    consumed := [] }

def consumerMachine : Machine :=
  { state := producerMachine.state
    env := producerMachine.env
    witnesses := [{ signalRank := 1, signalAddr := 7, expected := 1,
                    scope := .system, ordering := .acquire }]
    pending := []
    consumed := [] }

def waitedConsumerMachine : Machine :=
  { state := consumerMachine.state
    env := consumerMachine.env
    witnesses := consumerMachine.witnesses
    pending := [{ tokenVar := 2, signalRank := 1, signalAddr := 7, expected := 1,
                  scope := .system, ordering := .acquire }]
    consumed := consumerMachine.consumed }

def emptyConsumerMachine : Machine :=
  { producerMachine with
    witnesses := [], pending := [], consumed := [] }

theorem producer_notify_set_example :
    ∃ m', Step producerMachine (.notify 1 7 1 false .system) m' ∧
      m'.state.signals 1 7 = 1 := by
  let m' := {producerMachine with state :=
    {producerMachine.state with signals := fun rank addr =>
      if rank = 1 ∧ addr = 7 then 1 else producerMachine.state.signals rank addr}}
  exact ⟨m', Step.notifySet (by decide), by simp [m']⟩

theorem consumer_consume_then_load_example :
    ∃ m₁ m₂,
      Step waitedConsumerMachine (.consume 1 2) m₁ ∧
      Step m₁ (.load 1) m₂ := by
  let hptr : waitedConsumerMachine.env 1 = some (.pointer ⟨.i32, 1⟩ 1 7 true) := by
    simp [waitedConsumerMachine, consumerMachine, producerMachine]
  let m₁ : Machine := {waitedConsumerMachine with
      pending := waitedConsumerMachine.pending.filter (fun p => p.tokenVar ≠ 2),
      consumed := [{ valueVar := 1, tokenVar := 2, signalAddr := 7, rank := 1 }]}
  refine ⟨m₁, m₁, ?_, ?_⟩
  · apply Step.consume (m := waitedConsumerMachine) (valueVar := 1) (tokenVar := 2)
      (ty := ⟨.i32, 1⟩) (rank := 1) (addr := 7) (tokenAddr := 7)
      (observed := 1) (scope := .system) (ordering := .acquire) hptr
    · simp [waitedConsumerMachine, consumerMachine, producerMachine]
    · rfl
    · have hp : ∃ p : PendingToken, p ∈ waitedConsumerMachine.pending ∧
          p.tokenVar = 2 ∧ p.signalRank = 1 ∧ p.signalAddr = 7 ∧
          p.scope = .system ∧ p.ordering = .acquire := by
        let p : PendingToken :=
          { tokenVar := 2, signalRank := 1, signalAddr := 7,
            expected := 1, scope := .system, ordering := .acquire }
        refine ⟨p, ?_⟩
        simp [p, waitedConsumerMachine, consumerMachine]
      exact hp
  · simpa [m₁] using (Step.load (m := m₁) (ptrVar := 1) (ty := ⟨.i32, 1⟩)
      (rank := 1) (addr := 7) hptr (by
      exact ⟨{ valueVar := 1, tokenVar := 2, signalAddr := 7, rank := 1 },
        List.mem_cons_self, rfl, rfl, rfl⟩))

  theorem end_to_end_wait_consume_load_trace :
      ∃ m₁ m₂ m₃,
        Step emptyConsumerMachine
          (.wait 1 7 1 2 .system .acquire) m₁ ∧
        Step m₁ (.consume 1 2) m₂ ∧
        Step m₂ (.load 1) m₃ ∧
        Trace emptyConsumerMachine
          ([.wait 1 7 1 2 .system .acquire, .consume 1 2, .load 1]) m₃ := by
    have hvisible : NotificationVisible emptyConsumerMachine.state 1 7 .system := by
      simp [NotificationVisible, emptyConsumerMachine, producerMachine, producerState,
        initialState]
    have hwait : Step emptyConsumerMachine
        (.wait 1 7 1 2 .system .acquire) waitedConsumerMachine := by
      simpa [waitedConsumerMachine, consumerMachine, emptyConsumerMachine,
        producerMachine] using
        (Step.wait (m := emptyConsumerMachine) (rank := 1) (addr := 7)
          (expected := 1) (tokenVar := 2) (scope := .system) (ordering := .acquire)
          (by simp [emptyConsumerMachine, producerMachine]) hvisible)
    have hconsume : Step waitedConsumerMachine (.consume 1 2) (by
        exact {waitedConsumerMachine with
          pending := waitedConsumerMachine.pending.filter (fun p => p.tokenVar ≠ 2),
          consumed := [{ valueVar := 1, tokenVar := 2, signalAddr := 7, rank := 1 }]}) := by
      apply Step.consume (m := waitedConsumerMachine) (valueVar := 1) (tokenVar := 2)
        (ty := ⟨.i32, 1⟩) (rank := 1) (addr := 7) (tokenAddr := 7)
        (observed := 1) (scope := .system) (ordering := .acquire)
      · simp [waitedConsumerMachine, consumerMachine, producerMachine]
      · simp [waitedConsumerMachine, consumerMachine, producerMachine]
      · rfl
      · exact ⟨_, List.mem_cons_self, rfl, rfl, rfl, rfl, rfl⟩
    let m₂ : Machine := {waitedConsumerMachine with
      pending := waitedConsumerMachine.pending.filter (fun p => p.tokenVar ≠ 2),
      consumed := [{ valueVar := 1, tokenVar := 2, signalAddr := 7, rank := 1 }]}
    have hconsume' : Step waitedConsumerMachine (.consume 1 2) m₂ := by
      simpa [m₂] using hconsume
    have hload : Step m₂ (.load 1) m₂ := by
      apply Step.load (m := m₂) (ptrVar := 1) (ty := ⟨.i32, 1⟩) (rank := 1) (addr := 7)
      · simp [m₂, waitedConsumerMachine, consumerMachine, producerMachine]
      · exact ⟨_, List.mem_cons_self, rfl, rfl, rfl⟩
    refine ⟨waitedConsumerMachine, m₂, m₂, hwait, hconsume', hload, ?_⟩
    exact Trace.cons hwait (Trace.cons hconsume' (Trace.cons hload (Trace.nil m₂)))

theorem fabricated_environment_token_cannot_authorize_consume :
    ¬ ∃ m', Step emptyConsumerMachine (.consume 1 2) m' := by
  intro h
  obtain ⟨m', hstep⟩ := h
  obtain ⟨p, hp, _⟩ := consume_requires_wait_token emptyConsumerMachine m' 1 2 hstep
  simp [emptyConsumerMachine] at hp

theorem load_without_consume_is_not_derivable :
    ¬ ∃ m', Step consumerMachine (.load 1) m' := by
  intro h
  obtain ⟨m', hstep⟩ := h
  obtain ⟨c, hc, hvar⟩ := load_requires_consume_token consumerMachine m' 1 hstep
  simpa [consumerMachine, producerMachine] using hc

theorem load_without_wait_is_not_derivable :
    ¬ ∃ m', Step producerMachine (.load 1) m' := by
  intro h
  obtain ⟨m', hstep⟩ := h
  have hload := load_requires_ordering_witness producerMachine m' 1 hstep
  rcases hload with ⟨ty, rank, addr, hptr, c, hc, hvar, hrank, haddr⟩
  simp [producerMachine] at hc

def classifyConsumer (m : Machine) : ProtocolStatus :=
  if h : ∃ w ∈ m.witnesses, w.signalRank = 1 ∧ w.signalAddr = 7 then
    .safe
  else if m.state.signals 1 7 = 0 then
    .blocked
  else
    .invalid

theorem consumer_classification_safe :
    classifyConsumer consumerMachine = .safe := by
  simp [classifyConsumer, consumerMachine]

theorem consumer_classification_initially_blocked :
    classifyConsumer {producerMachine with state := initialState, witnesses := []} = .blocked := by
  simp [classifyConsumer, producerMachine, initialState]

end TritonDistributed
