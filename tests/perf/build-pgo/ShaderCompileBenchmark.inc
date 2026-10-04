// Included by the compute test harness after its synthetic case definitions.
// No Vulkan device, driver cache, IR dumps or timed SPIR-V validation is used.
std::vector<u32> CompileBenchmarkCase(const TestCase &test) {
  auto user_data = MakeNativeUserData(nullptr);
  user_data[2] = static_cast<u32>(test.initial.size() * sizeof(u32));
  auto compute_info = test.compute_info;
  compute_info.host_subgroup_size = 64;
  ShaderRecompiler::CompileOptions options;
  options.stage = ShaderType::Compute;
  options.dump_ir = false;
  options.input_info.compute = &compute_info;
  options.user_data = user_data;
  if (test.has_compute_info) {
    options.wave_size = compute_info.wave_size;
  }
  auto translated = ShaderRecompiler::TranslateProgram(test.code, options);
  auto plan = ShaderRecompiler::IR::ExtractResourcePlan(translated.program);
  ShaderRecompiler::IR::ResourceSnapshot resources;
  ShaderRecompiler::IR::ResourceSpecialization specialization;
  const ShaderRecompiler::IR::SrtRuntime runtime{
      .user_data = options.user_data,
      .shader_base = reinterpret_cast<uint64_t>(test.code.data()),
      .read_memory = ReadTestMemory,
      .userdata = const_cast<std::vector<u32> *>(&test.initial),
      .read_specialization_memory = ReadTestMemory,
  };
  Require(test.name, "benchmark materialization",
          ShaderRecompiler::IR::MaterializeResources(plan, runtime, resources,
                                                     specialization),
          "failed to materialize synthetic resources");
  return ShaderRecompiler::CompileProgram(std::move(translated), options,
                                          specialization)
      .spirv;
}

void RunShaderCompileBenchmark(bool training) {
  const std::vector<TestCase> cases =
      training ? std::vector<TestCase>{IntegerAddSubMul(), BitwiseOps(),
                                       Shifts(), ScalarExtendedArithmetic()}
               : std::vector<TestCase>{ScalarCompareOps(), ScalarSaveExecOps(),
                                       ScalarSubvectorLoops(32),
                                       ScalarSubvectorLoops(64)};
  std::vector<std::vector<u32>> expected;
  uint64_t checksum = 14695981039346656037ull;
  for (const auto &test : cases) {
    expected.push_back(CompileBenchmarkCase(test));
    ValidateSpirv(test.name, expected.back());
    for (const auto word : expected.back()) {
      checksum = (checksum ^ word) * 1099511628211ull;
    }
  }
  uint64_t sweeps = 0;
  const auto start = std::chrono::steady_clock::now();
  std::chrono::nanoseconds elapsed{};
  do {
    for (size_t i = 0; i < cases.size(); ++i) {
      Require(cases[i].name, "benchmark determinism",
              CompileBenchmarkCase(cases[i]) == expected[i],
              "SPIR-V changed between repeated compilations");
    }
    ++sweeps;
    elapsed = std::chrono::steady_clock::now() - start;
  } while (elapsed < std::chrono::seconds(1));
  std::printf(
      "shader_partition,compilations,elapsed_ns,ns_per_compile,checksum\n"
      "%s,%llu,%lld,%.2f,%llu\n",
      training ? "train" : "holdout",
      static_cast<unsigned long long>(sweeps * cases.size()),
      static_cast<long long>(elapsed.count()),
      static_cast<double>(elapsed.count()) / (sweeps * cases.size()),
      static_cast<unsigned long long>(checksum));
}
