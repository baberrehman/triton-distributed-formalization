# Source-to-core validation boundary

## Purpose

This file defines what is validated against Triton-Distributed source and what remains an unproved abstraction boundary. It is deliberately not called a compiler-correctness proof.

## Pinned source

Audited checkout: `../../yuling/Triton-distributed-ascend`

Revision: `1e6d688`

Primary evidence:

- `python/triton_dist/language/distributed_ops.py`
- `include/TritonDistributed/Dialect/Distributed/IR/DistributedOps.td`
- `docs/python-api/triton-dist.language.rst`
- `docs/python-api/triton-dist.semantics.rst`
- `docs/getting-started/tutorials/01-distributed-notify-wait.rst`

## Validated correspondence

| Source operation | Core representation | Validation status |
|---|---|---|
| `rank(axis)` | `Expr.rank axis` | Result is modeled as an `i32`; evaluation ignores the axis and returns current rank. |
| `num_ranks(axis)` | `Expr.numRanks axis` | Result is modeled as world size as an `i32`; evaluation ignores the axis. |
| `symm_at(ptr, rank)` | `Expr.symmAt ptr target` | Scalar pointer type is preserved and target bounds are explicit. |
| `notify(ptr, rank, signal, sig_op, scope)` | `Action.notify rank addr value isAdd scope` | `set` and `add` update signal state in `Step`; pointer lowering and remote-address calculation are abstracted. |
| `wait(ptr, count, scope, semantic, waitValue)` | `Action.wait rank addr expected tokenVar scope ordering` | Abstract action supplies fields directly. Expression evaluation treats count/expected as variable identifiers and does not evaluate those operands. |
| `consume_token(value, token)` | `Action.consume valueVar tokenVar` | Transition requires environment pointer/token, matching addresses, and pending token/rank/address/scope/ordering; observed and expected values are not compared. Expression consume only looks up operands and returns value. |
| `tl.load(ptr)` | `Action.load ptrVar` | Load requires an ordering witness in the core trace. |

## Validation theorem boundary

The Lean development proves properties of the core constructors and transitions. It does **not** prove that arbitrary Python/Triton source translates to those constructors, that all compiler passes preserve the witness dependency, or that a backend implements the abstract visibility predicate.

A complete source-to-core theorem would require:

1. An AST/IR representation for the relevant source subset.
2. A translation function from source/MLIR operations to `Expr` and `Action`.
3. A well-formedness theorem for translation.
4. A simulation theorem relating source/IR transitions to `Step` transitions.
5. A backend refinement theorem relating `NotificationVisible` and witness propagation to generated code and the target memory model.

The development includes `end_to_end_wait_consume_load_trace`, a three-step consumer trace from empty capability lists but with signal, pointer, and token already initialized, and the universal theorem `load_has_prior_wait_and_consume`. The theorem proves a wait/consume action-list decomposition and a final pointer under the loaded variable; scope/order are not stored in the consumed record or matched by load, and wait expected/token observed values are not equated. This is not source-level provenance: translation and backend refinement remain open.

Until those are implemented, the project should use the phrase **source-audited core model**, not **verified Triton-Distributed compiler**.
