"""Capture build output and sampled linker resource use (requires psutil)."""
import argparse
import json
from pathlib import Path
import subprocess
import time

import psutil

parser = argparse.ArgumentParser(__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
start = time.monotonic()
links = {}
with (args.output / "build.log").open("wb") as log:
    child = subprocess.Popen(args.command, stdout=log, stderr=subprocess.STDOUT)
    root = psutil.Process(child.pid)
    next_progress = start + 30
    while child.poll() is None:
        try:
            descendants = root.children(recursive=True)
        except psutil.NoSuchProcess:
            descendants = []
        for process in descendants:
            try:
                if process.name().lower() not in {"lld-link.exe", "link.exe"}:
                    continue
                mem = process.memory_info()
                row = links.setdefault(process.pid, dict(command=process.cmdline(),
                    first_seen_s=time.monotonic() - start, observed_s=0, peak_working_set=0,
                    peak_private_bytes=0))
                row["observed_s"] = time.monotonic() - start - row["first_seen_s"]
                row["peak_working_set"] = max(row["peak_working_set"], mem.peak_wset)
                row["peak_private_bytes"] = max(row["peak_private_bytes"], mem.peak_pagefile)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        if time.monotonic() >= next_progress:
            print(f"Building: {time.monotonic() - start:.0f}s; log: {args.output / 'build.log'}", flush=True)
            next_progress += 30
        time.sleep(0.05)
elapsed = time.monotonic() - start
(args.output / "build-metrics.json").write_text(json.dumps(dict(
    elapsed_s=elapsed, exit_code=child.returncode, sample_period_s=0.05,
    links=list(links.values())), indent=2))
print(f"Build finished: {elapsed:.2f}s exit={child.returncode}", flush=True)
if child.returncode:
    print((args.output / "build.log").read_text(errors="replace")[-8000:])
raise SystemExit(child.returncode)
