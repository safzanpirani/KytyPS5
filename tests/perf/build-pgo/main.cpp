#include <cstdio>

int transform(int value);

int main() {
  int sum = 0;
  for (int i = 0; i < 1000; ++i) {
    sum += transform(i);
  }
  std::printf("%d\n", sum);
  return sum == 867011 ? 0 : 1;
}
