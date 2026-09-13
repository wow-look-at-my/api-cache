# startup syscall counts: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`
- commit: `9b08f713116e98c791d5c07099188657b1704fbd`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728781892
- go: go version go1.24.13 linux/amd64
- strace: strace -- version 6.8
- method: `strace -c -f <prog>`, which follows cloned threads

| binary | total syscalls | clone | rt_sigaction | mmap | openat |
|---|---|---|---|---|---|
| c-static | 17 |  |  |  |  |
| c-dyn | 35 |  |  | 8 | 2 |
| go-hello | 206 | 4 | 114 | 22 | 1 |
| go-imports | 203 | 4 | 114 | 22 | 1 |

An empty cell means the program makes that syscall zero times.

## full strace summaries

### c-static

```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
  0.00    0.000000           0         1           write
  0.00    0.000000           0         1           fstat
  0.00    0.000000           0         1           mprotect
  0.00    0.000000           0         5           brk
  0.00    0.000000           0         1         1 ioctl
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         1           readlinkat
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         1           prlimit64
  0.00    0.000000           0         1           getrandom
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ----------------
100.00    0.000000           0        17         1 total
```

### c-dyn

```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
  0.00    0.000000           0         1           read
  0.00    0.000000           0         1           write
  0.00    0.000000           0         2           close
  0.00    0.000000           0         3           fstat
  0.00    0.000000           0         8           mmap
  0.00    0.000000           0         3           mprotect
  0.00    0.000000           0         1           munmap
  0.00    0.000000           0         3           brk
  0.00    0.000000           0         1         1 ioctl
  0.00    0.000000           0         2           pread64
  0.00    0.000000           0         1         1 access
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         2           openat
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         1           prlimit64
  0.00    0.000000           0         1           getrandom
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ----------------
100.00    0.000000           0        35         2 total
```

### go-hello

```
strace: Process 4585 attached
strace: Process 4586 attached
strace: Process 4587 attached
strace: Process 4588 attached
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ------------------
 32.34    0.001011         144         7           nanosleep
 29.56    0.000924          92        10         2 futex
 11.93    0.000373          26        14           rt_sigprocmask
  7.39    0.000231          57         4           clone
  6.30    0.000197          19        10           sigaltstack
  3.49    0.000109          12         9           gettid
  3.45    0.000108         108         1           prlimit64
  2.66    0.000083          13         6           fcntl
  2.34    0.000073           3        22           mmap
  0.54    0.000017          17         1           write
  0.00    0.000000           0         1           read
  0.00    0.000000           0         1           close
  0.00    0.000000           0       114           rt_sigaction
  0.00    0.000000           0         2           madvise
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
  0.00    0.000000           0         1           sched_getaffinity
  0.00    0.000000           0         1           openat
------ ----------- ----------- --------- --------- ------------------
100.00    0.003126          15       206         2 total
```

### go-imports

```
strace: Process 4610 attached
strace: Process 4611 attached
strace: Process 4612 attached
strace: Process 4613 attached
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ------------------
 30.62    0.001530         191         8           nanosleep
 20.95    0.001047         174         6           futex
 18.21    0.000910           7       114           rt_sigaction
  7.72    0.000386          96         4           clone
  6.44    0.000322          14        22           mmap
  6.42    0.000321          22        14           rt_sigprocmask
  3.62    0.000181          18        10           sigaltstack
  3.10    0.000155          17         9           gettid
  0.86    0.000043           7         6           fcntl
  0.46    0.000023          11         2           madvise
  0.44    0.000022          22         1           openat
  0.36    0.000018          18         1           prlimit64
  0.26    0.000013          13         1           write
  0.20    0.000010          10         1           read
  0.16    0.000008           8         1           close
  0.16    0.000008           8         1           sched_getaffinity
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         1           arch_prctl
------ ----------- ----------- --------- --------- ------------------
100.00    0.004997          24       203           total
```

