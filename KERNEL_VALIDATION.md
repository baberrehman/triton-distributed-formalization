# Representative Kernel Validation

## Purpose and scope

This document records an executable source audit against the Triton-distributed
checkout pinned to `1e6d6881cddf645759aa250c94b4157355aa57dc`. The audit is a
three-pattern API and source-order check. It is not a kernel execution test,
compiler validation, source-to-Lean translation, communication simulation, or
hardware-memory-model experiment.

The implementation is [`validation/validate_source_patterns.py`](validation/validate_source_patterns.py).
It uses only Python's standard-library `ast` parser and reads the checkout
without importing its dependencies.

## Evidence selected

1. **Notify/wait tutorial:** `tutorials/01-distributed-notify-wait.py` contains
   `dl.wait`, `dl.consume_token`, `tl.load`, `tl.store`, and `dl.notify` in
   `producer_consumer_kernel`. The validator checks the consumer order
   `wait -> consume_token -> load` and producer order `store -> notify`.
2. **Collective:** `tutorials/02-intra-node-allgather.py` contains the
   `cp_engine_producer_all_gather_full_mesh_pull` host path,
   `nvshmem_device_producer_all_gather_2d_put_block_kernel`, a device
   `putmem_signal_block`, initialization barriers, and a
   `torch.distributed.all_gather_into_tensor` reference.
3. **Compute overlap:** `tutorials/07-overlapping-allgather-gemm.py` contains
   `inter_node_allgather`, `kernel_consumer_gemm_persistent`, a consumer
   `dl.wait`/`dl.consume_token` sequence, and a `torch.matmul` reference. The
   launch path connects communication and the persistent GEMM kernel.

These are representative source patterns, not a claim that the files are
minimal, portable, or the only implementations in the repository.

## Command and expected result

From `/home/baber/baberrehman/docs/triton-distributed`:

```text
python3 validation/validate_source_patterns.py --mutate
```

The command prints the source root and revision, passes for all three positive
patterns, then passes three negative checks by rejecting in-memory mutations:
removing the token consumption, replacing the GEMM operation, and removing the
signal-bearing collective put. The checkout is not modified by the mutations.

## What this establishes

The result establishes that the pinned Python sources contain the documented
names and the selected relative call shapes. It makes the correspondence audit
reproducible and provides regression checks for accidental removal of the
source constructs represented by the Lean core.

## What this does not establish

It does not establish that Python control flow reaches those calls for every
rank or tile, that pointers are symmetric or valid, that signal values are
initialized or safely reused, that collectives participate correctly, that a
token prevents compiler motion, that acquire semantics make data visible, or
that generated code preserves any of these properties. It also does not test
the dirty working-tree changes in the checkout. Those questions require IR and
backend inspection, device tests/litmus tests, and a formal source-to-core or
compiler-refinement theorem.