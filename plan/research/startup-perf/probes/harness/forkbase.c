/* forkbase: the harness's OWN floor. fork() a child that calls _exit(0)
 * immediately, with no execve at all, then waitpid. Subtract this from every
 * execbench number to get the cost of the exec plus the program, without the
 * fork and the wait.
 *
 * On this VM the fork itself is a large fraction of the measurement, so
 * reporting exec numbers without this baseline would overstate every target
 * and flatten the differences between them.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/wait.h>

static int cmp_d(const void *a, const void *b) {
	double x = *(const double *)a, y = *(const double *)b;
	return (x > y) - (x < y);
}

int main(int argc, char **argv) {
	int n = argc > 1 ? atoi(argv[1]) : 400;
	double *t = malloc(sizeof(double) * n);
	for (int i = 0; i < n; i++) {
		struct timespec a, b;
		clock_gettime(CLOCK_MONOTONIC, &a);
		pid_t pid = fork();
		if (pid == 0) _exit(0);
		int st; waitpid(pid, &st, 0);
		clock_gettime(CLOCK_MONOTONIC, &b);
		t[i] = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
	}
	double sum = 0; for (int i = 0; i < n; i++) sum += t[i];
	qsort(t, n, sizeof(double), cmp_d);
	printf("%-40s n=%d  min=%.3f  p50=%.3f  p90=%.3f  p99=%.3f  mean=%.3f  max=%.3f (ms)\n",
	       "[fork+_exit+wait baseline]", n, t[0], t[n/2], t[(int)(n*0.90)], t[(int)(n*0.99)], sum/n, t[n-1]);
	return 0;
}
