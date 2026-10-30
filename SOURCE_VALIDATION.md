# Source-to-core validation boundary

## Purpose

This file defines what is validated against Triton-Distributed source and what remains an unproved abstraction boundary. It is deliberately not called a compiler-correctness proof.

## Pinned source

Audited checkout: `../../yuling/Triton-distributed-ascend`

Revision: `1e6d6881cddf645759aa250c94b4157355aa57dc`

Primary evidence:

- `python/triton_dist/language/distributed_ops.py`
- `include/TritonDistributed/Dialect/Distributed/IR/DistributedOps.td`
- `docs/python-api/triton-dist.language.rst`
- `docs/python-api/triton-dist.semantics.rst`
- `docs/getting-started/tutorials/01-distributed-notify-wait.rst`

## Validated correspondence

| Source operation | Core representation | Validation status |
|---|---|---|
| `rank(axis)` | `Expr.rank axis` | Result is modeled as an `i32`; axis remains abstract. |
| `num_ranks(axis)` | `Expr.numRanks axis` | Result is modeled as the world size as an `i32`; axis remains abstract. |
| `symm_at(ptr, rank)` | `Expr.symmAt ptr target` | Scalar pointer type is preserved and target bounds are explicit. |
| `notify(ptr, rank, signal, sig_op, scope)` | `Action.notify rank addr value isAdd scope` | `set` and `add` update signal state in `Step`; pointer lowering and remote-address calculation are abstracted. |
| `wait(ptr, count, scope, semantic, waitValue)` | `Action.wait rank addr expected scope ordering` | Ready/blocked behavior and token metadata are modeled; pointer/count evaluation is abstracted. |
| `consume_token(value, token)` | `Action.consume valueVar tokenVar` | Input type is preserved and the token must be present in the modeled environment and pending capability list; the transition consumes the matching pending capability. Compiler dependency enforcement is an assumption. |
| `tl.load(ptr)` | `Action.load ptrVar` | Load requires an ordering witness in the core trace. |

## Validation theorem boundary

The Lean development proves properties of the core constructors and transitions. It does **not** prove that arbitrary Python/Triton source translates to those constructors, that all compiler passes preserve the witness dependency, or that a backend implements the abstract visibility predicate.

A complete source-to-core theorem would require:

1. An AST/IR representation for the relevant source subset.
2. A translation function from source/MLIR operations to `Expr` and `Action`.
3. A well-formedness theorem for translation.
4. A simulation theorem relating source/IR transitions to `Step` transitions.
5. A backend refinement theorem relating `NotificationVisible` and witness propagation to generated code and the target memory model.

The development includes `end_to_end_wait_consume_load_trace`, a concrete three-step trace from an empty capability state, and the universal core-calculus theorem `load_has_prior_wait_and_consume`. The latter proves that every permitted load after an empty capability state has a matching earlier wait and consume in the abstract action trace. This is still not a source-level provenance result: the explicit source-to-core translation and backend refinement obligations above remain open.

Until those are implemented, the project should use the phrase **source-audited core model**, not **verified Triton-Distributed compiler**.
