#ifndef EMULATOR_SRC_GRAPHICS_HOST_GPU_RENDERER_SHADERCACHESTATS_H_
#define EMULATOR_SRC_GRAPHICS_HOST_GPU_RENDERER_SHADERCACHESTATS_H_

#include "graphics/shader/shader.h"

#include <array>
#include <chrono>
#include <cstddef>

namespace Libs::Graphics {

// ProgramCache only adds permutations, and the renderer serializes its access.
struct ShaderCacheStats {
	using Clock = std::chrono::steady_clock;
	std::array<size_t, static_cast<size_t>(ShaderType::TessellationEvaluation) + 1> counts {};

	void Record(ShaderType stage) { ++counts[static_cast<size_t>(stage)]; }

	bool ShouldReport(Clock::time_point now) {
		if (now < next_report) {
			return false;
		}
		next_report = now + std::chrono::seconds(1);
		return true;
	}

private:
	Clock::time_point next_report = Clock::time_point::min();
};

} // namespace Libs::Graphics

#endif // EMULATOR_SRC_GRAPHICS_HOST_GPU_RENDERER_SHADERCACHESTATS_H_
