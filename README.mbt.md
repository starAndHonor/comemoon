# comemoon

Incremental computation through constrained memoization — a MoonBit port of
[`comemo`](https://github.com/typst/comemo) v0.5.0.

A memoized function caches its result keyed by (1) a hash of all non-tracked
arguments and (2) a *call sequence*: every method call made on `Tracked`
arguments during the computation, recorded as `(call, return-hash)` pairs.
A cache hit is taken only if every recorded call, replayed on the *current*
tracked value, produces the same return hash. Editing an unreferenced part of
tracked data keeps the cache valid.

## Features

- Fine-grained invalidation: only *actually-read* tracked data invalidates.
- Mutable tracked calls replayed on cache hit (side effects restored).
- Per-instance validation accelerator (O(1) revalidation).
- Age-based eviction; recursion shares the per-function cache.
- No proc macros: `#comemo.track`-annotated types are expanded by a build-time
  generator (`gen/gen.py`) wired through MoonBit's `rule`/`dev_build` hooks.

## Quick start

```mbt nocheck
///|
#comemo.track
struct Files {
  map : @hashmap.HashMap[String, String]
}

///|
fn Files::read(self : Files, path : String) -> String {
  self.map.get(path).unwrap_or("")
}
```

`user_tracked.mbt` is expanded by the generator (via `moon test`/`moon check`,
which trigger `dev_build`) into a Call enum and a `FilesTracked` surface
wrapper. The generated `comemo_gen.mbt` is committed; downstream users build
against it directly without running the generator.

## Layout

- `lib/` — the runtime library (single package)
  - `siphash.mbt` — SipHash-1-3 128-bit (byte-identical to Rust comemo)
  - `hash.mbt` — Rust std `Hash` encodings + `RustHashable` trait
  - `tree.mbt` — `CallTree` trie + slab arena
  - `constraint.mbt` — `CallSequence` (dedup) + `Constraint` (immutable/mutable)
  - `tracked.mbt` — `Tracked` wrapper (closure recorder, MergedSink chaining)
  - `cache.mbt` — per-function `Cache` with age-based eviction
  - `memoize.mbt` — `memoize` entry (lookup/attach/insert)
  - `accelerate.mbt` — per-instance validation accelerator
  - `user_tracked.mbt` + `comemo_gen.mbt` — generator input / generated output
- `gen/gen.py` — `#comemo.track` code generator (wired via `rule`/`dev_build`)
- `bench/` — 5-scenario benchmark vs the Rust reference (`run_bench.sh`)
- `cmd/main/` — calc dependency graph demo

## Docs

- `AGENTS.md` — repository guidelines
- `PORTING-PLAN.md` — technical porting decisions (incl. no-proc-macro design)
- `MIGRATION-PLAN.md` — phase roadmap and test-contract mapping

## License

Apache-2.0. The reference implementation (`refs/comemo/`) is dual-licensed
MIT/Apache-2.0.
