# Build optimization handoff — unverified

Worktree: `C:\astra\kyty-swarm\build-pgo`  
Branch: `astra/build-pgo`  
Base: `719e02574a8cdcccf47dbd3118290a3e2ebd965e`  
Stopped: 2026-10-04, approximately 23:45 IST, at the user's quota stop request.

## Status and measurements

No configure, compilation, test execution, or benchmark was started by this
agent. The shared `READY.txt` was absent at the last check. Existing `_build/dev`
files and logs were prepared by shared infrastructure; they are not validation
of these changes. The user then explicitly prohibited further verification.

| Comparison | Before median | After median | Spread | N | Conclusion |
|---|---:|---:|---:|---:|---|
| Release vs ThinLTO | unavailable | unavailable | unavailable | 0 | Not measured |
| ThinLTO vs x86-64-v3 | unavailable | unavailable | unavailable | 0 | Not measured |
| ThinLTO vs raptorlake | unavailable | unavailable | unavailable | 0 | Not measured |
| ThinLTO vs PGO | unavailable | unavailable | unavailable | 0 | Not measured |
| O3, whole-program vtables, inline threshold, sections, link.exe | unavailable | unavailable | unavailable | 0 | Not measured |

No binary-size, link-time, peak-memory, FPS, or runtime improvement is claimed.
There are no measured negative results. No tuned setting is recommended yet.

## Implemented, not verified

- `src/utils.cmake`: opt-in `KYTY_ENABLE_LTO`, `KYTY_CPU_TARGET`,
  `KYTY_PGO_GENERATE`, `KYTY_PGO_USE`, and `KYTY_LTO_JOBS` (default 3).
  Conflicting PGO modes and missing profiles fail configuration. Windows
  instrumentation resolves the compiler's profile runtime explicitly because
  CMake invokes the linker directly. Profile timestamps become object dependencies.
- Root and common CMake files apply options to first-party executables, tests,
  and common code. Bundled dependencies retain their existing flags. Defaults
  are intended to be inert; compile-command parity still needs verification.
  Ninja ThinLTO links use a serial pool. No PCH setting was added because this
  checkout does not configure a project PCH.
- `tests/ShaderRecompilerComputeTests.cpp` and
  `tests/perf/build-pgo/ShaderCompileBenchmark.inc`: CPU-only synthetic shader
  selectors `--benchmark-shader-train` and `--benchmark-shader-holdout`.
  They disable IR dumps, validate reference SPIR-V outside timing, and compare
  emitted words during repeated compilation. Train and holdout use disjoint
  cases. Both the fixtures and their output checksums remain unexecuted.
- `bench/pgo-train.ps1`: gated instrumentation, training, profile merge, and
  profile-use rebuilding in the same build directory. Training uses shader
  arithmetic cases, clean memory uploads, and archive tests. Held-out shader
  cases, page manager, NGS2, resource tracking, and shader CFG tests execute only
  after profile use. Training profiles live in a fresh timestamped directory.
- `bench/build-pgo/build-matrix.ps1`: gated machine-local experimental variants.
  Experimental flags are harness inputs, not recommended production defaults.
- `bench/build-pgo/measure.py`: alternating variant order, one warmup, seven
  repetitions by default, full output logs, raw JSON, median/min/max, checksum
  parity, and exit-code recording. Failed tests do not count as successful times.
- `bench/build-pgo/monitor-build.py`: build logs and sampled linker resource use.
  Requires psutil (7.2.2 is installed). Link durations are sampled observations,
  not exact timings; the sampling interval is recorded.
- `tests/perf/build-pgo/{CMakeLists.txt,main.cpp,library.cpp}` and
  `bench/build-pgo/verify-options.ps1`: a smoke fixture for default flags,
  ThinLTO, profile generation/use, profile paths with spaces, profile invalidation,
  and contradictory settings. Not run.

Only Python syntax compilation of the two harness scripts and PowerShell parser
checks of `bench/pgo-train.ps1` and `bench/build-pgo/build-matrix.ps1` ran; they
passed. `git diff --check` passed before the last additions. New C++ fixture
files were formatted with installed clang-format. The repository pre-commit
clang-format hook applies only to `src/` C++ files; none were changed.

## Confirmed source findings

These are code observations, not measured bottlenecks or reproduced runtime bugs.

- `src/utils.cmake:89`: upstream clang-cl Release already adds `/O2` and NDEBUG.
  Existing flags retain frame pointers. No blanket fast-math or aliasing change
  is appropriate for this comparison.
- `C:\astra\kyty\build-windows.ps1`: lead's opt build combines global IPO,
  `raptorlake`, `/opt:ref`, `/opt:icf`, and `/threads:3`. That comparison cannot
  attribute a win to one setting. Lead benchmark results were not available
  when inspected.
- `src/graphics/guest_gpu/command_processor/pm4Handlers.cpp:1932`, `:2218`,
  `:2233`: diagnostic `fetch_add` executes before LOGF suppression on indirect
  buffers and marker packets. `src/graphics/guest_gpu/graphicsRun.cpp:710` does
  the same on predicated skips. These files belong to the GPU-lane owner and
  were not modified.
- `src/common/emulatorConfig.h:61`: Vulkan validation, shader validation,
  graphics dumps, GPU-assisted validation, and profiling default off. Logging
  defaults to Silent. `src/common/profiler.h` still constructs guarded Tracy
  zones; this is not evidence that disabling Tracy would improve runtime.

No new correctness defect in owned production code was reproduced or fixed.

## Resume procedure

1. Wait for `C:\astra\kyty-swarm\READY.txt`; read its exact commands and
   `baseline-tests.txt`. Preserve shared infrastructure and other agents' work.
2. Load the x64 environment and run the smoke checks first:

   ```powershell
   . C:\astra\kyty-swarm\env.ps1
   ./bench/build-pgo/verify-options.ps1
   ```

3. Run `./bench/build-pgo/build-matrix.ps1 -Variant dev`, then `-Variant thin`.
   The script enters the shared gate. Inspect actual compile/link commands and
   fix any build failures before proceeding. Confirm the new CPU shader cases
   compile, validate, and produce identical checksums across variants.
4. Inside the shared gate, invoke the measurement harness, for example:

   ```powershell
   & C:\astra\kyty-swarm\buildgate.ps1 -Label build-pgo-bench -Command {
       python ./bench/build-pgo/measure.py --build dev=_build/pgo-dev --build thin=_build/pgo-thin --output bench/build-pgo/runs/dev-thin
   }
   ```

   Avoid concurrent builds while timing. The gate allows two holders, so merely
   owning a slot does not prove a quiet machine. Before selecting `gpu_tiler`,
   inspect nvidia-smi and foreground activity, and coordinate exclusive GPU use.
   Preserve baseline failures and exclude failed cases from speedup claims.
5. Continue with v3, raptor, and the other experimental variants only if time
   and memory permit. Build and link one LTO configuration at a time. Compare
   each against the appropriate matching baseline. The link.exe experiment
   excludes kyty_emulator because its upstream link options include `/lldmap`.
6. Supply the dependency cache options from the matrix driver to
   `bench/pgo-train.ps1 -CMakeArgs ...` and run the complete workflow. Verify
   llvm-profdata matches the configured compiler and review missing-profile
   diagnostics. Do not train on held-out tests. Measure PGO on held-out cases.
7. Record raw results and medians/spreads, binary sizes, link times and memory;
   remove ineffective flags and fix unsupported paths. Run required upstream
   validation. Only then consider this upstream-ready.

This infrastructure may be useful upstream after validation. There is currently
no evidence for a substantial general performance improvement, and CPU-specific
settings must remain opt-in. No PR was opened.
