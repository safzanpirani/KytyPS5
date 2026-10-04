# Shader-core investigation handoff

Stopped at the user's quota wrap-up request on 2026-10-04 at approximately
23:46 IST. Worktree: `C:\astra\kyty-swarm\shader-core`; branch:
`astra/shader-core`; inspected upstream revision:
`719e02574a8cdcccf47dbd3118290a3e2ebd965e`.

## Status and measurements

No production code was changed. No compiler, test, benchmark, GPU workload,
or review was run. `C:\astra\kyty-swarm\READY.txt` did not exist at the final
check. The user explicitly stopped work before the shared build setup became
available. No performance improvement is claimed.

| Measurement | Before | After | N |
|---|---:|---:|---:|
| Compiler phases | unavailable | unavailable | 0 |
| Materialization / SRT refresh | unavailable | unavailable | 0 |
| Allocations | unavailable | unavailable | 0 |
| GPU readback / driver compilation | unavailable | unavailable | 0 |

There are no runtime-confirmed failures, measured negative experiments, or raw
timing samples. Findings below come from source inspection only.

## Findings

1. **Source-confirmed bounds defect, not runtime-reproduced:**
   `src/graphics/shader/recompiler/frontend/decode/ShaderDecoder.cpp:423`
   writes `branch_targets[target_index]` without checking the index against
   `code.size()`. The bitmap is resized to exactly `code.size()` at line 421.
   Direct branch offsets can target before the beginning or beyond the end of
   the supplied code; a negative target wraps to a large unsigned PC. The later
   CFG target validation cannot protect this earlier access. A target exactly
   at the code boundary also exceeds the bitmap, although CFG validation
   deliberately permits that synthetic exit target. A prospective fix should
   mark only targets strictly inside the code span and preserve decoded target
   values for CFG validation. Do not reject the boundary target indiscriminately.
2. `src/graphics/shader/recompiler/frontend/cfg/ShaderCFG.cpp:689` recomputes
   dominator sets with temporary vectors, repeated intersections, and sorting.
   Reusing scratch vectors and preserving sorted order are candidates; no
   timings establish their priority yet.
3. `src/graphics/shader/recompiler/backend/spirv/SpirvBuilder.cpp:65` and
   `:100` receive allocated vector keys even on type/constant interning hits.
   Stack keys for scalar operands and heterogeneous map lookup could reduce
   allocation churn. Preserve declaration IDs, annotation identity, signed
   operand encoding, and vector/span overloads. Existing tests in
   `tests/shaderCfgTests.cpp` cover these distinctions.
4. `SrtWalker` already reuses dense memo contexts and scratch vectors.
   `ExtractResourcePlan` already resolves invariant phis during cloning.
   Repeated invariant-phi analysis exists elsewhere, but a new runtime cache
   may have little benefit for extracted plans. Do not cache guest memory
   contents or descriptor values across refreshes without an invalidation rule.

## Uncommitted draft files

All paths below are relative to the worktree. They are deliberately uncommitted
because the benchmark has never compiled or run:

- `CMakeLists.txt`: one delimited block registers the opt-in
  `shader_core_bench` executable using the existing full-emulator test helper.
- `tests/perf/shader-core/Corpus.h`: copied encodings and small arithmetic,
  pixel-export, and loop fixtures from existing tests, plus scaled diamonds.
  This is a selected subset, not the complete MakeCases/MakeGraphicsCases corpus.
- `tests/perf/shader-core/ShaderCoreBench.cpp`: CPU benchmark draft for decode,
  CFG, structurization, IR, SSA, passes, extraction, compilation, SPIR-V emission,
  materialization, and SRT refresh. It includes `--validate` and
  `--decode-bounds` modes. The latter is expected to expose the baseline bounds
  defect and may terminate the baseline process with an access violation.
- `bench/shader-core/sample.ps1`: draft interleaved before/after sampler.
- `bench/shader-core/summarize.py`: draft median/min/max CSV summary tool.

The C++ draft was formatted using clang-format 21.1.8 with `src/.clang-format`;
the upstream pre-commit configuration pins 22.1.3. Some small edits followed
that formatting pass. No claim of final formatting validation is made.

## Intended method and next steps

1. Read `HOTPATHS.md`, `OWNERSHIP.json`, and, once present, `READY.txt` and
   `baseline-tests.txt` in `C:\astra\kyty-swarm`. Follow their exact commands.
   Preserve the uncommitted draft when resuming. Do not touch the repo hub or
   merge other branches.
2. Finish the benchmark and compile it through `swarm-build.ps1` / the shared
   build gate. Use identical Release flags for baseline and candidates. The
   draft command line is `shader_core_bench.exe 100 --validate`. Check the
   phase harness against the real TranslateProgram and validate emitted SPIR-V.
   In particular, verify that a second emission from compiled IR is supported;
   that is how the draft isolates backend emission time. Add missing fixtures
   if broader coverage is needed. Allocations are not counted yet.
3. Preserve a baseline executable before production changes. Fix the decoder
   bounds defect first and add an upstream regression in owned tests. Verify
   both invalid targets and the permitted end-of-code target.
4. Run at least five interleaved fresh-process samples through the build gate.
   The sampler defaults to seven, with two-iteration warmups discarded by
   the summary script. Keep raw CSV and stderr under this directory. Report
   median and min/max spread. Account for other agents' CPU load: one gate
   slot alone does not prevent a second concurrent build.
5. Select optimizations from measured phase costs. Retain only measured wins.
   Run owned CPU tests, all shader tests, and GPU readback tests after checking
   GPU/foreground use and acquiring the gate. Compare SPIR-V fingerprints and
   baseline failures. Do not enable the optional SPIRV-Tools optimizer without
   evidence of GPU or driver compilation benefit.
6. Commit completed changes with individual before/after measurements and push
   only `astra/shader-core` to the fork. This handoff document is the only
   completed deliverable at the stop point.

Potential decoder and allocation improvements are general and could be
upstream-worthy after implementation and validation. Nothing is ready for a PR.
