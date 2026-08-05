# comemoon

Incremental computation through constrained memoization — a MoonBit port of
[`comemo`](https://github.com/typst/comemo) v0.5.1.

A memoized function caches its result keyed by (1) a hash of all non-tracked
arguments and (2) a *call sequence*: every method call made on `Tracked`
arguments during the computation, recorded as `(call, return-hash)` pairs.
A cache hit is taken only if every recorded call, replayed on the *current*
tracked value, produces the same return hash. Editing an unreferenced part of
tracked data keeps the cache valid.

## Features

- Fine-grained invalidation: only *actually-read* tracked data invalidates.
- Mutable tracked calls (`TrackedMut`) replayed on cache hit (side effects
  restored); downgrade/reborrow/track_mut views.
- Trait track: `#comemo.track` on a trait generates a generic surface
  (`WorldTracked[T]` with `fn[T : World]` bounds) — Typst's `World` pattern.
- Multi-parameter memoize: up to 5 tracked params (`Input5`/`memoize5`),
  matching Typst's `bundle_impl` (4 Tracked + 1 TrackedMut).
- Per-instance validation accelerator (O(1) revalidation).
- Age-based eviction; recursion shares the per-function cache.
- murmur3 128-bit hashing (performance-first; keys are in-process only).
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
  - `hash.mbt` — murmur3 128-bit + Rust-style `Hash` encodings (`RustHashable`)
  - `tree.mbt` — `CallTree` trie + free-list arena
  - `constraint.mbt` — `CallSequence` (dedup) + `Constraint` (immutable/mutable)
  - `tracked.mbt` — `Tracked` / `TrackedMut` wrappers (Ref-based, MergedSink chaining)
  - `cache.mbt` — per-function `Cache` with age-based eviction
  - `memoize.mbt` — `memoize`/`memoize_pure` + `Input2..5`/`memoize2..5`
  - `accelerate.mbt` — per-instance validation accelerator
  - `user_tracked.mbt` + `comemo_gen.mbt` — generator input / generated output
  - `test_types.mbt` / `gen_test.mbt` — tests incl. G1-G6 gap coverage
- `gen/gen.py` — `#comemo.track` code generator (structs + traits, wired via
  `rule`/`dev_build`)
- `bench/` — 7-scenario benchmark vs the Rust reference (`run_bench.sh`)
- `cmd/main/` — calc dependency graph demo

## Docs

- `AGENTS.md` — repository guidelines

## License

This project is licensed under Apache-2.0.

It is a port of [`comemo`](https://github.com/typst/comemo), which is
dual-licensed MIT OR Apache-2.0. The ported code retains that dual licensing
for the parts derived from the original; see `refs/comemo/LICENSE-APACHE` and
`refs/comemo/LICENSE-MIT`. The reference implementation is vendored under
`refs/comemo/` (Apache-2.0 + MIT) and `refs/typst/` (Apache-2.0).
