# Image tiling investigation: stopped before measurement

Branch: `astra/image-tiling`. Baseline: `719e02574a8cdcccf47dbd3118290a3e2ebd965e`.
Host: Windows 11, i9-13900K, RTX 3090. Investigation date: 2026-10-04 IST.

The user requested an immediate quota-related stop. No production changes were
made. No configure, compilation, tests, or GPU benchmarks were run. The shared
`C:\astra\kyty-swarm\READY.txt` was absent at the last check, so the required
build-readiness gate had not been satisfied. This report is unverified by execution.

## Findings from source inspection

- `src/graphics/host_gpu/renderer/cache/textureCache.cpp:1995`: the garbage
  collector collects at most 10/20/40 LRU candidates before examining eligibility.
  GPU-owned linear images at normal pressure, and GPU-owned tiled images at any
  pressure, are subsequently skipped. A protected prefix can therefore consume
  the entire candidate budget on every pass and starve reclaimable images later
  in the LRU. This control-flow defect is confirmed by inspection, not by a local
  executable regression.
- [Upstream PR #977](https://github.com/KytyPS5/KytyPS5/pull/977) already proposes
  filtering protected entries before consuming the candidate budget. Its body and
  complete diff were read with `gh pr view` and `gh pr diff`. Do not represent this
  discovery or proposed fix as novel.
- `tests/ShaderRecompilerComputeTests.cpp:8590` onwards covers six depth/stencil
  pairs and expects five pairs to be retired under the ten-entry budget. Preserve
  association entries in the budget and finish LRU traversal before recursive
  deletion. Simply skipping all stencil associations would change this behavior.
- `src/graphics/host_gpu/renderer/cache/textureCache.cpp:1982` overwrites the
  cache-owned byte counter with driver-wide usage. Registration/unregistration
  also increments/decrements that counter. PR #977 treats this as a separate
  accounting fix; it was not implemented here.
- `src/graphics/host_gpu/shaders/gpu_tiler_common.inc:1` uses 8x8 workgroups.
  Sub-dword elements use two atomic operations per element. These are measurement
  candidates only; no throughput defect or faster alternative was established.
- `src/graphics/host_gpu/renderer/image/tiler.cpp:256` records uniform-buffer
  parameter bindings and barriers per operation. Workgroup tuning and parameter
  uploads require before/after measurement; no changes were attempted.

## Measurements

| Workload | Before median | After median | Spread | N |
| --- | --- | --- | --- | --- |
| Protected-prefix eviction | Not measured | Not measured | Not measured | 0 |
| GPU tile/detile | Not measured | Not measured | Not measured | 0 |

There are no raw measurements, measured improvements, or negative experimental
results. No claim about game FPS or emulator throughput is supported.

## Uncommitted continuation files

These draft files remain local and are **not built or verified**:

- `tests/perf/image-tiling/ImageTilingPerf.cpp`: standalone entry point reusing the
  upstream Vulkan harness through an include with its `main` renamed. Implements
  `--gc` and `--observe-gc` with 0/12/64 protected images before 12 reclaimable
  images, covering normal linear and pressured tiled cases. Fixture protection
  uses image ownership state, not GPU writes/readback. This is an explicit limit
  of its coverage.
- `tests/perf/image-tiling/TilerBench.inc`: draft `--tiler` benchmark. Device-local
  buffers, CPU `TileGetBlockOffset`/`TileGetBlockXor` reference, padding comparison,
  round-trip checks, Vulkan timestamps and CPU recording time. Intended cases:
  720p/1080p/4K standard families, narrow elements, compressed-block widths, 3D,
  depth, render targets, PRT and mip tails. Intended statistics: one warmup then
  seven samples of eight tile/detile operations. This method has not been run.
- `bench/image-tiling/RunBench.ps1`: draft runner taking both build mutex slots,
  checking foreground process and NVIDIA utilization, and retaining raw output.
  Its automatic foreground check recognizes streaming applications only. A human
  or resuming agent must also check for games/heavy GPU applications before use.

The temporary root CMake registration was removed during wrap-up. Production and
existing test sources remain unchanged. Draft C++ sources were formatted with the
repository's `src/.clang-format` using installed clang-format 21.1.8; upstream's
pre-commit configuration specifies 22.1.3.

## Resume procedure

1. Read the ownership map, hotpath notes, `READY.txt` and `baseline-tests.txt`.
   Use the current shared build script and build gate; do not assume earlier
   infrastructure commands are final.
2. Review the uncommitted harness for compilation and fixture correctness.
   Re-register `image_tiling_perf` with `add_kyty_full_emulator_test`, add
   `${gpu_test_ms_depth_header}` as a source, and register the `--gc` CTest case in
   one clearly delimited root CMake block after that generated header is defined.
3. Compile the unchanged production baseline and retain its benchmark executable.
   Establish the protected-prefix failure and collect at least five repetitions.
4. Apply the minimal protected-entry filter from PR #977 in the LRU collection
   callback. Preserve the existing depth/stencil budget and post-selection checks.
   Measure with the same executable source and compiler flags; run existing
   `gpu_tiler`, texture-cache selectors, overlap/HTILE and image-page-table tests.
5. Only then investigate GPU changes, requiring byte-identical results and short,
   exclusive GPU runs. Keep cache-accounting changes separate. Do not add lookup
   generation caches without a synthetic benchmark demonstrating their cost.
6. Commit verified improvements with before/after numbers and raw results, then
   push only `astra/image-tiling` to `fork`. No PR was opened in this investigation.

The starvation fix would be general and upstream-worthy, but substantially
overlaps existing PR #977. No optimization is ready to ship from this worktree.
