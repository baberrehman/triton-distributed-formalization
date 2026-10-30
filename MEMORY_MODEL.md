# Hardware and compiler memory-model assumptions

The Lean development has an explicit `NotificationVisible` predicate and an explicit ordering witness. These are semantic inputs to the model. They are not derived from CANN, CUDA, NVSHMEM, ROCSHMEM, MLIR, or Triton code.

## Assumption matrix

| Assumption | Used by | Evidence/status | Needed proof or experiment |
|---|---|---|---|
| `notify(set)` writes the requested signal value | `Step.notifySet` | Source API and operation name; backend behavior not formalized | Inspect lowering and run signal-observation tests. |
| `notify(add)` increments the requested signal | `Step.notifyAdd` | Source API exposes `sig_op="add"`; exact overflow/order behavior is not modeled | Inspect generated IR/backend implementation and test concurrent updates. |
| A successful acquire wait makes producer writes visible | `NotificationVisible`, wait witness | Semantics documentation states acquire ordering; hardware/compiler refinement absent | Prove or cite backend memory-model rule; validate with litmus tests. |
| `consume_token` prevents load motion before wait | `Step.load` witness requirement | Dialect says it builds a data dependency; compiler pass preservation is not proved | Inspect dependency lowering and test optimization configurations. |
| Symmetric pointers identify the intended remote allocation | `Value.pointer`, load/store rules | Documentation states symmetric allocation; allocation agreement is abstract | Add allocation model and cross-rank tests. |
| Signal initialization and reuse are correct | protocol examples | Tutorial resets signals and uses barriers; no invariant currently proves reuse safety | Formalize epochs/queue slots and test repeated reuse. |
| Scope values map to hardware visibility domains | `Scope.gpu`, `Scope.system` | Documentation describes scopes; target-specific semantics vary | Document CANN/NPU mapping and validate each supported backend. |

## Current claim

The currently proved ordering result is conditional:

> If a trace contains a successful wait that records a witness for `(rank, address)`, and a later load is permitted only with that witness, then the core trace excludes a load-before-wait execution for that location.

The present Lean artifact proves the local prerequisites for this statement (`load_requires_ordering_witness`, `load_requires_consume_token`, and `consume_requires_wait_token`), checks an explicit end-to-end `wait -> consume -> load` trace in `end_to_end_wait_consume_load_trace`, and proves the universal trace invariant/decomposition in `trace_preserves_capability_origins` and `load_has_prior_wait_and_consume`. This remains a theorem about the abstract transition model, not about generated machine instructions or a hardware memory consistency model.

The model currently treats signal and data addresses as values in one simplified namespace, does not model a state-changing `store` transition, and does not derive an environment token from `wait`. These are abstraction limits, not claims about the implementation.

## Required publication evidence

A publication claim should include backend-specific citations or formal rules, compiler IR examples before/after relevant optimization passes, litmus tests for acquire/release and signal reuse, and a clear list of trusted components. The Lean model should expose those assumptions as parameters instead of silently treating them as universal facts.
