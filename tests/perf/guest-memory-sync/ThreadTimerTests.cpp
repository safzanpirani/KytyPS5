#include <windows.h>

#include "common/threads.h"

#include <cstdio>
#include <thread>

int main() {
	std::thread([] { Common::Thread::SleepMicro(1); }).join();
	DWORD before = 0, after = 0;
	if (!GetProcessHandleCount(GetCurrentProcess(), &before)) return 1;
	for (int i = 0; i < 128; ++i) {
		std::thread([] {
			Common::Thread::SleepMicro(1);
			Common::Thread::SleepNano(1000);
		}).join();
	}
	if (!GetProcessHandleCount(GetCurrentProcess(), &after)) return 1;
	std::printf("timer thread churn: before=%lu after=%lu\n", before, after);
	return after > before + 4 ? 1 : 0;
}
