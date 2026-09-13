/*
 * binpazer -- a flexible, block-based binary file format.
 * Reference C implementation. See SPEC.md for the format.
 *
 * No file IO and no mmap: the caller injects all IO through callbacks. The
 * library only serializes/deserializes the format through those callbacks.
 *
 * Single-header style: define BINPAZER_IMPLEMENTATION in exactly one .c file
 * before including this header, or compile binpazer.c.
 */
#ifndef BINPAZER_H
#define BINPAZER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BINPAZER_MAGIC          "binpazer"   /* 8 bytes */
#define BINPAZER_VERSION_MAJOR  1
#define BINPAZER_VERSION_MINOR  0
#define BINPAZER_FILE_LENGTH_UNKNOWN  0xFFFFFFFFFFFFFFFFULL

/* Block type ids: 0 and 65535 are invalid; user types ascend from 1;
 * predefined types descend from 65534. */
#define BINPAZER_TYPE_INVALID          0
#define BINPAZER_TYPE_INVALID_MAX      65535
#define BINPAZER_TYPE_BLOCK_TYPE_TABLE 65534
#define BINPAZER_TYPE_BLOCK_INDEX      65533
#define BINPAZER_TYPE_WRITER_INFO      65532
#define BINPAZER_TYPE_PADDING          65531
#define BINPAZER_TYPE_GROUP            65530

/* large_mode (flag bit 4): `length` counts units of this many bytes (one page),
 * raising the per-block cap from 4 GiB to (2^32-1)*4096 (~16 TiB). */
#define BINPAZER_LARGE_UNIT 4096

/* Block flag bits (the 16-bit `flags` field). Bits 5.. are reserved, must be 0,
 * and readers MUST ignore ones they do not know. */
enum {
    /* An unknown block type here is fatal: stop, the file needs a feature you
     * lack. Clear (ancillary) means an unknown block is safe to skip. */
    BINPAZER_FLAG_CRITICAL     = 1u << 0,
    /* An editor that does not understand this block may copy it verbatim when
     * rewriting the file. Clear means drop it instead -- what the Block Index
     * does, since its offsets do not survive a rewrite. */
    BINPAZER_FLAG_SAFE_TO_COPY = 1u << 1,
    /* The stored payload is a Compression Envelope, not the block's logical
     * bytes; `length` still counts the STORED bytes. */
    BINPAZER_FLAG_COMPRESSED   = 1u << 2,
    /* A 4-byte CRC-32C over [block start .. end of payload] follows the
     * payload, before the alignment padding. It covers the bytes on disk, so
     * for a compressed block that is the envelope, before any codec runs. */
    BINPAZER_FLAG_HAS_CRC      = 1u << 3,
    /* `length` counts 4096-byte units instead of bytes, raising the per-block
     * cap from 4 GiB to ~16 TiB at 4096-byte granularity. */
    BINPAZER_FLAG_LARGE_MODE   = 1u << 4
};

/* Minor version a file must declare once it holds a compressed block. */
#define BINPAZER_VERSION_MINOR_COMPRESSION 1

/* Codec ids from SPEC.md's registry. This library carries no codec code: it
 * reads and writes the envelope, and the caller supplies the codec bytes. That
 * is what keeps it dependency-free -- BINPAZER_CODEC_STORED needs no codec at
 * all, so a well-formed compressed block is always writable from here. */
enum {
    BINPAZER_CODEC_INVALID = 0,
    BINPAZER_CODEC_STORED  = 1,     /* identity: codec bytes are the payload */
    BINPAZER_CODEC_DEFLATE = 2,     /* raw DEFLATE (RFC 1951) */
    BINPAZER_CODEC_ZSTD    = 3,     /* zstd (RFC 8878) */
    BINPAZER_CODEC_LZ4     = 4,     /* LZ4 frame format */
    BINPAZER_CODEC_BY_GUID = 65535  /* codec identified by codec_guid */
};

/* Compression Envelope header sizes: fixed part, and with the GUID escape. */
#define BINPAZER_ENVELOPE_FIXED_SIZE 16
#define BINPAZER_ENVELOPE_GUID_SIZE  32

typedef struct { uint8_t bytes[16]; } binpazer_guid;

/* The well-known GUID of the Block Type Table (62696e70-617a-6572-0000-...0001). */
extern const binpazer_guid BINPAZER_GUID_BLOCK_TYPE_TABLE;

/*
 * IO callbacks (fread/fwrite-style):
 *   read  returns the number of bytes read   (< n means EOF/short)
 *   write returns the number of bytes written (< n means error)
 *   seek  is optional (may be NULL); absolute offset from the start; 0 == ok.
 * The opaque `ctx` is passed back to each callback.
 */
typedef size_t (*binpazer_read_fn)(void *ctx, void *buf, size_t n);
typedef size_t (*binpazer_write_fn)(void *ctx, const void *buf, size_t n);
typedef int    (*binpazer_seek_fn)(void *ctx, uint64_t offset);

typedef enum {
    BINPAZER_OK        = 0,
    BINPAZER_END       = 1,   /* reader reached the last block */
    BINPAZER_ERR_IO    = -1,  /* a callback failed */
    BINPAZER_ERR_MAGIC = -2,  /* bad magic or signature */
    BINPAZER_ERR_VERSION = -3,/* unsupported major version */
    BINPAZER_ERR_FORMAT = -4, /* structurally invalid */
    BINPAZER_ERR_RANGE  = -5, /* value out of range (e.g. large_mode misuse) */
    BINPAZER_ERR_CRC    = -6, /* CRC mismatch */
    BINPAZER_ERR_CAPACITY = -7, /* a caller-supplied buffer is too small */
    BINPAZER_ERR_NOSEEK   = -8  /* operation requires a seek callback */
} binpazer_status;

/* ---- Writing ---- */

typedef struct {
    binpazer_write_fn write;
    binpazer_seek_fn  seek;   /* may be NULL */
    void             *ctx;
    uint64_t          offset; /* bytes written so far; == the next block's offset */
    int               err;    /* sticky error (binpazer_status) */
    uint64_t          index_offset; /* offset of the Block Index block, once written */
    int               wrote_index;
    int               used_compression; /* a compressed block was written: file is 1.1 */
    uint16_t          version_minor;    /* as declared in the header at begin */
} binpazer_writer;

/* One block-type-table entry supplied by the caller. Use user ids (1, 2, ...);
 * do not use predefined ids (65531..65534). The Block Type Table's own entry
 * (65534) is added automatically. */
typedef struct {
    uint16_t       type_id;
    binpazer_guid  guid;
    const char    *name;   /* may be NULL */
} binpazer_type_def;

/* Writes the file header and the Block Type Table (the required first block). */
binpazer_status binpazer_writer_begin(
    binpazer_writer *w,
    binpazer_write_fn write, binpazer_seek_fn seek, void *ctx,
    const binpazer_guid *writer_guid, const char *writer_name,
    const binpazer_type_def *defs, size_t ndefs);

/* binpazer_writer_begin declaring a specific minor version in the header
 * instead of BINPAZER_VERSION_MINOR. The one reason to use it: a compressed
 * block normally raises the version by back-patching the header at end, which
 * needs a seek callback -- declare BINPAZER_VERSION_MINOR_COMPRESSION here and
 * a STREAMING writer (no seek) can write compressed blocks too. Declaring a
 * version whose features the file does not use is legal but pointless: it just
 * turns readers away. */
binpazer_status binpazer_writer_begin_version(
    binpazer_writer *w,
    binpazer_write_fn write, binpazer_seek_fn seek, void *ctx,
    const binpazer_guid *writer_guid, const char *writer_name,
    const binpazer_type_def *defs, size_t ndefs, uint16_t version_minor);

/* Writes one block. `payload` may be NULL iff payload_len == 0.
 * If `flags` has LARGE_MODE, payload_len is the byte length and must be a
 * multiple of BINPAZER_LARGE_UNIT (4096); the length field stores the unit count. */
binpazer_status binpazer_writer_block(
    binpazer_writer *w, uint16_t type_id, uint16_t flags,
    const void *payload, uint64_t payload_len);

/* ---- Compression (SPEC.md "Compression", 1.1) ---- */

/* A block's Compression Envelope: what codec produced the stored bytes, and
 * how many bytes they decode to. */
typedef struct {
    uint16_t      codec_id;            /* BINPAZER_CODEC_*; 0 is invalid */
    binpazer_guid codec_guid;          /* only when codec_id == BY_GUID */
    uint64_t      uncompressed_length; /* authoritative decoded size */
    uint64_t      stored_length;       /* codec bytes, i.e. payload - header */
    uint32_t      header_size;         /* FIXED_SIZE, or GUID_SIZE for BY_GUID */
} binpazer_compression;

/* Writes one block whose payload is a Compression Envelope wrapping
 * `stored`/`stored_len` -- bytes the CALLER has already encoded with the named
 * codec (for BINPAZER_CODEC_STORED they are the payload itself). The
 * BINPAZER_FLAG_COMPRESSED flag is added to `flags`. `codec_guid` is used only
 * when codec_id is BINPAZER_CODEC_BY_GUID and may otherwise be NULL.
 *
 * A compressed block makes the file 1.1, and the header was already written,
 * so this requires a seek callback to back-patch version_minor in
 * binpazer_writer_end; without one it returns BINPAZER_ERR_NOSEEK. */
binpazer_status binpazer_writer_block_compressed(
    binpazer_writer *w, uint16_t type_id, uint16_t flags,
    uint16_t codec_id, const binpazer_guid *codec_guid,
    const void *stored, uint64_t stored_len, uint64_t uncompressed_len);

/* Parses a Compression Envelope from the front of a payload the caller has
 * already read (the library does no IO). `payload_len` is the block's whole
 * stored payload length. Returns BINPAZER_ERR_FORMAT for an invalid codec id,
 * a set reserved field, or a payload too short to hold the header. The codec
 * bytes are at (const uint8_t *)payload + out->header_size. */
binpazer_status binpazer_compression_parse(
    const void *payload, uint64_t payload_len, binpazer_compression *out);

/* Finishes the file. Patches file_length when a seek callback is available;
 * otherwise file_length stays the streaming sentinel. When a compressed block
 * was written, version_minor is patched to 1.1 at the same time. */
binpazer_status binpazer_writer_end(binpazer_writer *w);

/* ---- Reading ---- */

typedef struct {
    uint16_t       type_id;
    binpazer_guid  guid;
} binpazer_type_entry;

typedef struct {
    binpazer_read_fn read;
    binpazer_seek_fn seek;   /* may be NULL */
    void            *ctx;
    uint64_t         offset;
    int              err;
    uint16_t         version_major, version_minor;
    binpazer_guid    writer_guid;
    uint64_t         file_length;        /* sentinel if unknown */
    uint64_t         first_block_offset;
    int              has_index;          /* a Block Index was located via the footer */
    uint64_t         index_offset;       /* offset of the Block Index block */
    uint64_t         blocks_end;         /* end of the block stream (excludes a trailing footer) */
} binpazer_reader;

typedef struct {
    uint16_t      type_id;
    uint16_t      flags;
    uint64_t      payload_len;     /* in bytes, already decoded from large_mode */
    binpazer_guid guid;            /* resolved from the type table (zero if unknown) */
    int           known;           /* 1 if type_id was found in the table */
    uint64_t      payload_offset;
} binpazer_block;

/* Reads and validates the file header and the Block Type Table. The table is
 * copied into `entries`; `*entries_count` receives the number stored. If
 * `entries` is non-NULL and the table holds more than `entries_cap` entries,
 * BINPAZER_ERR_CAPACITY is returned (nothing is stored) and `*entries_count`
 * receives the required count so the caller can retry with a bigger buffer.
 * Passing `entries` == NULL opts out of the table entirely.
 * `writer_name_buf` (if non-NULL) receives the writer name, truncated to fit
 * and always NUL-terminated. */
binpazer_status binpazer_reader_begin(
    binpazer_reader *r,
    binpazer_read_fn read, binpazer_seek_fn seek, void *ctx,
    char *writer_name_buf, size_t writer_name_cap,
    binpazer_type_entry *entries, size_t entries_cap, size_t *entries_count);

/* Reads the next block header, resolving its GUID against `entries`.
 * Returns BINPAZER_END after the last block. Does not read the payload. */
binpazer_status binpazer_reader_next(
    binpazer_reader *r,
    const binpazer_type_entry *entries, size_t entries_count,
    binpazer_block *blk);

/* Reads the current block's payload into `buf` (verifying the CRC if present),
 * then advances past it. `buf` must hold at least blk->payload_len bytes. */
binpazer_status binpazer_reader_read_payload(
    binpazer_reader *r, const binpazer_block *blk, void *buf, size_t buf_cap);

/* Skips the current block's payload (and CRC) and advances to the next block. */
binpazer_status binpazer_reader_skip_payload(
    binpazer_reader *r, const binpazer_block *blk);

/* Receives one chunk of a streamed payload. Returning anything but
 * BINPAZER_OK aborts the stream with that status. */
typedef binpazer_status (*binpazer_sink_fn)(void *ctx, const void *buf, size_t n);

/* Streams the current block's payload through `sink` in pieces of at most
 * `scratch_cap` bytes, verifying the CRC as it goes, then advances past the
 * block. Peak memory is the scratch buffer, NOT the payload -- which is how a
 * caller reads a payload bigger than memory (large_mode blocks reach ~16 TiB).
 * Use binpazer_reader_read_payload when the whole payload fits and a single
 * buffer is simpler. A CRC failure is reported only after the last chunk has
 * been handed over, since it cannot be known before then. */
binpazer_status binpazer_reader_stream_payload(
    binpazer_reader *r, const binpazer_block *blk,
    void *scratch, size_t scratch_cap,
    binpazer_sink_fn sink, void *sink_ctx);

/* ---- Group blocks (nesting, predefined type 65530) ---- */

/* One nested block inside a Group block's payload. `payload` points INTO the
 * caller's buffer -- nothing is copied, so it is valid as long as that buffer
 * is. */
typedef struct {
    uint16_t       type_id;
    uint16_t       flags;
    uint64_t       offset;       /* of the child's 8-byte header, relative to the payload */
    const uint8_t *payload;
    uint64_t       payload_len;
    int            crc_ok;       /* 0 only when has_crc is set and the stored CRC mismatches */
} binpazer_group_child;

/* Parses a Group block's payload -- nested blocks laid out exactly like
 * top-level ones -- from a buffer the caller has already read. Children are
 * written to `out` (up to `cap`) and `*count` receives the TOTAL child count,
 * so BINPAZER_ERR_CAPACITY means "call again with a buffer this big". A
 * structural error returns BINPAZER_ERR_FORMAT with the children parsed before
 * it still filled in, so a caller can render the intact prefix of a damaged
 * group. A child's CRC is verified into crc_ok without failing the parse.
 * Child type ids resolve against the same file-global Block Type Table as
 * top-level blocks; that resolution is left to the caller, which has it. */
binpazer_status binpazer_group_parse(
    const void *payload, uint64_t payload_len,
    binpazer_group_child *out, size_t cap, size_t *count);

/* ---- Block Index (optional, predefined type 65533) ---- */

typedef struct {
    uint16_t type_id;
    uint64_t offset;   /* absolute file offset of the block's 8-byte header */
} binpazer_index_entry;

/* Writes a Block Index block from `entries`. Call after the indexed blocks are
 * written; capture each block's offset by reading `writer.offset` immediately
 * before writing it. binpazer_writer_end then emits the footer that locates it. */
binpazer_status binpazer_writer_index(
    binpazer_writer *w, const binpazer_index_entry *entries, size_t n);

/* Finds blocks by type id, using the Block Index when present (seeking straight
 * to it) and otherwise walking the file. Requires a seek callback. Fills `out`
 * with up to `cap` matches; `*count` receives the total match count (which may
 * exceed `cap`, in which case BINPAZER_ERR_CAPACITY is returned). The reader's
 * position is preserved. */
binpazer_status binpazer_reader_find(
    binpazer_reader *r, uint16_t type_id,
    binpazer_index_entry *out, size_t cap, size_t *count);

/* Seeks to a block at `offset` (e.g. from binpazer_reader_find) and reads its
 * header into `blk`, resolving its GUID against `entries`. Requires a seek
 * callback. Afterwards, binpazer_reader_read_payload reads that block. */
binpazer_status binpazer_reader_at(
    binpazer_reader *r, const binpazer_type_entry *entries, size_t entries_count,
    uint64_t offset, binpazer_block *blk);

/* ---- GUIDs ---- */

/* Bytes needed for a canonical GUID string, including the NUL. */
#define BINPAZER_GUID_STRING_SIZE 37

/* Formats `g` as a canonical UUID (8-4-4-4-12, lowercase hex) into `buf`,
 * NUL-terminated. `cap` must be at least BINPAZER_GUID_STRING_SIZE. */
binpazer_status binpazer_guid_format(const binpazer_guid *g, char *buf, size_t cap);

/* Parses a canonical UUID string into `out`. Hyphens are optional and may sit
 * anywhere; exactly 32 hex digits must be present. */
binpazer_status binpazer_guid_parse(const char *s, binpazer_guid *out);

/* CRC-32C (Castagnoli), the algorithm used by the has_crc flag. Call with
 * crc = binpazer_crc32c(0, NULL, 0) to start, feed chunks, use the result. */
uint32_t binpazer_crc32c(uint32_t crc, const void *data, size_t n);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* BINPAZER_H */
