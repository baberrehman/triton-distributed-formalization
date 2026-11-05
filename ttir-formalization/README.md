# TTIR and TTAdapter: a scoped Lean formalization

This directory contains a self-contained Lean 4.19.0 development for a rank-one,
static-shaped i32 fragment and its tensor/linalg-style lowering. The main theorem
proves equality of source and target tensor values for every modeled expression
and environment. This is a proof about the encoded abstraction; correspondence
to the C++ compiler is a manual source audit, not a verified extraction.

The compiler spells the stage **`ttadapter`** (rather than `ttadaptor`). It is a
pipeline output containing mixed MLIR operations, not a single dialect. See
[FINDINGS.md](FINDINGS.md) for the source revision and detailed correspondence.

## Contents

| File | Purpose |
| --- | --- |
| `TTIRFormal/Core.lean` | Shape-indexed tensors, source and target expression trees, denotational semantics, signed range bounds |
| `TTIRFormal/Lowering.lean` | Lowering functions and universal preservation proofs |
| `TTIRFormal/Examples.lean` | Ten checked example/counterexample theorems |
| `TTIRFormal/Audit.lean` | Prints trusted axiom dependencies of principal results |
| `FINDINGS.md` | Source correspondence, assumptions, omissions, validation results |

## Semantics

A tensor of length `n` is a function `Fin n → BitVec 32`. Shapes and element
widths are preserved by the types of expressions and `lower`; there is no separate
theorem about arbitrary MLIR type checking. Arithmetic is modulo 2^32, with
`BitVec.ofInt` encoding signed constants and `BitVec.ofNat` encoding loop indices.

Source expressions are inputs, splats, ranges, and pointwise addition. Addition
is an abstract arithmetic composition operation corresponding to signless i32
addition, not a claimed `tt.add` instruction. Target expressions are inputs,
fills, insertion at index zero into an empty tensor, generated indices, and
pointwise addition.

`makeRange n start valid` represents an exclusive end of `start + n`.
`RangeValid` requires `0 < n`, `-2^31 ≤ start`, and `start + n ≤ 2^31 - 1`.
These bounds keep both endpoints representable as signed i32. The mathematical
lane bounds are proved separately; a general theorem converting the modular
lane result back to the mathematical signed integer is not included.

`Environment.empty` supplies arbitrary initial values for empty tensors. This
is a value abstraction of unspecified contents, not a complete poison/undefined
behavior model. The lowering theorem quantifies over every such choice, and
`lowering_ignores_empty` proves independence from that choice.

## Checked results

| Theorem | Statement |
| --- | --- |
| `range_lane_bounds` | Every mathematical lane lies in the half-open range |
| `range_lane_signed_bounds` | Every mathematical lane lies within signed i32 bounds |
| `lower_splat_correct` | Singleton insertion and general fill preserve splat values |
| `lower_range_correct` | Zero-start index generation and nonzero offset addition preserve ranges |
| `lowering_correct` | Every modeled expression preserves its complete tensor value |
| `lowering_lane_correct` | Preservation at each individual lane |
| `source_ignores_empty` | Source results depend only on tensor inputs |
| `lowering_ignores_empty` | Lowered results are independent of initial empty-tensor contents |

The ten examples cover negative starts, last-lane values, zero starts, singleton
splats, arithmetic composition, wrapping addition, two incorrect-lowering
counterexamples, and rejection of empty/overflowing ranges by the model.
The counterexamples are hypothetical mutations, not reported compiler bugs.

## Reproduction

From this directory, run `lake build` to check the library and examples, then
`lake env lean TTIRFormal/Audit.lean` to print theorem assumptions. The project
uses only Lean's bundled `Std`, with no external library dependencies. It does
not change the parent synchronization formalization or require Ascend hardware.

The successful audit reports `propext` and `Quot.sound` for the lowering results;
the arithmetic bound proofs additionally report `Classical.choice`. There are
no custom axioms, `sorry`, `admit`, or native-evaluation proof shortcuts.

This development does not formalize arbitrary ranks, broadcasts, loads/stores,
masks, pointer arithmetic, floating point, SSA/control flow, concurrency,
bufferization, or the complete TTIR-to-TTAdapter pipeline.