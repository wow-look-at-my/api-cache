#include <stdio.h>
#include <string.h>
#include <stdlib.h>
struct kv { char *k; long v; };
static int cmpkv(const void *a, const void *b) {
	const struct kv *x = a, *y = b;
	return strcmp(x->k, y->k);
}
long total(struct kv *a, int n) { long t = 0; for (int i = 0; i < n; i++) t += a[i].v; return t; }
int main(int argc, char **argv) {
	struct kv *a = calloc(argc, sizeof *a);
	for (int i = 1; i < argc; i++) { a[i-1].k = argv[i]; a[i-1].v = i; }
	qsort(a, argc-1, sizeof *a, cmpkv);
	printf("%ld\n", total(a, argc-1));
	free(a);
	return 0;
}
