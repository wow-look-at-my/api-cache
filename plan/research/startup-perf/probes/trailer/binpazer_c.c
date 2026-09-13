/* The C side of the binpazer cooked-trailer read.
 *
 * This is the "thin native client" bound: what a C shim would pay per exec to
 * pull its compiled rules out of a container appended to its own executable.
 * binpazer's C implementation takes injected read and seek callbacks and
 * allocates nothing, so the callbacks here are pread against one fd with a
 * base offset, which is exactly how a trailer is addressed.
 *
 * usage: binpazer_c <file> <containerLen> [iterations]
 *
 * The container is located the same way the Go probe locates it: the file's
 * last 8 bytes hold the container length, the container's own last 16 bytes
 * are binpazer's footer, and every offset inside is relative to the container
 * start, which the base offset in the context rebases.
 *
 * binpazer is MIT licensed (github.com/wow-look-at-my/bin-file-fmt).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include "binpazer.h"

#define TYPE_STRINGS 0x4000
#define TYPE_RULES   0x4001

/* The reader's cursor, rebased onto the container inside the host file. */
typedef struct {
	int      fd;
	uint64_t base;   /* container start within the file */
	uint64_t pos;    /* cursor, relative to base */
} ctx_t;

static size_t rd(void *vc, void *buf, size_t n) {
	ctx_t *c = vc;
	ssize_t got = pread(c->fd, buf, n, (off_t)(c->base + c->pos));
	if (got <= 0) return 0;
	c->pos += (uint64_t)got;
	return (size_t)got;
}

static int sk(void *vc, uint64_t off) {
	ctx_t *c = vc;
	c->pos = off;
	return 0;
}

static int cmp_d(const void *a, const void *b) {
	double x = *(const double *)a, y = *(const double *)b;
	return (x > y) - (x < y);
}

/* one_read performs the whole per-exec job: open, find the container, read the
 * header and type table, look up the rules block through the index, and read
 * its payload. */
static int one_read(const char *path, uint8_t *payload, size_t cap, uint64_t *plen) {
	int fd = open(path, O_RDONLY);
	if (fd < 0) return -1;

	unsigned char tail[8];
	/* Locate the container: its length is the file's last 8 bytes. */
	off_t end = lseek(fd, 0, SEEK_END);
	if (pread(fd, tail, 8, end - 8) != 8) { close(fd); return -1; }
	uint64_t clen = 0;
	for (int i = 7; i >= 0; i--) clen = (clen << 8) | tail[i];

	ctx_t c = { .fd = fd, .base = (uint64_t)(end - 8) - clen, .pos = 0 };

	binpazer_reader r;
	binpazer_type_entry types[16];
	size_t ntypes = 0;
	if (binpazer_reader_begin(&r, rd, sk, &c, NULL, 0, types, 16, &ntypes) != BINPAZER_OK) {
		close(fd); return -1;
	}
	if (!r.has_index) { close(fd); return -2; } /* the index is the whole point */

	binpazer_index_entry hits[8];
	size_t nhits = 0;
	if (binpazer_reader_find(&r, TYPE_RULES, hits, 8, &nhits) != BINPAZER_OK || nhits == 0) {
		close(fd); return -1;
	}
	binpazer_block blk;
	if (binpazer_reader_at(&r, types, ntypes, hits[0].offset, &blk) != BINPAZER_OK) {
		close(fd); return -1;
	}
	if (blk.payload_len > cap) { close(fd); return -1; }
	if (binpazer_reader_read_payload(&r, &blk, payload, cap) != BINPAZER_OK) {
		close(fd); return -1;
	}
	*plen = blk.payload_len;
	close(fd);
	return 0;
}

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: binpazer_c <file> [iterations]\n"); return 2; }
	const char *path = argv[1];
	int n = argc > 2 ? atoi(argv[2]) : 300;

	static uint8_t payload[1 << 20];
	uint64_t plen = 0;

	/* warm up: the first read pays the page cache, which is not the steady state */
	for (int i = 0; i < 5; i++) {
		int rc = one_read(path, payload, sizeof payload, &plen);
		if (rc != 0) { fprintf(stderr, "read failed rc=%d\n", rc); return 1; }
	}

	double *t = malloc(sizeof(double) * n);
	for (int i = 0; i < n; i++) {
		struct timespec a, b;
		clock_gettime(CLOCK_MONOTONIC, &a);
		if (one_read(path, payload, sizeof payload, &plen) != 0) return 1;
		clock_gettime(CLOCK_MONOTONIC, &b);
		t[i] = ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / 1000.0;
	}
	qsort(t, n, sizeof(double), cmp_d);
	double sum = 0; for (int i = 0; i < n; i++) sum += t[i];
	printf("| C: open + footer + index + rules block | %.1f | %.1f | %.1f | payload %llu B, allocation-free reader |\n",
	       t[0], t[n/2], sum/n, (unsigned long long)plen);

	/* The syscall floor under it: open and close alone. */
	for (int i = 0; i < n; i++) {
		struct timespec a, b;
		clock_gettime(CLOCK_MONOTONIC, &a);
		int fd = open(path, O_RDONLY);
		close(fd);
		clock_gettime(CLOCK_MONOTONIC, &b);
		t[i] = ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / 1000.0;
	}
	qsort(t, n, sizeof(double), cmp_d);
	sum = 0; for (int i = 0; i < n; i++) sum += t[i];
	printf("| C: open + close only | %.1f | %.1f | %.1f | the syscall floor under the row above |\n",
	       t[0], t[n/2], sum/n);
	return 0;
}
