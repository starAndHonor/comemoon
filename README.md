<div align="center">

# comemoon

**Incremental computation through constrained memoization — a MoonBit port of [comemo](https://github.com/typst/comemo).**

受约束记忆化的增量计算库 —— 把 Rust 生态中 typst 使用的 comemo 移植到 MoonBit。

[![CI](https://github.com/starAndHonor/comemoon/actions/workflows/ci.yml/badge.svg)](https://github.com/starAndHonor/comemoon/actions/workflows/ci.yml)
[![mooncakes.io](https://img.shields.io/badge/mooncakes-0.1.1-blue)](https://mooncakes.io/docs/starAndHonor/comemoon)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-31%20passed-brightgreen)](#testing)

</div>

---

## Why comemoon?

A memoized function normally caches on its *argument values*. Change one byte of
input and everything recomputes — even if the changed part was never read.

**comemoon caches on what the computation actually *did*.** A memoized result is
keyed by a hash of the plain arguments *plus* a recorded sequence of every
method call made on tracked data, with its return hash. On the next call, those
recorded calls are replayed against the *current* tracked value: if all return
hashes still match, the cached result is valid — even when other parts of the
input changed.

Edit one word in a document, and only the parts that *read* that word
recompute. This is how [typst](https://typst.app) gets sub-millisecond
incremental recompilation, now available to MoonBit.

## Features

- **Fine-grained invalidation** — only actually-read tracked data invalidates a cache entry
- **Mutable tracked calls** (`TrackedMut`) — side effects recorded and replayed on cache hit, with downgrade / reborrow / track_mut views
- **Trait tracking** — `#comemo.track` on a trait generates a generic surface (`WorldTracked[T]` with `fn[T : World]` bounds)
- **Multi-parameter memoization** — `memoize2` … `memoize6` for up to 6 tracked parameters
- **Validation accelerator** — per-instance call→return-hash map, O(1) revalidation
- **Age-based eviction** — `evict(max_age)` with age reset on hit
- **Recursion** — recursive memoized functions share the same per-function cache
- **No proc macros** — `#comemo.track` is expanded by a build-time generator (`gen/gen.py`) via MoonBit's official `rule` / `dev_build` hooks; generated code is committed, so downstream users never run it

## Installation

```bash
moon add starAndHonor/comemoon
```

## Quick start

Annotate the type you want to track:

```mbt nocheck
#comemo.track
pub struct Files {
  map : Map[String, String]
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

The generator (triggered automatically by `moon check` / `moon test` via the
`dev_build` hook) emits a `FilesCall` enum, hash impls, and a `FilesTracked`
surface wrapper into `comemo_gen.mbt` (committed). Then memoize over the
tracked value:

```mbt nocheck
fn eval(script : String, files : FilesTracked) -> Int {
  let cache : Cache[FilesCall, Int] = Cache::new()
  memoize(cache, input, true, fn() {
    // the computation; reads through `files` are tracked
  })
}
```

A cache hit is taken only when every recorded call, replayed on the current
`Files`, still produces the recorded return hash. Writes to paths the script
never read keep the cache valid.

## Demo

The `cmd/main/` package ports comemo's `calc.rs` example: a dependency graph
of spreadsheet-like cells, where editing one cell only re-evaluates its
dependents.

```bash
moon run cmd/main
```

## API overview

| API | Purpose |
|---|---|
| `memoize` … `memoize6` | Memoize a function with 0–6 tracked parameters |
| `Cache::new` / `CacheEntry` | Per-function cache holding output + recorded mutable calls + age |
| `Tracked[T]` / `TrackedMut[T]` | Read-only / mutable tracked wrappers |
| `evict(max_age)` | Age-based eviction; resets validation accelerators |
| `Input::new` | Combine plain-hash args and tracked args into a memoization key |
| `last_was_hit()` | Test oracle: did the last memoized call hit the cache? |

## How it works

```
memoized fn call
      │
      ▼
per-fn Cache (CallTree)      key = murmur3-128(receiver + plain args)
      │
      ▼
CallTree lookup: walk trie; at each inner node replay the recorded call on the
live tracked value; continue only if the replayed return-hash == edge label
      │
      ├─ leaf → HIT:  replay recorded mutable calls (side effects),
      │               clone output, reset age
      └─ miss → attach a Constraint sink to tracked args, run fn,
                insert (immutable calls → trie path, mutable calls → entry)
```

Semantics preserved from the Rust reference: order-independent validation of
the immutable call set, mutable-call replay on hit, `enabled` bypass,
age-based eviction, and debug panics for non-deterministic memoized functions
and impure tracked methods.

## Differences from Rust comemo

- **No proc macros** — instead of `#[memoize]` / `#[track]`, you annotate types and traits with `#comemo.track` and a build-time generator emits the boilerplate.
- **Generic trait tracking** — tracked traits produce a generic surface (`WorldTracked[T]`) instead of `dyn Track` trait objects, so tracked APIs stay statically typed.
- **Single-threaded** — no locks or cross-thread sharing; one cache belongs to one thread.

## Testing

31 tests covering the full comemo behavioral contract — basic memoization,
dependency graphs, eviction, trait tracking, mutable replay, determinism and
panic behaviors — green on both targets:

```bash
moon test                    # wasm
moon test --target native    # native
```

CI additionally runs `moon check`, `moon fmt --check`, and a generator
consistency check (regenerated output must match the committed file).

## Roadmap

- [ ] Multi-target codegen polish (native performance tuning)
- [ ] Extended arity beyond 6 tracked parameters
- [ ] Benchmark suite against the Rust reference (speed + memory)
- [ ] More examples: incremental build tool, reactive data pipeline

## Contributing

Issues and pull requests are welcome. Please run `moon fmt`, `moon check`,
and both test targets before submitting.

## License

Apache-2.0. comemoon is a port of [comemo](https://github.com/typst/comemo)
(MIT OR Apache-2.0) by the typst authors; derived code retains that dual
licensing — see `refs/comemo/LICENSE-APACHE` and `refs/comemo/LICENSE-MIT`.
The reference implementation is vendored under `refs/comemo/`.

## Acknowledgements

- [comemo](https://github.com/typst/comemo) — the original implementation and behavioral contract
- [typst](https://typst.app) — the project comemo was built for
- [MoonBit](https://www.moonbitlang.com) — the language and toolchain
