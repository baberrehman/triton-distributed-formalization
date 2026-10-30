#!/usr/bin/env python3
"""Validate representative Triton-distributed source/API patterns.

This is intentionally a source-shape validator.  It parses Python with the
standard-library AST and does not import Triton, compile kernels, launch
devices, or simulate communication or memory ordering.
"""

from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_REVISION = "1e6d6881cddf645759aa250c94b4157355aa57dc"
DEFAULT_SOURCE = Path(__file__).resolve().parents[3] / "yuling" / "Triton-distributed-ascend"


@dataclass(frozen=True)
class Finding:
    name: str
    passed: bool
    detail: str


def call_name(node: ast.Call) -> str:
    parts: list[str] = []
    value: ast.expr = node.func
    if isinstance(value, ast.Subscript):
        value = value.value
    while isinstance(value, ast.Attribute):
        parts.append(value.attr)
        value = value.value
    if isinstance(value, ast.Name):
        parts.append(value.id)
    return ".".join(reversed(parts))


def calls(tree: ast.AST) -> list[tuple[str, int]]:
    return [
        (call_name(node), node.lineno)
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
    ]


def function(tree: ast.AST, name: str) -> ast.AST | None:
    return next(
        (node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name),
        None,
    )


def required_calls(tree: ast.AST, names: Iterable[str], label: str) -> Finding:
    present = {name for name, _ in calls(tree)}
    missing = sorted(set(names) - present)
    return Finding(label, not missing, "all required calls present" if not missing else f"missing {', '.join(missing)}")


def ordered(tree: ast.AST, before: str, after: str, label: str) -> Finding:
    positions = calls(tree)
    left = [line for name, line in positions if name == before]
    right = [line for name, line in positions if name == after]
    passed = bool(left and right and min(left) < max(right))
    detail = f"{before} precedes {after}" if passed else f"no ordered {before} -> {after} sequence"
    return Finding(label, passed, detail)


def parse(source: str, label: str) -> tuple[ast.AST | None, Finding | None]:
    try:
        return ast.parse(source, filename=label), None
    except SyntaxError as exc:
        return None, Finding(label, False, f"syntax error at line {exc.lineno}: {exc.msg}")


def validate_notify_wait(source: str, label: str) -> list[Finding]:
    tree, error = parse(source, label)
    if error:
        return [error]
    kernel = function(tree, "producer_consumer_kernel")
    if kernel is None:
        return [Finding("notify/wait kernel", False, "producer_consumer_kernel not found")]
    findings = [required_calls(kernel, ("dl.wait", "dl.consume_token", "tl.load", "tl.store", "dl.notify"), "notify/wait API")]
    findings += [ordered(kernel, "dl.wait", "dl.consume_token", "wait before token consumption"),
                 ordered(kernel, "dl.consume_token", "tl.load", "token consumption before load"),
                 ordered(kernel, "tl.store", "dl.notify", "producer store before notify")]
    return findings


def validate_collective(source: str, label: str) -> list[Finding]:
    tree, error = parse(source, label)
    if error:
        return [error]
    findings = [required_calls(tree, ("torch.distributed.all_gather_into_tensor", "nvshmem_barrier_all_on_stream", "libshmem_device.putmem_signal_block"), "all-gather API")]
    kernel = function(tree, "nvshmem_device_producer_all_gather_2d_put_block_kernel")
    host = function(tree, "cp_engine_producer_all_gather_full_mesh_pull")
    findings += [Finding("collective kernel", kernel is not None, "producer kernel found" if kernel else "producer kernel not found"),
                 Finding("collective host path", host is not None, "host collective path found" if host else "host collective path not found")]
    return findings


def validate_overlap(source: str, label: str) -> list[Finding]:
    tree, error = parse(source, label)
    if error:
        return [error]
    kernel = function(tree, "kernel_consumer_gemm_persistent")
    launch = function(tree, "ag_gemm_persistent_op")
    findings = [required_calls(tree, ("torch.distributed.all_gather_into_tensor", "torch.matmul", "inter_node_allgather"), "overlap data path"),
                Finding("overlap consumer kernel", kernel is not None, "consumer kernel found" if kernel else "consumer kernel not found"),
                Finding("overlap launch path", launch is not None, "launch path found" if launch else "launch path not found"),
                required_calls(kernel, ("dl.wait", "dl.consume_token"), "consumer wait/token API") if kernel else Finding("consumer wait/token API", False, "consumer kernel unavailable")]
    if launch:
        findings += [required_calls(launch, ("inter_node_allgather", "kernel_consumer_gemm_persistent"), "communication/compute launch")]
    return findings


def validate_file(path: Path, source: str) -> list[Finding]:
    label = str(path)
    if path.name == "01-distributed-notify-wait.py":
        return validate_notify_wait(source, label)
    if path.name == "02-intra-node-allgather.py":
        return validate_collective(source, label)
    if path.name == "07-overlapping-allgather-gemm.py":
        return validate_overlap(source, label)
    return [Finding(label, False, "no validator registered")]


def run_mutations(paths: dict[str, Path]) -> list[Finding]:
    results: list[Finding] = []
    notify = paths["notify"].read_text()
    mutated = notify.replace("dl.consume_token(", "dl.removed_consume_token(")
    findings = validate_notify_wait(mutated, "mutation: remove consume_token")
    results.append(Finding("mutation removes consume_token", not all(item.passed for item in findings), "rejected" if not all(item.passed for item in findings) else "unexpectedly accepted"))

    overlap = paths["overlap"].read_text()
    mutated = overlap.replace("torch.matmul(ag_out, local_weight)", "torch.add(ag_out, local_weight)", 1)
    findings = validate_overlap(mutated, "mutation: remove matmul")
    results.append(Finding("mutation removes compute", not all(item.passed for item in findings), "rejected" if not all(item.passed for item in findings) else "unexpectedly accepted"))

    collective = paths["collective"].read_text()
    mutated = collective.replace("libshmem_device.putmem_signal_block", "libshmem_device.putmem_block", 1)
    findings = validate_collective(mutated, "mutation: remove signal put")
    results.append(Finding("mutation removes collective signal", not all(item.passed for item in findings), "rejected" if not all(item.passed for item in findings) else "unexpectedly accepted"))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--revision", default=DEFAULT_REVISION, help="reported source pin; this script does not run git")
    parser.add_argument("--mutate", action="store_true", help="also run in-memory negative mutations")
    args = parser.parse_args()
    paths = {
        "notify": args.source_root / "tutorials/01-distributed-notify-wait.py",
        "collective": args.source_root / "tutorials/02-intra-node-allgather.py",
        "overlap": args.source_root / "tutorials/07-overlapping-allgather-gemm.py",
    }
    print(f"source_root={args.source_root}")
    print(f"revision={args.revision}")
    findings = [item for path in paths.values() for item in validate_file(path, path.read_text())]
    if args.mutate:
        findings.extend(run_mutations(paths))
    failed = False
    for item in findings:
        status = "PASS" if item.passed else "FAIL"
        print(f"{status} {item.name}: {item.detail}")
        failed |= not item.passed
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())