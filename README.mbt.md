# comemoon

Incremental computation through constrained memoization — a MoonBit port of
[`comemo`](https://github.com/typst/comemo) v0.5.1.

A memoized function caches its result keyed by (1) a hash of all non-tracked
arguments and (2) a *call sequence*: every method call made on `Tracked`
arguments during the computation, recorded as `(call, return-hash)` pairs.
A cache hit is taken only if every recorded call, replayed on the *current*
tracked value, produces the same return hash. Editing an unreferenced part of
tracked data keeps the cache valid — this is what makes fine-grained
incremental computation possible.

## Features

- **Fine-grained invalidation**: only *actually-read* tracked data
  invalidates. A function re-runs only when the data it touched has changed.
- **Mutable tracked calls** (`TrackedMut`): side effects recorded during
  computation are replayed on cache hit, with downgrade / reborrow /
  track_mut views.
- **Trait tracking**: `#comemo.track` on a trait generates a generic surface
  (`WorldTracked[T]` with `fn[T : World]` bounds) — the pattern used by
  Typst's `World` trait.
- **Multi-parameter memoization**: 1–6 tracked parameters (`Input2`..`Input6`
  / `memoize2`..`memoize6`), covering every arity used in Typst.
- **Validation accelerator**: per-instance call→return-hash cache gives O(1)
  revalidation.
- **Age-based eviction**: `evict(max_age)` prunes stale entries; recursion
  shares the per-function cache.
- **No proc macros**: `#comemo.track`-annotated types and traits are expanded
  by a build-time generator (`gen/gen.py`) wired through MoonBit's official
  `rule` / `dev_build` hooks.

## Quick start

Define a tracked type, annotate it, and mark the methods you want tracked:

```mbt nocheck
#comemo.track
pub struct Files {
  map : @hashmap.HashMap[String, String]
}

///|
pub fn Files::read(self : Files, path : String) -> String {
  self.map.get(path).unwrap_or("")
}

///|
pub fn Files::write(self : Files, path : String, text : String) -> Unit {
  self.map[path] = text
}
```

The generator (triggered by `moon check` / `moon test` via the `dev_build`
hook) emits a Call enum, hash impls, and a `FilesTracked` surface wrapper into
`comemo_gen.mbt`, which is committed to the repo. Then memoize a function over
the tracked value:

```mbt nocheck
fn eval(script : String, files : FilesTracked) -> Int {
  let cache : Cache[FilesCall, Int] = Cache::new()
  memoize(cache, Input::new(
    fn() { hash_string(script) },
    fn(rec : Recorder[FilesCall]) -> Recorder[FilesCall]? { files.t.attach(rec) },
    fn(c : FilesCall) -> UInt64 { /* replay a recorded call, return its hash */ },
    fn(_c : FilesCall) -> Unit { () },
    fn(prev : Recorder[FilesCall]?) -> Unit { files.t.detach(prev) },
  ), true, fn() {
    /* the computation; reads through files are tracked */
  })
}
```

The `.calc` dependency-graph demo in `cmd/main/` shows the full pattern:
editing an unreferenced file keeps the cache valid, so re-evaluation is O(1).

## Layout

- `lib/` — the runtime library (single package)
  - `hash.mbt` — MurmurHash64A hashing + Rust-style `Hash` encodings
  - `murmur3_hash64.mbt` — 64-bit MurmurHash64A (zero-allocation)
  - `tree.mbt` — `CallTree` trie + free-list arena
  - `constraint.mbt` — `CallSequence` (dedup) + `Constraint` (immutable/mutable)
  - `tracked.mbt` — `Tracked` / `TrackedMut` wrappers (Ref-based, MergedSink chaining)
  - `cache.mbt` — per-function `Cache` with age-based eviction
  - `memoize.mbt` — `memoize`/`memoize_pure` + `Input2`..`Input6`/`memoize2`..`memoize6`
  - `accelerate.mbt` — per-instance validation accelerator
  - `user_tracked.mbt` + `comemo_gen.mbt` — generator input / generated output
- `gen/gen.py` — `#comemo.track` code generator (structs + traits, wired via
  `rule`/`dev_build`)
- `bench/` — performance scenarios vs the Rust reference (`run_bench.sh`), run as tests
- `cmd/main/` — calc dependency-graph demo

## Testing

- 31 unit tests across the comemo behavioral contract (basic memoization,
  dependency graphs, eviction, trait tracking, mutable replay, determinism),
  green on both wasm and native targets.
- 7 performance scenarios (`lib/bench_wbtest.mbt`) run alongside the tests,
  compared against the Rust reference in `bench/run_bench.sh`.

## Docs

- `AGENTS.md` — repository guidelines

## License

This project is licensed under Apache-2.0.

It is a port of [`comemo`](https://github.com/typst/comemo), which is
dual-licensed MIT OR Apache-2.0. The ported code retains that dual licensing
for the parts derived from the original; see `refs/comemo/LICENSE-APACHE` and
`refs/comemo/LICENSE-MIT`. The reference implementation is vendored under
`refs/comemo/` (Apache-2.0 + MIT) and `refs/typst/` (Apache-2.0).
