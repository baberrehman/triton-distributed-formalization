# Executable Source Validation

`validate_source_patterns.py` is a deliberately small, standard-library-only
validator for three committed examples in the sibling checkout
`../../Triton-distributed-ascend` at revision `1e6d688`. The validator's
`--revision` option prints the pin but does not verify Git history; check out
that revision in the source repository before running the audit:

| Pattern | Source | Checked shape |
| --- | --- | --- |
| Tutorial synchronization | `tutorials/01-distributed-notify-wait.py` | `wait -> consume_token -> load` and producer `store -> notify` |
| Collective | `tutorials/02-intra-node-allgather.py` | all-gather reference, barrier, device signal-put, and host/device paths |
| Compute overlap | `tutorials/07-overlapping-allgather-gemm.py` | communication path, consumer wait/token dependency, and GEMM launch path |

Run from the artifact root (`docs/triton-distributed`):

```text
python3 validation/validate_source_patterns.py --mutate
```

The validator parses source with `ast`, checks names and relative source order,
and applies three in-memory mutations. It does not import Triton, execute
kernels, invoke a compiler, inspect generated MLIR/PTX/Ascend code, exercise a
device, or model communication, scheduling, visibility, memory consistency,
collective correctness, progress, or performance. A passing result therefore
means only that the selected working-tree source contains the API shapes. It is
not source-to-core simulation and is not evidence of compiler or hardware
correctness.