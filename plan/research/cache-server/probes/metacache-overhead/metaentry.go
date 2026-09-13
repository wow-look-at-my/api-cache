// Copied verbatim from go-s3-server/metacache.go (the parts that define an
// entry's shape and size estimate) so the estimate can be checked against a
// measured heap.
package main

type kvPair struct{ k, v string }

type metaEntry struct {
	modNano int64
	size    int64
	kv      []kvPair
}

const metaEntryOverhead = 160

func metaEntrySize(key string, e metaEntry) int64 {
	n := int64(len(key) + metaEntryOverhead)
	for _, p := range e.kv {
		n += int64(len(p.k) + len(p.v) + 32)
	}
	return n
}

func newMetaCache(budget int64) *lruCache[string, metaEntry] {
	return newLRUCache(budget, fnv1a, metaEntrySize)
}

func main() {}
