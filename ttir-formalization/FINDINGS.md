# Source audit and formalization findings

## Audited checkout

- Checkout: `/home/baber/baberrehman/Triton-distributed-ascend/3rdparty/triton-ascend`
- Git revision: `fdecef82c42cade68b4039af35a0e06ac8851536`
- Source working tree was clean during initial inspection.
- Paths and line anchors below are relative to that checkout and revision.

## TTAdapter is a pipeline stage

`third_party/ascend/backend/compiler.py:1584` registers the compilation stages;
line 1592 registers `stages["ttadapter"]` using `ttir_to_linalg` with named
operations enabled. `ttir_to_linalg`, beginning at line 324, runs several
transformations before and around the Triton-to-Linalg conversion and returns
the resulting module text. Its temporary/dump artifact is named
`kernel.ttadapter.mlir`. The pure-SIMT route can bypass this stage.

Consequently, correctness of two conversion patterns is not correctness of the
whole stage. Earlier passes can change structure, memory operations, and dialects;
later compilation performs additional transformations. This artifact models
selected tensor computations at the conversion-pattern boundary only.

## Correspondence table

| Source anchor | Observed implementation | Lean abstraction |
| --- | --- | --- |
| `include/triton/Dialect/Triton/IR/TritonOps.td:427` | `tt.splat` preserves element type and returns a tensor | `Source.Expr.splat`, restricted to rank-one i32 |
| `include/triton/Dialect/Triton/IR/TritonOps.td:854` | `tt.make_range` returns a 1D i32 tensor, start inclusive/end exclusive | `Source.Expr.makeRange`; end represented by `start + n` |
| `lib/Dialect/Triton/IR/Ops.cpp:407` | Range verifier checks `start < end`, rank one, length `end-start`, i32 elements | `RangeValid` plus shape/element type indices; no parser or proof of verifier equivalence |
| `third_party/ascend/lib/TritonToLinalg/TritonOpConverter.cpp:1145` | Range conversion generates loop indices, casts to i32, optionally adds filled start | `lowerRange`, `Target.Expr.index`, `fill`, `add` |
| `third_party/ascend/lib/TritonToLinalg/TritonOpConverter.cpp:1205` | Splat conversion inserts at all-zero indices when every dimension is one; otherwise fills | `lowerSplat`; rank-one specialization tests `n = 1` |
| `third_party/ascend/lib/TritonToLinalg/TritonOpConverter.cpp:1350` | Broadcast conversion collapses source shape and invokes linalg.broadcast; can fail matching | Inspected but not formalized |

## Range lowering

The converter creates an empty tensor and a `linalg.generic` with identity
indexing and a parallel loop. Its body uses `linalg.index`, `arith.index_cast`
to i32, and yield. When the signed start is zero it returns that tensor.
Otherwise it fills a second tensor with the signed start constant and adds it
to the index tensor with `arith.addi`.

The operation declaration warns that generated `getStart()`/`getEnd()` accessors
return unsigned values even though the attributes are interpreted as signed i32.
Both the inspected verifier and converter use `getStartAttr().getInt()` where
signedness matters. The Lean model encodes negative starts with `BitVec.ofInt`;
the checked `-2` example exercises that interpretation.

The abstraction treats the cast of a nonnegative loop index as its low 32 bits.
It assumes an index representation capable of expressing the modeled loop
indices and does not verify MLIR data-layout/index-width behavior. Addition is
exact modular i32 addition; it is not unrestricted integer addition. The source
range denotation is defined as the start word plus the lane-index word, while
the target builds the index tensor and optional filled offset separately.
The proof uses zero identity, commutativity, and expression-tree induction.

Range metadata (`tt.from_make_range`, `tt.make_range_offset`, and
`tt.make_range_size`) is omitted. Its effects on subsequent optimizations are
outside the proof. The current range bounds make a nonempty, representable
exclusive end mandatory; this is intentional and excludes an end of +2^31.

## Splat lowering

The C++ optimization is not uniformly a fill: shapes whose dimensions are all
one use `tensor.insert` into `tensor.empty`. For rank one, this is exactly the
test `n = 1`. Every valid index of a singleton tensor is zero, so the insertion
overwrites every lane, independently of initial empty-tensor contents.

For larger tensors the model uses fill. The checked counterexample with length
four and an unwritten lane initially containing 99 shows why inserting only at
zero cannot replace general splat. The denotation also permits zero-length
splats as empty functions; no claim is made that all such shapes are accepted
by upstream TTIR. Rank-zero and multidimensional splats are outside the model.
Transient debug NOP anchors in the converter are not represented.

## Broadcast and other boundaries

`BroadcastConverter` computes broadcast/unbroadcast dimensions, asks for collapse
reassociation indices, and can return `notifyMatchFailure`. It then creates
`tensor.collapse_shape` followed by `linalg.broadcast`. No theorem here covers
these helpers, legal shape conditions, failure behavior, or broadcast values.

The syntax is a typed expression tree with tensor inputs; it is not actual MLIR
SSA. There is no parsing, dominance, block argument, operation registration,
encoding, layout, or dialect legality model. Shape preservation is intrinsic to
the Lean types and does not establish preservation by the real compiler's type
converter. `insertZero` is an internal abstraction, not a full semantics of
`tensor.insert` for invalid/empty destinations.

The proof does not cover pointer/memory lowering, masks, aliasing, synchronization,
floating-point numerical behavior, general control flow, allocations, poison,
bufferization, hardware execution, or compiler termination. It does not extend
the separate synchronization model with claims about TTIR loads.

## Validation and trust boundary

`lake build` successfully checked the library and all ten example theorems under
Lean 4.19.0. `lake env lean TTIRFormal/Audit.lean` successfully audited the main
theorems: lowering results and mutation counterexamples depend on `propext` and
`Quot.sound`; lane-bound proofs additionally depend on `Classical.choice`.
There are no additional axioms or unfinished proofs.

The trusted boundary comprises Lean and its standard foundations, the manually
chosen source and target denotations, and the manual mapping from source code to
those denotations. No compiler execution, generated-MLIR comparison, C++
verification, or hardware experiment was performed for this artifact. The
counterexamples check the model's sensitivity to two plausible incorrect
translations; they do not mutate or test the real compiler.