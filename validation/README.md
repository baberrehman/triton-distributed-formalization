# Executable Source Validation

`validate_source_patterns.py` is a deliberately small, standard-library-only
validator for three committed examples in the pinned checkout
`/home/baber/baberrehman/yuling/Triton-distributed-ascend` at revision
`1e6d6881cddf645759aa250c94b4157355aa57dc`:

| Pattern | Source | Checked shape |
| --- | --- | --- |
| Tutorial synchronization | `tutorials/01-distributed-notify-wait.py` | `wait -> consume_token -> load` and producer `store -> notify` |
| Collective | `tutorials/02-intra-node-allgather.py` | all-gather reference, barrier, device signal-put, and host/device paths |
| Compute overlap | `tutorials/07-overlapping-allgather-gemm.py` | communication path, consumer wait/token dependency, and GEMM launch path |

Run from this directory:

```text
python3 validation/validate_source_patterns.py --mutate
```

The validator parses source with `ast`, checks names and relative source order,
and applies three in-memory mutations. It does not import Triton, execute
kernels, invoke a compiler, inspect generated MLIR/PTX/Ascend code, exercise a
device, or model communication, scheduling, visibility, memory consistency,
collective correctness, progress, or performance. A passing result therefore
means only that the committed source contains the selected API shapes. It is
not source-to-core simulation and is not evidence of compiler or hardware
correctness.