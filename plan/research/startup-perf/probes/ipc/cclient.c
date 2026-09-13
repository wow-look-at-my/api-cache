/* The C shim client: the sccache-style "thin native client, fat daemon"
 * architecture. It is the smallest useful thing — connect to a unix socket,
 * write one length-prefixed request, read one length-prefixed reply, exit.
 * No allocator beyond the stack, no stdio, no dynamic library beyond libc.
 *
 * Against the Go client of the same protocol this bounds what the shim buys:
 * the difference is the Go runtime's startup, since both pay the same
 * connect-and-round-trip syscalls.
 *
 * usage: cclient [iterations] [socket]
 *   iterations > 1 also reports in-process per-op time.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/un.h>

static int rt(int fd, const char *req, unsigned len) {
	unsigned char hdr[4];
	hdr[0]=len&0xff; hdr[1]=(len>>8)&0xff; hdr[2]=(len>>16)&0xff; hdr[3]=(len>>24)&0xff;
	if (write(fd, hdr, 4) != 4) return -1;
	if (write(fd, req, len) != (ssize_t)len) return -1;
	unsigned char rh[4];
	ssize_t got = 0;
	while (got < 4) { ssize_t r = read(fd, rh+got, 4-got); if (r <= 0) return -1; got += r; }
	unsigned rl = rh[0] | (rh[1]<<8) | (rh[2]<<16) | ((unsigned)rh[3]<<24);
	char buf[4096];
	if (rl > sizeof buf) return -1;
	got = 0;
	while (got < (ssize_t)rl) { ssize_t r = read(fd, buf+got, rl-got); if (r <= 0) return -1; got += r; }
	return 0;
}

static int dial(const char *path) {
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) return -1;
	struct sockaddr_un a;
	memset(&a, 0, sizeof a);
	a.sun_family = AF_UNIX;
	strncpy(a.sun_path, path, sizeof(a.sun_path) - 1);
	if (connect(fd, (struct sockaddr *)&a, sizeof a) < 0) { close(fd); return -1; }
	return fd;
}

int main(int argc, char **argv) {
	int n = argc > 1 ? atoi(argv[1]) : 1;
	const char *sock = argc > 2 ? argv[2] : "/tmp/apcache-bench.sock";
	char req[512];
	for (int i = 0; i < 512; i++) req[i] = 'a' + i % 26;

	if (n <= 1) {
		int fd = dial(sock);
		if (fd < 0) { perror("connect"); return 1; }
		if (rt(fd, req, sizeof req) < 0) { perror("roundtrip"); return 1; }
		close(fd);
		return 0;
	}

	struct timespec a, b;
	clock_gettime(CLOCK_MONOTONIC, &a);
	for (int i = 0; i < n; i++) {
		int fd = dial(sock);
		if (fd < 0) { perror("connect"); return 1; }
		if (rt(fd, req, sizeof req) < 0) return 1;
		close(fd);
	}
	clock_gettime(CLOCK_MONOTONIC, &b);
	double cold = ((b.tv_sec-a.tv_sec)*1e9 + (b.tv_nsec-a.tv_nsec)) / n / 1000.0;

	int fd = dial(sock);
	rt(fd, req, sizeof req);
	clock_gettime(CLOCK_MONOTONIC, &a);
	for (int i = 0; i < n; i++) rt(fd, req, sizeof req);
	clock_gettime(CLOCK_MONOTONIC, &b);
	double warm = ((b.tv_sec-a.tv_sec)*1e9 + (b.tv_nsec-a.tv_nsec)) / n / 1000.0;
	close(fd);

	printf("c client:  dial+roundtrip+close %.1f us/op   roundtrip only (reused conn) %.1f us/op\n", cold, warm);
	return 0;
}
