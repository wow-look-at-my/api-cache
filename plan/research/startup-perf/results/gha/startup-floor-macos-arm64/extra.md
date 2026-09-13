
## binary sizes

| binary | bytes |
|---|---|
| c-dyn | 33480 |
| cpp-dyn | 35912 |
| go-hello-nocgo | 2005170 |
| go-hello-cgo | 2005170 |
| go-hello-sw | 1335634 |
| go-imports | 5017618 |
| rust-hello | 469160 |

> **No static rows on macOS, by platform rule rather than by failure.**
> Apple does not support statically linking libSystem (no crt1.o is
> shipped for it and the ABI is the dylib), and clang on macOS links
> libc++ dynamically. The static targets are therefore not attempted
> here. Every target this platform DOES support was built and timed;
> a failure in any of them fails the job.
