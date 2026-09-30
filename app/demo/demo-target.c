#include <stdio.h>
#include <unistd.h>

/*
 * The program the app injects into by default.
 *
 * Two functions, deliberately different in one respect: the prologue of demo_guard
 * contains a conditional branch. Relocating that branch instead of copying its
 * encoding is the difference between this program finishing and it dying on an
 * undefined instruction, so the demo exercises a path that used to be broken.
 */

__attribute__((noinline, optnone)) int demo_work(int x) { return x * 3 + 1; }

__attribute__((noinline, optnone)) int demo_guard(int x) {
  if (x == 0) return -1;
  return x + 1;
}

int main(void) {
  printf("[demo] pid=%d, giving the hook a moment to install\n", getpid());
  fflush(stdout);
  sleep(2);

  for (int i = 1; i <= 5; i++) {
    int odd = i % 2;
    printf("[demo] demo_work(%d) = %d    demo_guard(%d) = %d\n", i,
           demo_work(i), odd, demo_guard(odd));
    fflush(stdout);
    sleep(1);
  }

  printf("[demo] done\n");
  return 0;
}
