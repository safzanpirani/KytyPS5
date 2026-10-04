#include "graphics/host_gpu/renderer/pipeline/shaderCacheStats.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string_view>
#include <unordered_map>
#include <vector>

using namespace Libs::Graphics;
using Clock = std::chrono::steady_clock;

namespace {

void Check(bool condition) {
	if (!condition) {
		std::fputs("cache benchmark check failed\n", stderr);
		std::exit(1);
	}
}

constexpr ShaderType Stages[] = {
    ShaderType::Vertex,
    ShaderType::Pixel,
    ShaderType::Compute,
    ShaderType::Mesh,
    ShaderType::Local,
    ShaderType::TessellationControl,
    ShaderType::TessellationEvaluation,
};

struct Source {
	ShaderType            stage;
	std::vector<uint64_t> permutations;
};

using Sources = std::unordered_map<size_t, Source>;

// The old ProgramCache recount, without printf. This deliberately excludes terminal I/O.
auto Recount(const Sources& sources) {
	decltype(ShaderCacheStats::counts) counts {};
	for (const auto& [key, source]: sources) {
		counts[static_cast<size_t>(source.stage)] += source.permutations.size();
	}
	return counts;
}

template <typename T>
void Observe(const T& value) {
	// clang-cl supports GNU extended asm on x64. Make the result observable on every insertion.
	asm volatile("" : : "g"(&value) : "memory");
}

void TestStats() {
	ShaderCacheStats stats;
	Sources          sources;
	for (size_t i = 0; i < 10000; ++i) {
		const size_t source_id = (i * 31) % 193;
		auto [entry, inserted] = sources.try_emplace(source_id, Source {Stages[source_id % 7], {}});
		entry->second.permutations.push_back(i);
		stats.Record(entry->second.stage);
		Check(stats.counts == Recount(sources));
	}
	const auto start = Clock::time_point {};
	Check(stats.ShouldReport(start));
	Check(!stats.ShouldReport(start));
	Check(!stats.ShouldReport(start + std::chrono::milliseconds(999)));
	Check(stats.ShouldReport(start + std::chrono::seconds(1)));
	Check(stats.ShouldReport(start + std::chrono::seconds(5)));
	Check(!stats.ShouldReport(start + std::chrono::milliseconds(5999)));
}

template <bool Incremental>
double Insert(size_t count, size_t source_count) {
	constexpr size_t Batches = 3;
	const auto       start   = Clock::now();
	for (size_t batch = 0; batch < Batches; ++batch) {
		Sources          sources;
		ShaderCacheStats stats;
		for (size_t i = 0; i < count; ++i) {
			const size_t source_id = i % source_count;
			auto [entry, inserted] =
			    sources.try_emplace(source_id, Source {Stages[source_id % 7], {}});
			entry->second.permutations.push_back(i);
			if constexpr (Incremental) {
				stats.Record(entry->second.stage);
				Observe(stats.counts);
			} else {
				const auto counts = Recount(sources);
				Observe(counts);
			}
		}
	}
	return std::chrono::duration<double, std::micro>(Clock::now() - start).count() / Batches;
}

void BenchmarkStats() {
	std::puts("case,implementation,N,sources,repetition,microseconds");
	for (const size_t n: {1000u, 10000u}) {
		for (const size_t sources: std::array<size_t, 2> {1, n}) {
			Insert<false>(n, sources);
			Insert<true>(n, sources);
			for (int rep = 0; rep < 7; ++rep) {
				double before, after;
				if (rep % 2 == 0) {
					before = Insert<false>(n, sources);
					after  = Insert<true>(n, sources);
				} else {
					after  = Insert<true>(n, sources);
					before = Insert<false>(n, sources);
				}
				std::printf("insert,recount,%zu,%zu,%d,%.3f\n", n, sources, rep, before);
				std::printf("insert,incremental,%zu,%zu,%d,%.3f\n", n, sources, rep, after);
			}
		}
	}
}

} // namespace

int main(int argc, char** argv) {
	TestStats();
	if (argc == 2 && std::string_view(argv[1]) == "--test") {
		std::puts("pipeline cache tests passed");
		return 0;
	}
	BenchmarkStats();
}
