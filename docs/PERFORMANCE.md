# Performance plan

Omaloom optimizes user-visible transition latency, not implementation-language benchmarks. Measurements are taken on the development Omarchy system and are directional rather than hardware-independent guarantees.

## v0.1.3 baseline

| Operation | Median |
| --- | ---: |
| Empty `/usr/bin/python3` startup | 6.8 ms |
| Typical Python helper | 27–55 ms |
| Recorder status | 82.6 ms |
| `hyprctl monitors -j` | 2.1 ms |
| Fixed post-countdown waits | 1,100 ms |

The baseline microphone meter started a fresh FFmpeg process for each sample. Its first event arrived in about 450–580 ms and it emitted about five events in 2.5 seconds.

These results show that process orchestration and deliberate waits dominate Python interpreter startup.

## Phase 1 fast path

The first optimization pass:

- keeps one FFmpeg meter process alive while setup is open;
- prepares audio arguments and secure output/state reservations before countdown;
- reduces popup unmap delay from 300 ms to 120 ms;
- replaces the unconditional 800 ms recorder survival delay with output/process readiness capped at 200 ms;
- reduces the pre-launch popup delay from 200 ms to 100 ms; and
- exposes opt-in `OMALOOM_PROFILE=true` monotonic transition markers in the private recorder log.

The persistent meter's first event arrives in about 120 ms and it emits about 26 events in 2.5 seconds on the same system. The expected fixed countdown-to-confirmation budget falls from at least 1,100 ms to 120–320 ms, pending end-to-end capture QA.

## Native-backend decision gate

Do not choose a native language based only on helper startup time. Reconsider a persistent backend after Phase 1 profiling if critical interactions remain visibly delayed or if planned features require long-lived application state, direct PipeWire integration, indexing, or background job management.

A persistent Python JSON-lines prototype is the lowest-cost way to validate the IPC and ownership model. If native deployment is then justified, Rust is preferred for an independent backend. C++ is preferable only if the backend intentionally becomes an in-process Qt component; that coupling is not currently desired.
