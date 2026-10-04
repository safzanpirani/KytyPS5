# Pipeline-bindings handoff results

Branch: `astra/pipeline-bindings`, based on upstream `719e02574a8cdcccf47dbd3118290a3e2ebd965e`.
Work stopped at the user's quota wrap-up request on 2026-10-04, approximately 23:46 IST.

## Outcome and verification

Implemented a self-contained shader-statistics fix and a CPU regression/benchmark harness. **Unverified:** no configure, build, test, benchmark, or GPU run was performed. `READY.txt` was absent at the last readiness check. No before/after performance numbers exist. The user explicitly requested stopping without further tests and allowed clearly marked unverified commits.

`git diff --check` passed before wrap-up. Changed production lines and the new C++ sources were formatted with clang-format 21.1.8 using `src/.clang-format`. This is formatting evidence, not compilation or behavioral verification.

| Experiment | Before | After | Median/spread/N |
| --- | --- | --- | --- |
| Statistics insertion, 1k/10k permutations | Not run | Not run | Unavailable |
| Permutation lookup, 1/8/64/512 variants | Not run | Not run | Unavailable |
| Stable/changing descriptor preparation, 1/8/32 resources | Not run | Not run | Unavailable |

## Confirmed findings

Line numbers below refer to upstream `719e025`.

- `src/graphics/host_gpu/renderer/pipeline/pipelineCache.cpp:373`: every new compiled permutation scans all source entries to recount shader totals. With one source per insertion, cumulative recount work is O(N squared). It then calls `std::printf`, bypassing Silent logging. The fix increments a per-stage counter after successful insertion and uses LOGF at most once per second. Silent mode does not query the clock.
- `src/graphics/host_gpu/renderer/pipeline/pipelineCache.cpp:306`: a source hit materializes resources and linearly searches permutations. Matching includes both full resource specialization and `PushData::StartFor` placement. Materialization cannot simply be skipped because guest descriptors and specialization memory can change independently of shader source.
- `src/graphics/host_gpu/renderer/pipeline/descriptors.cpp:772`: preparation resolves images and samplers every call. `FindBuffers` (808), `RebindBuffers` (835), `RebindImages` (871), and `CommitBindings` (953) perform identity/coherence work. Image discovery can submit the scheduler; stable descriptor bytes alone do not justify skipping aliases, uploads, barriers, or rebinding.
- `src/graphics/host_gpu/renderer/pipeline/pipelineCache.cpp:429`: driver-cache initialization requires title ID, release-class build, known revision and a clean tree. The explicit `-dirty` gate disables persistence for local dirty builds. The signature embeds revision, vendor/device/driver and pipelineCacheUUID, with a payload checksum. Save destroys the live cache, so periodic saves require a lifecycle change.

## Committed work

- `src/graphics/host_gpu/renderer/pipeline/pipelineCache.cpp`: replace recount/direct stdout with incremental, throttled regular logging.
- `src/graphics/host_gpu/renderer/pipeline/shaderCacheStats.h`: per-stage counts and monotonic one-second report throttle.
- `tests/perf/pipeline-bindings/cacheBench.cpp`: count/reference parity and throttle-boundary checks; original recount versus production counter benchmark.
- `CMakeLists.txt`: one delimited block registers `pipeline_cache_bench` and CTest `pipeline_cache_cpu`.
- This report.

The benchmark inserts 1k/10k permutations into an unordered source map, with either one source or one source per permutation. It has seven alternating before/after samples after warmup, each averaging three fresh insertions. Allocation is included; shader translation, Vulkan compilation and console output are excluded. Simplified source records have a smaller footprint than production. Report median and min-max spread, preserving raw CSVs. These will be component measurements, not game FPS.

## Uncommitted experiments left for resumption

These are incomplete and have never compiled. They are not wired into production or registered with CMake.

- `src/graphics/host_gpu/renderer/pipeline/shaderPermutationIndex.h`: candidate fieldwise specialization hash and lazy index above eight permutations; exact equality and push-layout checks remain. Numeric vector indices survive reallocation. Do not ship without measurement.
- `tests/perf/pipeline-bindings/permutationBench.cpp`: draft lookup benchmark using production specialization/compiled metadata, plus vector-growth and push-placement checks. Cases cover 1/8/64/512 variants, 1/8/32 buffers plus the same number of images, stable/changing/missing keys, and seven alternating 200k-lookup repetitions.
- `tests/perf/pipeline-bindings/bindingsBench.cpp`: draft standalone Vulkan harness exercising actual preparation/commit with sampler-only resources, push descriptors and descriptor heaps, and command rollover every 128 calls. Intended seven repetitions of 4096 calls after warmup. No guest buffers/images or shader execution: this cannot validate alias-sensitive shortcuts. Vulkan setup/lifetimes and test compilation still need verification.

## Resume steps

1. Read `C:\astra\kyty-swarm\READY.txt` and `baseline-tests.txt` when present; use their exact shared build commands. Keep all compilation and timed runs inside the build gate.
2. Build `pipeline_cache_bench`, run CTest `pipeline_cache_cpu`, and build the production pipelineCache translation unit/emulator. Run the relevant upstream regressions and separate baseline failures from regressions.
3. Run the insertion benchmark under the gate with at least five repetitions; the harness provides seven. Save raw CSV under `bench/pipeline-bindings/`, summarize median/spread, and add the missing evidence. Do not claim measured speedup until then.
4. Review and register the uncommitted lookup experiment if still useful. Measure before integrating it into ProgramCache. Preserve materialization and push-data matching. Revert an index that does not measurably help.
5. Finish the descriptor harness only if scope/budget allows. Check GPU load/foreground processes and use the gate before any Vulkan run. Do not infer safe buffer/image reuse from sampler-only results.

## Deferred designs

A format-version driver-cache signature (upstream PR #982) would permit reuse across revisions and dirty builds. Preserve device/driver/UUID validation, bounded reads, checksum and driver rejection fallback. No cache policy change or repeat-launch speedup was implemented or measured.

A recompiler-result cache needs a shader-core serialization contract for immutable resource plans, specialization, compiled metadata and SPIR-V. Exclude guest addresses, live pointers, runtime snapshots and mutable SRT evaluation scratch. Key code/back-code, logical stage, static state, specialization, push placement, subgroup assumptions and compiler/cache version. Treat malformed/truncated files as misses.

Async pipeline compilation remains out of scope. Future work needs immutable jobs, bounded workers, Vulkan cache synchronization and retained module/layout lifetimes; dependent draws must wait rather than be skipped. ResourcePlan's mutable evaluation scratch cannot be shared concurrently without an ownership change.

The statistics fix is general and plausibly upstream-worthy, but remains unverified and has no measured performance evidence. No PR was opened.
