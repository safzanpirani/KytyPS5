"""Paired warm-cache component timings. Invoke inside the shared build gate."""
import argparse
import csv
import io
import json
from pathlib import Path
import statistics
import subprocess
import time


CASES = {
    "shader_train": ("shader_recompiler_compute_tests", ["--benchmark-shader-train"]),
    "shader_holdout": ("shader_recompiler_compute_tests", ["--benchmark-shader-holdout"]),
    "shader_cfg": ("shader_cfg_tests", []),
    "memory_clean": ("memory_tracker_tests", ["--benchmark-clean-upload"]),
    "memory_tracker": ("memory_tracker_tests", []),
    "page_manager": ("page_manager_tests", []),
    "archive_file": ("archive_file_tests", []),
    "ngs2_sampler": ("ngs2_sampler_tests", []),
    "resource_tracking": ("resource_tracking_tests", []),
    "gpu_tiler": ("shader_recompiler_compute_tests", ["--gpu-tiler-only"]),
}


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--build", action="append", required=True, help="label=build directory")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES)[:-1])
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("Use at least five repetitions")
    builds = {label: Path(directory).resolve() for label, directory in
              (item.split("=", 1) for item in args.build)}
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    checksums = {}
    for case in args.cases:
        exe, extra = CASES[case]
        for repeat in range(-1, args.runs):
            labels = list(builds)
            if repeat % 2:
                labels.reverse()
            for label in labels:
                cwd = args.output.resolve() / "runtime" / label
                cwd.mkdir(parents=True, exist_ok=True)
                start = time.perf_counter_ns()
                result = subprocess.run([str(builds[label] / (exe + ".exe")), *extra],
                                        cwd=cwd, capture_output=True, timeout=180)
                elapsed_ms = (time.perf_counter_ns() - start) / 1e6
                output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
                (args.output / f"{case}-{label}-{repeat}.log").write_text(output, encoding="utf-8")
                record = dict(case=case, variant=label, repeat=repeat,
                              exit_code=result.returncode, process_ms=elapsed_ms)
                if not result.returncode and case.startswith("shader_") and case != "shader_cfg":
                    rows = list(csv.DictReader(io.StringIO(output[output.index("shader_partition,"):])) )
                    record["ns_per_compile"] = float(rows[0]["ns_per_compile"])
                    record["checksum"] = rows[0]["checksum"]
                    if case in checksums and record["checksum"] != checksums[case]:
                        raise RuntimeError(f"SPIR-V mismatch: {case}/{label}")
                    checksums[case] = record["checksum"]
                if not result.returncode and case == "memory_clean":
                    for row in csv.DictReader(io.StringIO(output[output.index("chunk_bytes,"):])):
                        record["chunk_" + row["chunk_bytes"] + "_ns"] = float(row["ns_per_call"])
                print(f"{case}/{label}/{repeat}: {elapsed_ms:.2f} ms exit={result.returncode}", flush=True)
                if repeat >= 0:
                    records.append(record)
                    (args.output / "raw.json").write_text(json.dumps(records, indent=2))
    summary = []
    for case in args.cases:
        for label in builds:
            rows = [r for r in records if r["case"] == case and r["variant"] == label]
            failures = sum(r["exit_code"] != 0 for r in rows)
            for metric in rows[0]:
                if metric not in {"process_ms", "ns_per_compile"} and not metric.startswith("chunk_"):
                    continue
                values = [r[metric] for r in rows if not r["exit_code"]]
                if values:
                    summary.append(dict(case=case, variant=label, metric=metric, n=len(values),
                                        failures=failures, median=statistics.median(values),
                                        minimum=min(values), maximum=max(values)))
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
