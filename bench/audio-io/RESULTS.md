# Audio and file I/O handoff — 2026-10-04

Worktree: `C:\astra\kyty-swarm\audio-io`. Branch: `astra/audio-io`.
Base: upstream `719e02574a8cdcccf47dbd3118290a3e2ebd965e`.

Work stopped at approximately 23:47 IST at the user's request because the weekly quota was nearly exhausted. No configure, build, test, benchmark, or runtime reproduction was executed. `C:\astra\kyty-swarm\READY.txt` was still absent at 23:46 IST. All committed changes are explicitly **unverified**. No performance improvement is claimed.

## Findings and completed implementation

- `src/common/platform/sysWindowsFileIO.cpp:66`: the original `SysFileRead` ignored `ReadFile`'s return status and exposed only the byte count. A native failure therefore looked like EOF. The implementation now returns success separately from the byte count; `src/common/file.cpp:251` forwards it. The POSIX implementation uses `ferror` and clears the previous operation's status before reading.
- `src/kernel/fileSystem.cpp:641`, `:766`, `:868`: read, pread, and preadv now propagate native errors as `EIO` when no bytes were transferred. Partial reads remain partial successes; EOF remains successful. Read and pread also reject write-only descriptors with `EBADF`, matching the existing preadv validation. Pread checks seek and restore failures.
- `src/libs/audio.cpp:547`: output formerly used port configuration, volumes, pacing state, and SDL stream pointers outside the mutex used by close and volume updates. Close could destroy a stream during output. Output now validates the entire batch and holds that mutex through queue/state work, copies the return sample count, and releases the lock before the final pacing sleep. Queue-backpressure waits still hold the lock; this is a correctness fix, not a concurrency optimization.
- Added ordinary read-failure coverage in `tests/perf/audio-io/FileReadTests.cpp` and `tests/KernelFileSystemTests.cpp`: write-only handles, Windows byte-range locks, recovery, short reads, and EOF. The standalone common-file test also covers memory files.
- Added a controlled concurrent close/output test to `tests/AudioOutTimingTests.cpp`. It checks five repetitions. Its optional argument observes the original behavior instead of asserting the fix. Five dummy-output timing repetitions are also present, but have not run.

These defects are confirmed by source inspection. Runtime reproduction and regression verification remain pending.

## Uncommitted draft work

Preserve these files when resuming:

- `src/libs/ajm.cpp`: draft shared ownership, per-instance mutex, destruction synchronization, sideband lifetime protection, and reusable split input/output buffers. This draft has not been compiled or formatted fully; do not ship it without validation and measurements.
- `tests/perf/audio-io/AjmConcurrencyTests.cpp`: draft independent-instance, same-instance, destroy/sideband, and scratch-zeroing tests using a controlled decoder.
- `bench/audio-io/AjmBench.cpp`: generated legal ATRAC9 fixture, one/eight independent instances, contiguous/split buffers, five timing repetitions, output hashes.
- `bench/audio-io/Ngs2Bench.cpp`: generated PCM graphs, 8/32/128 samplers plus mixers/mastering, fan-out 1/4, channels 2/8, five repetitions, output hashes.
- `bench/audio-io/FileBench.cpp`: generated 64 MiB file; 4 KiB random and 1 MiB sequential read sequences; one/eight threads sharing a file with the existing seek/read/restore mutex pattern; five repetitions. This measures Common::File overhead, not guest memory invalidation or physical cold-disk throughput.
- `CMakeLists.txt`: additional uncommitted benchmark and AJM-test registrations inside the delimited audio-io block. The committed part registers only the standalone file-read regression test.

The original AJM global lock covered codec decode. Raw decoder/gapless pointers also escaped the lock before sideband writes (`AjmBatchJobGetCodecInfo`, `AjmBatchJobControl`, `AjmBatchJobRun`, and `AjmBatchJobRunSplit`). The draft retains one owning instance guard through those operations.

## Measurements

| Case | Before median / spread | After median / spread | N |
|---|---|---|---:|
| File read failures / recovery | Not run | Not run | 0 |
| Audio concurrent close / output | Not run | Not run | 0 |
| Dummy audio output timing | Not run | Not run | 0 |
| AJM 1/8 instances, contiguous/split | Not run | Not run | 0 |
| NGS2 8/32/128 voice graphs | Not run | Not run | 0 |
| File 4 KiB random / 1 MiB sequential, 1/8 readers | Not run | Not run | 0 |

There are no raw timing files and no measured positive or negative performance results.

## Deliberately deferred

- No NGS2 production optimization was made. Reverse adjacency must preserve source/port summation order and handle graph mutations from callbacks. Skipping zero matrix terms can change NaN, infinity, or signed-zero behavior; a finite-PCM benchmark alone does not prove equivalence.
- No positioned-read optimization was made. Supplying an OVERLAPPED offset on a synchronous Windows handle does not preserve its current file pointer. Removing the guest mutex on that basis would be incorrect. Concurrent handle lifetime, ordinary reads/writes, and archive fallback also need validation.
- No archive worker changes or archive throughput measurements were made.
- No PR was opened. Only the requested feature branch is pushed.
- Linux behavior has not been compiled or tested.

## Resume procedure

1. Read `HOTPATHS.md`, `OWNERSHIP.json`, `READY.txt`, and `baseline-tests.txt` in `C:\astra\kyty-swarm\`. Preserve the uncommitted draft and benchmark sources listed above.
2. Inspect and finish the draft fixtures and AJM implementation before compiling them. Format changed regions with `C:\Program Files\LLVM\bin\clang-format.exe --style=file:src/.clang-format`.
3. Once READY exists, use its current exact commands. The shared wrapper already invokes the build gate. Expected correctness command, subject to READY:

   ```powershell
   pwsh -NoProfile -File C:\astra\kyty-swarm\swarm-build.ps1 -Worktree C:\astra\kyty-swarm\audio-io -Variant dev -Action all -Targets audio_io_file_read_tests,audio_out_timing_tests,audio_out2_port_tests,ngs2_sampler_tests,archive_file_tests,avplayer_file_tests,kernel_file_system_tests -TestRegex '^(audio_io_file_read|audio_out_timing|audio_out2_port|ngs2_sampler|archive_file|avplayer_file|kernel_file_system)$'
   ```

4. Build the draft AJM tests and benchmark targets separately after resolving any compile problems. No baseline executable exists yet. Capture both original and changed production code using the same harness and build flags; preserve all current edits before temporarily restoring baseline owned files. Do not use other agents' worktrees or modify the repo hub.
5. Run timing under the shared gate, retain raw output under this directory, and report at least five repetitions with median and min–max spread. Compare output hashes. Check GPU/foreground activity before the Vulkan-backed kernel filesystem test or any GPU benchmark.
6. Keep correctness fixes even if they add small necessary synchronization cost. Ship AJM or other optimizations only with measured wins and passing regressions. Add measurements to the commit bodies and this document, then push `astra/audio-io` to `fork`.

The read-error and audio-lifetime fixes are general and potentially upstream-worthy once verified. The AJM draft needs correctness review, actual output parity, and performance evidence.
