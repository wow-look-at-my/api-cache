package main

import (
	"fmt"
	"runtime"
	"testing"
	"unsafe"
	"container/list"
)

// Measures the real heap cost of one metaEntry in the LRU cache against the
// 160-byte estimate, using the exact key shape (go-buildcache/v1 + 64 hex, 80
// bytes) and the ten attributes docs/hot-path-cpu.md lists for a typical entry.
func TestMetaEntryRealOverhead(t *testing.T) {
	attrs := [][2]string{
		{"outputid", "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"},
		{"compression", "zstd"},
		{"object-type", "package"},
		{"pkg", "github.com/wow-look-at-my/api-cache/internal/store"},
		{"src", "store.go"},
		{"module", "github.com/wow-look-at-my/api-cache"},
		{"go-version", "go1.26.8"},
		{"target", "linux/amd64"},
		{"toolchain-version", "1.26.8"},
		{"created", "2026-09-13T01:02:03Z"},
	}
	const n = 200_000
	keys := make([]string, n)
	for i := range keys {
		keys[i] = fmt.Sprintf("go-buildcache/v1%064x", i)
	}
	payload := 0
	for _, a := range attrs {
		payload += len(a[0]) + len(a[1])
	}
	payload += len(keys[0])

	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	c := newMetaCache(1 << 40)
	var estimate int64
	for i := range keys {
		kv := make([]kvPair, 0, len(attrs))
		for _, a := range attrs {
			kv = append(kv, kvPair{a[0], a[1]}) // attribute strings shared, as in the server (they come from xattr names/values per read, so a real server holds fresh copies; measured both ways below)
		}
		e := metaEntry{modNano: int64(i), size: int64(i), kv: kv}
		estimate += metaEntrySize(keys[i], e)
		c.Put(keys[i], e)
	}
	runtime.GC()
	runtime.ReadMemStats(&after)
	shared := int64(after.HeapAlloc-before.HeapAlloc) / n

	// Now with per-entry fresh copies of every attribute string, which is what
	// the server actually holds: getMetadata builds a new map per read.
	runtime.GC()
	runtime.ReadMemStats(&before)
	c2 := newMetaCache(1 << 40)
	for i := range keys {
		kv := make([]kvPair, 0, len(attrs))
		for _, a := range attrs {
			kv = append(kv, kvPair{string([]byte(a[0])), string([]byte(a[1]))})
		}
		c2.Put(keys[i], metaEntry{modNano: int64(i), size: int64(i), kv: kv})
	}
	runtime.GC()
	runtime.ReadMemStats(&after)
	fresh := int64(after.HeapAlloc-before.HeapAlloc) / n

	t.Logf("entries: %d", n)
	t.Logf("payload bytes per entry (key + attribute strings): %d", payload)
	t.Logf("sizeof: lruEntry=%d list.Element=%d metaEntry=%d kvPair=%d map bucket amortized ~%d",
		unsafe.Sizeof(lruEntry[string, metaEntry]{}), unsafe.Sizeof(list.Element{}), unsafe.Sizeof(metaEntry{}), unsafe.Sizeof(kvPair{}), 0)
	t.Logf("estimate (metaEntrySize) per entry: %d bytes", estimate/n)
	t.Logf("measured heap per entry, attribute strings shared:      %d bytes", shared)
	t.Logf("measured heap per entry, attribute strings fresh copies: %d bytes (the server's case)", fresh)
	t.Logf("real overhead beyond payload: %d bytes (fresh), %d bytes (shared)", fresh-int64(payload), shared-int64(payload))
	t.Logf("32 MiB default budget holds ~%d entries by the estimate, ~%d by the real cost", (32<<20)/(estimate/n), (32<<20)/fresh)
	_ = c
	_ = c2
}
