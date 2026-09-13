/* execbench: fork+exec+wait a target N times, report min/median/p90/p99/mean wall time.
 *
 * This is the shape a compiler wrapper is invoked in: a build tool forks and
 * execs the wrapper once per translation unit, then waits for it. The fork and
 * wait overhead of the harness itself is a constant across every target, so the
 * DIFFERENCE between targets is the number that matters.
 *
 * usage: execbench N /path/to/prog [args...]
 * Child stdout/stderr go to /dev/null so output volume is not measured.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/wait.h>

static int cmp_d(const void *a, const void *b) {
	double x = *(const double *)a, y = *(const double *)b;
	return (x > y) - (x < y);
}

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: execbench N prog [args...]\n"); return 2; }
	int n = atoi(argv[1]);
	if (n < 1) n = 1;
	double *t = malloc(sizeof(double) * n);
	int devnull = open("/dev/null", O_WRONLY);

	for (int i = 0; i < n; i++) {
		struct timespec a, b;
		clock_gettime(CLOCK_MONOTONIC, &a);
		pid_t pid = fork();
		if (pid == 0) {
			dup2(devnull, 1);
			dup2(devnull, 2);
			execv(argv[2], &argv[2]);
			_exit(127);
		}
		int st = 0;
		waitpid(pid, &st, 0);
		clock_gettime(CLOCK_MONOTONIC, &b);
		if (WEXITSTATUS(st) == 127) { fprintf(stderr, "exec failed: %s\n", argv[2]); return 2; }
		t[i] = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6; /* ms */
	}
	double sum = 0;
	for (int i = 0; i < n; i++) sum += t[i];
	double mean = sum / n;
	qsort(t, n, sizeof(double), cmp_d);
	printf("%-40s n=%d  min=%.3f  p50=%.3f  p90=%.3f  p99=%.3f  mean=%.3f  max=%.3f (ms)\n",
	       argv[2], n, t[0], t[n/2], t[(int)(n*0.90)], t[(int)(n*0.99)], mean, t[n-1]);
	return 0;
}
