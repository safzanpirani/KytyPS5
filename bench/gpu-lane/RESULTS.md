# GPU-lane handoff: unverified prototypes

Stopped on the user's urgent quota wrap-up instruction on 2026-10-04, before building or measuring. No production code changes, completed optimizations, or PRs. Only this investigation report is being committed; all prototype sources remain uncommitted. Branch: `astra/gpu-lane`, base `719e02574a8cdcccf47dbd3118290a3e2ebd965e`.

## Findings

- `src/graphics/presentation/window/window.cpp:916` (`UpdateTitle`) formats and synchronously dispatches an SDL main-thread callback every presented frame; the blocking dispatch is at line 961. This is confirmed source-level overhead, with no measured latency yet. Upstream PR 1013 was read; it changes to heap-owned text but retains a raw window pointer.
- `3rdparty/SDL3/src/events/SDL_events.c:1346` (`SDL_QuitMainThreadCallbacks`) discards asynchronous callbacks without invoking them or freeing their userdata. A heap-only callback payload therefore needs cancellation cleanup as well as window lifetime protection.
- `src/graphics/guest_gpu/graphicsRun.cpp:499` (CPU-command branch) leaves blocked queue fronts marked blocked after a command writes a waited-on label and can enter the timed wait at line 478. The incomplete-submission branch at line 514 also does not rearm other blocked queues after a producer writes a label and subsequently blocks. These are source observations, not measured performance results or demonstrated semantic defects. Line references use base 719e025.

## Files left uncommitted

- `bench/gpu-lane/titleBaseline.h`: isolated upstream title scheduling behavior.
- `bench/gpu-lane/titleCandidate.h`: experimental per-window FPS cadence, copied title text owned by SDL window properties, coalescing, and a callback carrying only an SDL window ID. Not integrated into production.
- `bench/gpu-lane/titleBenchmark.cpp`: synthetic 180-frame SDL loop, 16.667 ms frame work, configurable main-thread delay (default 8 ms). Candidate selected by `KYTY_BENCH_TITLE_CANDIDATE=1`. Reports interval and title-call p50/p99 in microseconds, frame/update counts.
- `bench/gpu-lane/queueBenchmark.cpp`: reuses upstream VulkanHarness through an include with renamed main. Exercises CPU-command and cross-queue releases, NOP/register/indirect throughput, and timeline submission counts. Unbuilt and unrun.
- `tests/perf/gpu-lane/windowTitleTests.cpp`: prototype tests for FPS cadence, temporary string ownership, coalescing, inline callback, destruction/recreation, and discarded callbacks at quit. Unbuilt and unrun.

Unfinished CMake registrations were removed during wrap-up. Existing tracked source files are unchanged.

## Measurements and verification

| Workload | Before | After | N | Status |
| --- | --- | --- | --- | --- |
| Title latency | unavailable | unavailable | 0 | Not run |
| Queue wake latency | unavailable | unavailable | 0 | Not run |
| Packet throughput | unavailable | unavailable | 0 | Not run |

No configure, build, test, benchmark, or production verification command was run. Prototype C++ files were formatted with clang-format 21.1.8 using `src/.clang-format`; upstream's hook pins 22.1.3. No performance gain is claimed.

`C:\astra\kyty-swarm\READY.txt` was absent at the last check before wrap-up. The desktop GPU showed 33–35% utilization and Parsec processes; no GPU benchmark was started. Do not stop those processes.

## Resume

1. Read `HOTPATHS.md`, `OWNERSHIP.json`, `READY.txt`, and `baseline-tests.txt` in `C:\astra\kyty-swarm`. Follow current shared build commands and the build gate.
2. Register the two title benchmark executables (SDL3 static and fmt dependencies; candidate compile definition above) and the prototype test (SDL3 static). Register the queue benchmark with `add_kyty_full_emulator_test` and the generated `gpu_test_ms_depth_spv.h` dependency if pursuing it.
3. Build and measure baseline/candidate with identical flags, at least five interleaved repetitions, preserving raw results. Check GPU/foreground load and hold the benchmark gate before the Vulkan harness.
4. Only integrate a measured title win into owned presentation files. Initialize title state on the SDL thread after window creation, tick before formatting in UpdateTitle, and use the tested asynchronous queue. Verify shutdown and all required upstream tests.
5. Measure the scheduler observations before changing queue retry behavior. Preserve raw CPU-memory polling fallback, packet-boundary fault service, CE/DE ordering, indirect chains, label timing, and flip semantics.
6. Record results, commit verified improvements, and push only `astra/gpu-lane` to `fork`. No PR is currently prepared.
