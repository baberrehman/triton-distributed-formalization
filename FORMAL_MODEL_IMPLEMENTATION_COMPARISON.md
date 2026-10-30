# Formal Model versus `Triton-distributed-ascend`

## Executive summary

This report compares the Lean core calculus in this directory with the implementation in:

- `/home/baber/baberrehman/Triton-distributed-ascend`
- audited source revision: `1e6d6881cddf645759aa250c94b4157355aa57dc`

The Lean model is **stricter than the implementation interface** for the specific capability discipline it formalizes. A permitted `Action.load` must be preceded, in the modeled machine state, by a matching consumed capability. A consumed capability must have matching pointer, token, rank, address, scope, and ordering metadata, and must originate from a pending capability created by a successful `wait`. Consequently, `load_has_prior_wait_and_consume` proves that every permitted load from empty initial capability lists has an earlier matching `wait` and `consume` in the abstract trace.

The implementation does not provide the same end-to-end static or dynamic guarantee. Its Python API accepts a token and a value at `consume_token`; the compiler/IR is responsible for preserving the dependency and the backend is responsible for giving it the intended ordering semantics. The implementation therefore can accept programs that are rejected by the Lean transition relation, and incorrect behavior can arise if the source program, compiler transformation, pointer/signal pairing, signal epoch, or backend memory ordering violates the intended protocol.

This is a **model-to-implementation gap report**, not a claim that a particular upstream kernel has been observed to fail. The findings identify behaviors that the implementation API and documented abstraction do not rule out, whereas the corresponding Lean transitions are unrepresentable or unprovable.

## What the formal model enforces

The relevant definitions are in `TritonDistributed/Transition.lean`:

1. `Step.wait` creates a `PendingToken` containing the signal rank, signal address, expected value, token variable, scope, and ordering.
2. `Step.consume` requires:
   - the value variable to be a valid symmetric pointer;
   - the token variable to be an environment token;
   - token address to equal pointer address;
   - a pending token with matching token variable, rank, address, scope, and ordering.
3. `Step.consume` removes the pending capability and creates a `ConsumedOrdering` capability.
4. `Step.load` requires a valid pointer and a consumed capability matching the pointer variable, rank, and signal address.
5. `trace_preserves_capability_origins` preserves historical provenance through arbitrary traces.
6. `load_has_prior_wait_and_consume` derives the universal action-list decomposition from empty `pending` and `consumed` lists.

Thus, within the model, the following bad shapes are not valid completed traces:

- `load` with no prior `consume`;
- `consume` with no matching prior `wait`;
- consuming an environment token whose metadata does not match the waited signal;
- consuming a token for one pointer and loading an unrelated pointer/rank/address;
- loading a pointer that is not represented by the required typed environment value.

The guarantee is conditional on the model's premises, especially `NotificationVisible`, typed environments, and the abstract pointer/capability state.

## What the implementation exposes

The implementation API is defined in `python/triton_dist/language/distributed_ops.py`:

- `wait(barrierPtrs, numBarriers, scope, semantic, waitValue=1)` checks that `barrierPtrs` is a scalar pointer and emits an IR wait returning an `int32` token.
- `consume_token(value, token)` checks only `token.type.scalar.is_int()`, emits `create_distributed_consume_token(value.handle, token.handle)`, and returns the value with its original type.
- `symm_at(ptr, rank)` checks that `ptr` is a scalar pointer and returns the same pointer type.
- `notify(ptr, rank, signal, sig_op, comm_scope)` checks pointer shape and selected signal dtypes, then emits the notify operation.

The implementation's documented contract says that the token should come from `wait` and that `consume_token` creates the dependency needed by a later load. However, the Python API does not itself establish token provenance, pointer/signal matching, signal epoch matching, or a proof that compiler transformations preserve the dependency. Those obligations are delegated to IR construction, compiler passes, generated code, and backend behavior.

## Findings

### Finding 1: Fabricated or unrelated integer tokens are rejected by the model but accepted by the API

**Formal behavior.** `Step.consume` requires an environment value of token type and a matching `PendingToken` created by `Step.wait`. A token-shaped value without a matching pending capability cannot authorize consume. This is demonstrated by `fabricated_environment_token_cannot_authorize_consume` in `TritonDistributed/Examples.lean`.

**Implementation behavior.** `consume_token` checks only that `token.type.scalar.is_int()` before calling `create_distributed_consume_token`. It does not check that the integer is the result of `wait`, or that it refers to the same signal, expected value, scope, or ordering as the value being consumed.

**Potential failure.** A source program can pass an unrelated integer tensor or token-like SSA value. The call may compile and produce an ordering dependency that is not justified by a successful wait on the relevant signal. Whether this becomes an observable stale or premature load depends on lowering and backend behavior, but the API does not rule it out.

**Evidence:** `python/triton_dist/language/distributed_ops.py`, `consume_token`; `python/triton_dist/test/ascend/api/test_wait_notify.py` demonstrates the intended wait-to-consume pattern but is not a negative provenance test.

### Finding 2: The model rejects pointer/signal mismatches that the implementation does not establish

**Formal behavior.** A consumed capability records `valueVar`, `tokenVar`, `signalAddr`, and `rank`. `Step.load` requires the consumed capability's value variable, rank, and signal address to match the loaded pointer. The universal theorem therefore returns a wait and consume matching the final load's pointer metadata.

**Implementation behavior.** `consume_token(value, token)` preserves the value's type but does not inspect its relationship to the signal pointer passed to `wait`. `wait` accepts a barrier pointer and count; `consume_token` receives only `value` and `token`, not the barrier pointer, rank, or signal address. `symm_at` also preserves pointer type but does not prove allocation agreement or correspondence between a remote data pointer and the signal pointer.

**Potential failure.** A consumer can wait on signal A, consume token A, and then consume/load data pointer B. The API shape permits this because the token and value are independent operands. The intended protocol may still be correct if the programmer maintains the association, but the implementation has no general check equivalent to the formal matching-capability premise.

**Evidence:** `python/triton_dist/language/distributed_ops.py`, `wait`, `consume_token`, and `symm_at`; `docs/python-api/triton-dist.language.rst` describes the token as an ordering token but does not specify a statically checked pointer/signal association.

### Finding 3: Missing `consume_token` is rejected by the model but is not rejected at ordinary `tl.load` API level

**Formal behavior.** `Step.load` has an explicit consumed-capability premise. A trace ending in a permitted load from empty capabilities must contain a prior matching wait and consume by `load_has_prior_wait_and_consume`.

**Implementation behavior.** Ordinary Triton `tl.load` remains an ordinary load. The intended ordering discipline is expressed by placing `consume_token` before the load; the tutorial explicitly comments that it is used “to make sure that the `wait` is needed.” There is no source-level rule in the Python API shown here that rejects `tl.load` when no `consume_token` dependency reaches it.

**Potential failure.** Removing or bypassing `consume_token` can leave a kernel that still parses and compiles but no longer carries the intended wait-to-load dependency. The implementation's own source-validation tests treat removal of `consume_token` as a mutation to reject at the validation-script level, not as a proof that the compiler or runtime rejects all such kernels.

**Evidence:** `docs/getting-started/tutorials/01-distributed-notify-wait.rst`; `python/triton_dist/language/distributed_ops.py`; `TritonDistributed/Transition.lean`, `Step.load`.

### Finding 4: Signal reuse and epoch discipline are programmer obligations in the implementation, not enforced by the API

**Formal behavior.** A `PendingToken` records an expected signal value, and the provenance theorem matches the consumed ordering to the wait action. The model can represent a protocol in which different signal values distinguish epochs; a load cannot be justified merely by an unrelated capability in the abstract state.

**Implementation behavior.** `wait` accepts an arbitrary `waitValue`, while `notify` accepts arbitrary `set` or `add` values. The API does not maintain a signal epoch invariant, prevent signal reuse, or prove that a reused signal value belongs to the current buffer slot. The tutorials themselves use explicit queue/repetition arithmetic such as `queue_repeat * 2`, and other documentation describes cycling signal values.

**Potential failure.** Reusing a signal or choosing an incorrect `waitValue` can allow a consumer to observe an old signal value and read a buffer slot before the current producer has completed, or can cause a deadlock by waiting for a value that will never be produced. The formal core requires a successful modeled wait and preserves its metadata, but it does not prove that a real backend signal has the intended epoch semantics.

**Evidence:** `docs/getting-started/tutorials/01-distributed-notify-wait.rst`; `docs/layers/nvidia/ep_ll_a2a_layer.rst`; `python/triton_dist/language/distributed_ops.py`.

### Finding 5: Rank bounds and symmetric allocation are formal premises, not implementation-wide guarantees

**Formal behavior.** Notification steps require `rank < m.state.world`; pointer typing and the core's symmetric-address rules require valid target-rank conditions. The model treats these as transition premises.

**Implementation behavior.** `notify` converts `rank` to an IR value and emits the operation; `symm_at` converts `rank` and emits the operation. The Python wrappers do not establish a general runtime proof that the rank is in range, that all ranks agree on symmetric allocation, or that a signal and data pointer refer to corresponding remote objects.

**Potential failure.** An out-of-range or otherwise invalid rank, mismatched symmetric allocation, or incorrectly computed peer pointer can produce backend errors, invalid remote accesses, hangs, or data corruption. The implementation may rely on NVSHMEM/CANN runtime checks or undefined behavior; the wrapper itself does not provide the formal model's proof obligation.

**Evidence:** `python/triton_dist/language/distributed_ops.py`, `symm_at` and `notify`; `docs/python-api/triton-dist.language.rst`; `SOURCE_VALIDATION.md` in this project.

### Finding 6: Memory visibility and compiler dependency preservation remain trusted implementation assumptions

**Formal behavior.** A successful `Step.wait` requires `NotificationVisible`, and `Step.load` requires a consumed ordering capability. These premises make visibility and dependency explicit in the transition relation.

**Implementation behavior.** `wait` passes `scope` and `semantic` into IR, and `consume_token` emits an IR operation. The implementation does not prove that the selected backend's acquire/release semantics make producer writes visible to the consumer, nor that every optimization preserves the dependency through to the generated load. The documentation for inter-node paths delegates memory-barrier behavior to NVSHMEM.

**Potential failure.** A wrong scope/semantic choice, unsupported backend combination, compiler motion, or backend lowering defect can yield a load that is ordered in the source intent but not in the generated execution. This is not a failure of the Lean theorem: it is outside its source-to-core and backend-refinement boundary.

**Evidence:** `python/triton_dist/language/distributed_ops.py`; `docs/python-api/triton-dist.semantics.rst`; `docs/getting-started/tutorials/03-inter-node-allgather.rst`; `MEMORY_MODEL.md` in this project.

## Important qualification

The Lean model does **not** prove that every program accepted by the implementation is wrong, nor does it model all valid implementation programs. It proves safety properties for a deliberately small abstract language. The correct comparison is:

> Every execution admitted by the Lean transition relation satisfies the modeled capability/provenance rules; the implementation interface and current validation suite do not establish those rules for all source programs or all compiler/backend executions.

The implementation's documented examples are intended to follow the correct protocol and may work correctly. The findings above identify missing enforcement and conditional failure modes, not experimentally confirmed bugs in every example.

## Recommended next steps

1. Add a typed source/IR representation in Lean for `wait` results and `consume_token` dataflow.
2. Define a translation from the Python/MLIR operations to `Action` and prove a simulation theorem.
3. Add negative compiler tests for fabricated tokens, token/value mismatch, missing consume dependencies, wrong signal epochs, and invalid ranks.
4. Inspect generated IR and backend code for representative Ascend and NVSHMEM paths.
5. Add signal-reuse litmus tests and multi-rank tests that distinguish stale-signal acceptance from current-epoch readiness.
6. Treat `NotificationVisible`, symmetric allocation agreement, and compiler dependency preservation as explicit refinement obligations rather than informal assumptions.
