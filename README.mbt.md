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

- **Fine-grained invalidation**: only *actually-read* tracked data invalidates.
- **Mutable tracked calls** (`TrackedMut`): side effects replayed on cache hit,
  with downgrade / reborrow / track_mut views.
- **Trait tracking**: `#comemo.track` on a trait generates a generic surface
  (`WorldTracked[T]` with `fn[T : World]` bounds).
- **Multi-parameter memoization**: 1–6 tracked parameters (`memoize2`..`memoize6`).
- **Validation accelerator**: per-instance call-to-return-hash cache, O(1)
  revalidation.
- **Age-based eviction**; recursion shares the per-function cache.
- **No proc macros**: `#comemo.track` types and traits are expanded by a
  build-time generator (`gen/gen.py`) via MoonBit's `rule` / `dev_build` hooks.

## Quick start

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

The generator (triggered by `moon check` / `moon test`) emits a Call enum,
hash impls, and a `FilesTracked` surface wrapper into `comemo_gen.mbt`
(committed). Then memoize over the tracked value:

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

The `.calc` dependency-graph demo in `cmd/main/` shows the full pattern.

## Layout

- `lib/` — runtime library: `hash.mbt` (MurmurHash64A), `tree.mbt`
  (CallTree), `constraint.mbt`, `tracked.mbt` (`Tracked`/`TrackedMut`),
  `cache.mbt`, `memoize.mbt` (`memoize`..`memoize6`), `accelerate.mbt`,
  `user_tracked.mbt` + `comemo_gen.mbt` (generator input / output)
- `gen/gen.py` — `#comemo.track` code generator (structs + traits)
- `cmd/main/` — calc dependency-graph demo

## Testing

31 unit tests across the comemo behavioral contract (basic memoization,
dependency graphs, eviction, trait tracking, mutable replay, determinism),
green on both wasm and native targets.

## License

Apache-2.0. A port of [`comemo`](https://github.com/typst/comemo)
(MIT OR Apache-2.0); derived code retains that dual licensing, see
`refs/comemo/LICENSE-APACHE` and `refs/comemo/LICENSE-MIT`. The reference
implementation is vendored under `refs/comemo/` and `refs/typst/`.
