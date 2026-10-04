#include "common/file.h"

#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <type_traits>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

static void Check(bool ok, const char* message) {
	if (!ok) {
		std::fprintf(stderr, "FileReadTests: %s\n", message);
		std::abort();
	}
}

// Compile the same harness against the void-returning baseline.
template <typename File>
static bool Read(File& file, void* data, uint32_t size, uint32_t* bytes) {
	if constexpr (std::is_void_v<decltype(file.Read(data, size, bytes))>) {
		file.Read(data, size, bytes);
		return true;
	} else {
		return file.Read(data, size, bytes);
	}
}

int main(int argc, char**) {
	const bool observe = argc > 1;
	const auto path    = std::filesystem::temp_directory_path() /
	                  ("kyty-read-error-" +
	                   std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
	std::array<uint8_t, 8> expected {1, 2, 3, 4, 5, 6, 7, 8}, data {};
	{
		Common::File file(path);
		Check(!file.IsInvalid(), "create fixture");
		file.Write(expected.data(), expected.size());
	}
	int detected = 0;
	{
		Common::File file(path, Common::File::Mode::Write);
		uint32_t     bytes = 123;
		const bool   ok    = Read(file, data.data(), data.size(), &bytes);
		detected += !ok;
		Check(bytes == 0 && (observe || !ok), "write-only read must fail, not report EOF");
	}
	{
		Common::File file(path, Common::File::Mode::Read);
		uint32_t     bytes = 123;
		Check(Read(file, data.data(), data.size(), &bytes) && bytes == data.size() &&
		          data == expected,
		      "ordinary read");
		Check(Read(file, data.data(), data.size(), &bytes) && bytes == 0, "EOF is success");
		Check(file.Seek(5) && Read(file, data.data(), data.size(), &bytes) && bytes == 3,
		      "short read is success");
#if defined(_WIN32)
		HANDLE locker = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE,
		                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
		                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
		Check(locker != INVALID_HANDLE_VALUE, "open lock owner");
		OVERLAPPED offset {};
		Check(LockFileEx(locker, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 8, 0,
		                 &offset),
		      "lock file range");
		Check(file.Seek(0), "rewind");
		bytes         = 123;
		const bool ok = Read(file, data.data(), data.size(), &bytes);
		detected += !ok;
		Check(bytes == 0 && (observe || !ok), "locked range must fail, not report EOF");
		Check(UnlockFileEx(locker, 0, 8, 0, &offset), "unlock file range");
		CloseHandle(locker);
		Check(file.Seek(0) && Read(file, data.data(), data.size(), &bytes) &&
		          bytes == data.size() && data == expected,
		      "read succeeds after transient lock failure");
#endif
	}
	{
		Common::File memory;
		Check(memory.OpenInMem(expected.data(), expected.size()), "open memory file");
		uint32_t bytes = 0;
		Check(Read(memory, data.data(), data.size(), &bytes) && bytes == data.size() &&
		          data == expected,
		      "memory read");
		Check(Read(memory, data.data(), data.size(), &bytes) && bytes == 0, "memory EOF");
	}
	Check(std::filesystem::remove(path), "remove fixture");
	std::printf("FileReadTests: detected_failures=%d; normal, short, EOF, recovery and memory "
	            "reads passed\n",
	            detected);
}
