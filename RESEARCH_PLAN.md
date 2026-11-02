# Research plan: formalizing Triton-Distributed synchronization

## Status

This is a research plan and prototype description, **not a publication-ready paper**. The Lean development currently proves lemmas about a deliberately small, idealized calculus. It does not yet establish a soundness theorem for Triton-Distributed programs or compiler output.

## Candidate research question

Can a mechanized operational model of Triton-Distributed's signal-based synchronization establish when a consumer's memory access is ordered after its corresponding producer notification, and can the model expose unsafe producer-consumer schedules in representative kernels?

This question is only a candidate contribution. Novelty must be established by reviewing prior work on distributed GPU programming, memory models, compiler verification, and mechanized concurrency proofs. The repository's own semantics documentation cites TileLink (MLSys 2025) and Triton-distributed (2025); this development must identify its distinction from those works and any existing formal models before claiming novelty.

## Source-grounded primitive contract (audited)

The current source/API describes:

- `rank(axis=-1)` and `num_ranks(axis=-1)` as `int32` results, with `axis` an operand.
- `symm_at(ptr, rank)` as accepting a scalar pointer and an `int32` rank, returning the same pointer type.
- `notify(ptr, rank, signal, sig_op, comm_scope)` as an effectful update to a remote signal.
- `wait(barrierPtrs, numBarriers, scope, semantic, waitValue)` as waiting on signal storage and returning an integer token. The expected-value type is tied to the signal pointee type; memory scope and semantics matter.
- `consume_token(value, token)` as returning the input's type while introducing a dependency. Ordinary `tl.load` follows this dependency in the documented producer-consumer pattern.

Evidence is in `../../yuling/Triton-distributed-ascend/python/triton_dist/language/distributed_ops.py`, `../../yuling/Triton-distributed-ascend/include/TritonDistributed/Dialect/Distributed/IR/DistributedOps.td`, and that repository's API/semantics documentation and notify-wait tutorial. These files should be pinned to a commit in any submission.

Revision audited during this session: `1e6d688`. Re-audit the API and semantics if the source revision changes.

## Current abstraction boundary

`TritonDistributed/Core.lean` and `TritonDistributed/Transition.lean` are still not a full semantics of that API:

1. `rank(axis)` and `numRanks(axis)` retain an axis argument, but evaluation ignores it; rank returns the state's current rank.
2. Wait expression evaluation uses variable identifiers as count and expected operands without looking up their values. The abstract transition action directly supplies rank, address, expected value, and token variable.
3. The transition layer models `consume_token` over environment variables and creates an explicit capability, but does not yet represent arbitrary SSA values or token dataflow.
4. `.load` is an ordinary load whose transition requires the consumed capability. Upstream uses `consume_token` followed by ordinary `tl.load`; the source-to-core simulation is still pending.
5. Signal readiness and memory ordering remain simplified: notification state is explicit, while scope, acquire/release, compiler reordering, and hardware visibility are represented by assumptions and witnesses.
6. `wait_progress` is conditional progress for the modeled transition, not a liveness theorem for kernels.

Therefore the current theorems must be described as results about the prototype calculus only.

## Implemented formal development

The current artifact includes explicit state transitions for notification set/add, wait, consume, and load; general well-typedness preservation over steps and traces; conditional wait progress; an explicit consume-token capability required by load; and mechanized safe/unsafe producer-consumer examples. The checked examples include `consumer_consume_then_load_example`, `end_to_end_wait_consume_load_trace` from empty capabilities, and `fabricated_environment_token_cannot_authorize_consume` from an empty pending list.

## Remaining formal development

A publication-grade formalization should, at minimum:

1. Define a typed core with explicit local and symmetric pointers, typed signal cells, rank/axis queries, `notify`, `wait`, `consume_token`, ordinary loads/stores, and the API's scope/semantic parameters.
2. Give small-step or trace semantics that distinguish blocked execution from completed execution and represent notification and memory-ordering effects.
3. State assumptions explicitly: valid ranks, symmetric allocation agreement, signal initialization, signal reuse discipline, supported scopes, and the hardware/compiler guarantees relied upon.
4. Prove a general preservation theorem and a progress theorem with precise preconditions. For concurrency, prove an ordering/safety result connecting producer writes, notification, successful wait, token consumption, and consumer reads.
5. Define a source-to-core translation and prove at least a simulation or establish a transparent validation boundary. Without this, claims apply only to the core calculus.
6. Add mechanized examples and counterexamples, including the queue/reuse pattern from the notify-wait tutorial and a deliberately incorrect variant.
7. Audit trusted assumptions and ensure no theorem depends on `sorry`, hidden axioms, or unreviewed external assumptions.

The trace theorem `load_has_prior_wait_and_consume` assumes empty initial pending and consumed lists and a permitted final load. It gives `prefix ++ [wait] ++ middle ++ [consume] ++ suffix` plus a final symmetric pointer at the loaded variable/rank/address. The consumed record stores value variable, token variable, signal address, and rank; scope/order are recovered from the wait, and wait expected/token observed values are not equated. The middle contains only supported actions (notify, wait, consume, load), not arbitrary computation. This is a calculus result, not source-to-core or backend refinement.

## Required evaluation and paper work

- Pin the exact upstream commit and provide scripts to reproduce Lean builds and example checks.
- Validate the abstraction against representative kernels and, where feasible, compiler IR/lowering and hardware behavior. Report mismatches and limitations rather than treating tests as proofs.
- Compare the model and theorem statements against related formal work; do not claim novelty until this review is complete.
- Write a paper with a precise contribution statement, formal definitions, proof sketches, implementation/evaluation methodology, limitations, and artifact instructions.
- Obtain independent review and select a venue whose scope fits the contribution.

## Acceptance gates before calling this publishable

- API correspondence reviewed against pinned source and IR definitions.
- Main theorem is general (not a collection of constructor-specific facts) and kernel-relevant.
- Memory-ordering assumptions are explicit and justified by implementation documentation or evidence.
- Translation/validation boundary is documented and tested.
- Related-work and novelty assessment is complete.
- Reproducible artifact builds from a clean environment.

Passing `lake build` alone satisfies only the artifact-compilation gate; it is not evidence of soundness with respect to the implementation, practical impact, or novelty.
