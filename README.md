# A Lean Core for Triton-Distributed

This directory contains a Lean 4 formal core modeling a small, explicit subset aligned with Triton-Distributed's documented distributed language operations. It is a reproducible research artifact, not a complete source-faithful compiler verification or a publication-ready claim of novelty.

See [`RESEARCH_PLAN.md`](RESEARCH_PLAN.md) for the source correspondence audit, the current model's known mismatches, and the formal/evaluation work needed before making research claims.

The expanded artifacts are [`SOURCE_VALIDATION.md`](SOURCE_VALIDATION.md), [`MEMORY_MODEL.md`](MEMORY_MODEL.md), and [`RELATED_WORK.md`](RELATED_WORK.md). The Lean transition semantics and checked protocol examples are in `TritonDistributed/Transition.lean` and `TritonDistributed/Examples.lean`.

## Scope

This is a **core-calculus formalization**, not a formalization of all Python/Triton syntax, compiler lowering, NVSHMEM/ROCSHMEM implementations, Ascend CANN primitives, or hardware memory consistency. In particular, actual kernels can use raw pointers, atomics, collectives, inline/external calls, and backend-specific ordering that are outside this model. The results below apply only to the constructors and assumptions encoded in `TritonDistributed/Core.lean`.

The modeled guarantees are:

- **Variable preservation:** a typed environment maps a well-typed variable to a value of its declared type.
- **Rank-query typing:** the modeled `rank` result is an `i32` and `numRanks` returns the world size as an `i32`.
- **Symmetric-address safety:** successful modeled remote addressing preserves the pointer element type and requires the target rank to be in range.
- **Wait/token properties:** a successful wait yields an `i32` token and carries an explicit visible-notification condition; a blocked wait has a signal value below its expected value.
- **Load preservation:** under `StoreWellTyped`, a successful load returns a value of the cell's declared type.
- **Determinism:** the evaluation relation gives at most one result for an expression in a fixed state and environment.
These are conditional safety lemmas over the formal core, including general machine/trace well-typedness preservation and conditional wait progress. The transition model makes `notify` mutate signal state, requires a consumed-token capability before a matching load, and includes mechanized producer/consumer and negative examples. `consumer_consume_then_load_example` uses explicit observed value, scope, ordering, and post-consume machine construction. `end_to_end_wait_consume_load_trace` constructs an actual `wait -> consume -> load` trace from empty capabilities, while `fabricated_environment_token_cannot_authorize_consume` shows that an environment token alone cannot authorize consume when the pending list is empty. The universal theorem `load_has_prior_wait_and_consume` proves the corresponding list decomposition for every permitted load from empty initial pending and consumed capabilities. Deadlock freedom, fairness, collective participation, buffer lifetime, general data-race freedom, hardware memory consistency, and backend/compiler refinement remain unproved.

## Build and verify

Requirements: Lean 4.19.0, as pinned in `lean-toolchain`, with Lake.

From this directory, run:

```sh
lake build
```

`TritonDistributed.lean` imports the core development. The project was checked with `lake build` using Lean 4.19.0. The Lean sources contain no `sorry`, `admit`, or `axiom` declarations. The `NotificationVisible` predicate is an explicit semantic condition in the model, not a proved property of hardware. The current model does not issue an environment token from `wait`; token metadata is supplied by the abstract action/step relation. Signal and data locations share the simplified address namespace, and no state-changing store transition or memory-ordering refinement is modeled.

## Correspondence to the project

The model follows the public primitive descriptions for `rank`, `num_ranks`, `symm_at`, `wait`, and `consume_token` in `docs/python-api/triton-dist.language.rst` and `docs/primitives.md`. The producer/consumer interpretation is motivated by `docs/python-api/triton-dist.semantics.rst` and the AllGather/GEMM tutorials. It is a semantic abstraction chosen for proof tractability, not a claim that every implementation path has these exact operational rules.

## Files

- `TritonDistributed/Core.lean`: types, expressions, runtime state, evaluation relation, and safety lemmas.
- `TritonDistributed/Transition.lean`: state-changing notification/wait/token/load transitions, traces, machine preservation, and conditional progress.
- `TritonDistributed/Examples.lean`: producer/consumer protocol, safe post-wait load, and no-witness counterexample.
- `RESEARCH_PLAN.md`: source audit, candidate research question, required proofs/evaluation, and publication acceptance gates.
- `SOURCE_VALIDATION.md`: source-to-core correspondence and the unproved simulation boundary.
- `MEMORY_MODEL.md`: explicit hardware/compiler assumptions and required backend evidence.
- `RELATED_WORK.md`: initial related-work and novelty analysis.
- `TritonDistributed.lean`: root import.
- `lakefile.lean`: Lake package configuration.
- `lean-toolchain`: compiler version pin.
