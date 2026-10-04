# Buffer coherence investigation — interrupted before validation

Date: 2026-10-04, approximately 23:47 IST.
Branch: `astra/buffer-coherence`, based on upstream `719e025`.
The user stopped work because the shared Codex quota was nearly exhausted.

## Findings

- Confirmed by source inspection: `src/graphics/host_gpu/shaders/fault_buffer_process.comp:28` increments the output counter before checking capacity. The 1,024-word output slot has one header and room for 1,023 addresses. The shader also clears the input word before reserving space, dropping the remaining bits when the output fills.
- Confirmed by source inspection: `src/graphics/host_gpu/renderer/cache/faultManager.cpp:135` trusts the shader count and iterates without clamping to the slot capacity. Overflow can therefore cause a CPU out-of-bounds read as well as lost faults.
- `src/graphics/host_gpu/renderer/renderContext.cpp:133` scans all mapped ranges before BDA use. Read upstream PR [562](https://github.com/KytyPS5/KytyPS5/pull/562), including its description of dirty-region hints and lifecycle requirements. Its reported performance numbers were not reproduced and are not results from this investigation.
- `src/graphics/host_gpu/regionManager.h:29` and `src/graphics/host_gpu/pageManager.cpp:60` spin using atomic operations and a compiler fence without a hardware pause instruction. No spin-lock change was made or measured.

Line references above refer to upstream `719e025`; tracked production sources were restored to that baseline at wrap-up.

## Measurements and verification

| Workload | Before | After | Median / spread | N |
|---|---|---|---|---|
| Fault overflow | Source inspection only | Not executed | Unavailable | 0 |
| BDA 0/1/10/100% dirty pages | Not executed | Not executed | Unavailable | 0 |
| Spin contention | Not executed | Not executed | Unavailable | 0 |

No configure, compile, link, test, GPU run, or benchmark was started. The shared `C:\astra\kyty-swarm\READY.txt` was absent at the last readiness check. The subsequent user instruction prohibited further builds, tests, benchmarks, and reviews. There are no measured speedups, test passes, or measured negative performance results to report.

The documentation commit contains no emulator changes. The defect remains unfixed on this branch. No PR was opened.

## Local, uncommitted drafts

These files are deliberately excluded from the documentation commit and push:

- `bench/buffer-coherence/UNVERIFIED.patch`: tracked-source prototype saved before restoring the baseline. It contains a bounded shader reservation with an overflow flag and retained input bits; CPU count clamping and synchronous draining of retained faults; dirty-region candidate hints; buffer registration and mapping publication; selective BDA synchronization; and an isolated CMake test-registration block.
- `tests/perf/buffer-coherence/BufferCoherenceTests.cpp`: draft GPU overflow probe, CPU recovery check, alternating legacy/selective BDA benchmark, buffer readback comparison, and basic growth/remapping checks. It reuses the existing shader-test fixture by including its translation unit with a renamed entry point. This arrangement has not been compiled.
- `tests/perf/buffer-coherence/TrackerBench.cpp`: draft hint lifecycle/concurrency tests, spin contention benchmark, and CPU candidate benchmark. It reuses the existing memory-tracker fixture with a renamed entry point. This arrangement has not been compiled.
- `_build/tools/`: ignored local clang-format 22.1.3 wheel installation matching the repository pre-commit version. Formatting was not run before the stop instruction.

The prototype is incomplete and must not be treated as a validated fix. In particular, alias behavior, delayed GPU writeback with selective BDA synchronization, shader contention cost, callback/scheduler lifetime, and all compiler/linker integration remain unverified. No scratch-reuse or interval-merging change was attempted. Full-slot clearing and per-fault logging remain in the draft.

## Resume

1. Read `C:\astra\kyty-swarm\HOTPATHS.md`, `OWNERSHIP.json`, and the latest `READY.txt` and baseline test results. Stay within this area's ownership boundaries.
2. Inspect the local patch and draft sources. If retaining the prototype, apply `git apply bench/buffer-coherence/UNVERIFIED.patch` from this worktree. The two test sources already exist locally; they are not embedded in the patch and are not present on the pushed branch.
3. Separate the overflow correction from the selective BDA work. Compile and validate overflow first. Exercise more than 1,023 faults, ring reuse, and recovery without a subsequent guest draw. Check scheduler callback behavior and shader/host synchronization before accepting the fix.
4. Use the shared build script and gate specified by READY.txt. Candidate targets registered by the draft are `buffer_coherence_tests` and `buffer_coherence_tracker`. Draft arguments are `--fault-probe`, `--fault-manager`, `--bda`, `--spin`, and `--candidates`; these are untested. `--fault-legacy` is only a bounded observation mode intended for a separately built original shader, not an automatic baseline selector.
5. Run required existing tests: `memory_tracker`, `page_manager`, `stream_buffer_ring`, `buffer_cache_dirty_gc`, and `buffer_cache_ranges`. Complete alias, concurrent publication, registration/growth, unmap/remap, and delayed writeback coverage before shipping BDA changes.
6. Measure both versions on this machine with identical flags and at least five repetitions. Record raw output, medians, spreads, counts, and limitations. Check foreground/GPU activity and hold the build gate for GPU measurements.
7. Format touched C++ with upstream clang-format 22.1.3, commit only completed changes with measured results, and push only `astra/buffer-coherence` to `fork`.

The overflow correction appears general and upstream-worthy if validated. No performance change has yet earned that conclusion.
