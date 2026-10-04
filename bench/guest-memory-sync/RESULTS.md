# Guest memory and synchronization findings

Worktree: `C:\astra\kyty-swarm\guest-memory-sync`  
Branch: `astra/guest-memory-sync`  
Base: `719e02574a8cdcccf47dbd3118290a3e2ebd965e`  
Status: stopped at the user's quota wrap-up request on 2026-10-04. **Unverified.**

## Self-contained change

`src/common/threads.cpp:34` introduces a noncopyable thread-local timer owner. Its
destructor at line 43 closes the handle, including the ordinary timer fallback.
`SleepHighResolution100ns` uses that owner at line 59. Linux code is unchanged.

On the base revision, `src/common/threads.cpp:40` stores a handle returned by
`CreateWaitableTimerExW` in a raw thread-local variable. The fallback stores another
raw handle. Neither has a corresponding `CloseHandle`. This is a confirmed source
ownership defect; process handle growth has **not** been measured.

`tests/perf/guest-memory-sync/ThreadTimerTests.cpp` warms up thread creation, starts
and joins 128 threads that call both sleep APIs, and checks process handle growth
with `GetProcessHandleCount`. The tolerance is four handles. A delimited Windows-only
block in `CMakeLists.txt` registers `thread_timer_tests` / CTest `thread_timer`.

Formatting used the repository's `src/.clang-format` with clang-format 22.1.3,
matching `.pre-commit-config.yaml`.

## Measurement and verification status

| Measurement | Before | After | Median / spread | N |
|---|---|---|---|---|
| Handles retained after thread churn | Not run | Not run | Unavailable | 0 |
| 100 us condition-variable timeout | Not run | Not run | Unavailable | 0 |
| Address-wake latency, 1/2/8/24 waiters | Not run | Not run | Unavailable | 0 |
| Idle CPU and fragmented map/protect/unmap | Not run | Not run | Unavailable | 0 |

No configure, compilation, tests, benchmarks, or GPU workloads ran. Shared
`C:\astra\kyty-swarm\READY.txt` was still absent at wrap-up. No runtime performance
improvement or passing regression result is claimed. There are no measured negative
results either. The timer fix is an upstream-worthy, platform-general correctness
candidate once compiled and validated.

## Additional source findings

* `src/common/threads.cpp:365` still rounds every sub-millisecond `CondVar::WaitFor`
  request to 1 ms. This is confirmed by source, not a measured wake latency.
* The baseline Windows address-wait implementation uses a global registry, heap
  allocations, and condition variables. A replacement must retain finite wake
  counts, value-change polling, and guest signal callbacks.
* PR https://github.com/KytyPS5/KytyPS5/pull/618 and its inline reviews were read.
  Reviews identify portable-build breakage, finite-timeout overflow, waking more
  than a requested finite count, and billions of native calls for `INT_MAX - 1`.
  A further design concern is losing an unchanged-value wake during a signal
  callback if only the guest address is used as the native wait token.
* `src/kernel/pthread.cpp:96` sets native mutex signal polling to **10000 us**;
  `NativeMutexLock` uses `std::condition_variable` at lines 1272 and 1297. It does
  not use `Common::CondVar` for those waits.
* `src/kernel/memory.cpp:833` defines the global recursive memory-operation mutex.
  No contention measurements justify changing its scope. No memory or pthread
  production changes were made.

## Uncommitted drafts and resumption

These files remain local and uncommitted; none has been compiled:

* `bench/guest-memory-sync/waits.cpp`: CSV benchmark for timer churn, 100 us waits,
  condition-variable/address wake p50/p99 at 1/2/8/24 waiters, CPU time, and address
  mismatch/zero-timeout/empty-wake operations.
* `bench/guest-memory-sync/mapping.cpp`: fragmented flexible mapping, protection,
  and unmapping benchmark with disjoint reserved address ranges per worker.
* `tests/perf/guest-memory-sync/CondVarTests.cpp`: timeout, mutex reacquisition,
  mixed waiters, and signal/timeout race checks.
* `tests/perf/guest-memory-sync/AddressWaitTests.cpp`: finite counts, huge empty
  wake requests, high-word changes without wakes, and wakes during signal callbacks.
* `_build/measurement-src/threads-precise-draft.cpp`: experimental short waits
  using thread-local events and high-resolution timers. Removed from active sources.
* `_build/measurement-src/syncOnAddress-native-draft.cpp`: experimental sharded,
  allocation-free waiter records and native waits on private notification tokens.
  Removed from active sources. Check Windows header `NOMINMAX` requirements before
  compiling this draft; its native API import uses `synchronization.lib`.
* `_build/measurement-src/CMakeLists-draft.txt`: registrations for all draft targets.
* `_build/measurement-src/threads-baseline.cpp`, `syncOnAddress-baseline.cpp`, and
  `threads-raii.cpp`: snapshots for constructing comparable baseline/candidate runs.

Next agent: wait for and read `READY.txt` and `baseline-tests.txt`, then build the
timer fixture using the shared `swarm-build.ps1` and its build gate. Run the same
handle-churn harness on base and candidate at least five times; record actual
median, range, and raw counts here. Run `thread_timer`, `virtual_memory_allocation`,
`guest_red_zone_patcher`, `sync_on_address`, and `event_queue_lifetime`. Assess and
compile drafts separately only after this correctness fix passes. Measure precise
wait latency and idle CPU before retaining that experiment, and measure native
address waits independently. Do not interpret synthetic results as game FPS.
