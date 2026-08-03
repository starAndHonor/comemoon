# Repository Guidelines

## Project Overview

**comemoon** is a MoonBit rewrite of [`comemo`](https://github.com/typst/comemo) v0.5.0 — an incremental-computation library based on *constrained memoization*. Goal: match comemo's semantics with better speed and lower memory usage (MoonBit compiles to native/WASM with no GC overhead on the hot path).

The Rust reference implementation lives at `refs/comemo/` (Apache-2.0 + MIT dual licensed) and is the **behavioral contract** for this project. The MoonBit side is currently a bare `moon new` scaffold — no library code exists yet.

**What comemo does:** a memoized function caches its result keyed by (1) a 128-bit hash of all non-tracked arguments and (2) a *call sequence* — every method call made on `Tracked` arguments during the computation, recorded as `(call, return-hash)` pairs. A cache hit is taken only if every recorded call, replayed on the *current* tracked value, produces the same return hash. This gives fine-grained invalidation: editing an unreferenced part of tracked data keeps the cache valid (see `refs/comemo/examples/calc.rs`).

## Architecture & Data Flow

Two-layer design from the reference implementation:

```
memoized fn call
      │
      ▼
per-fn Cache (RwLock<CallTree>)
      │  key = SipHash128(receiver + non-tracked args)
      ▼
CallTree lookup: walk trie; at each inner node replay recorded call on live
Tracked value (Input::call oracle, accelerated by per-instance map); continue
only if replayed return-hash == edge label
      │
      ├─ leaf reached → HIT: replay recorded mutable calls (side effects),
      │                 clone output, reset age
      └─ no leaf → MISS: attach Constraint sink to Tracked args (chain via
                       MergedSink through nested memoized calls), run fn,
                       insert (immutable calls → trie path; mutable calls →
                       stored in CacheEntry)
```

Core components (Rust names — the MoonBit rewrite must provide equivalents):

| Rust module | Role |
|---|---|
| `memoize.rs` | `memoize()` entry + per-fn `Cache`/`CacheEntry` (output, mutable calls, age) |
| `track.rs` | `Track`/`Sink`/`Call`/`Surfaces` traits, `Tracked<'a,T,C>` / `TrackedMut` wrappers |
| `tree.rs` | `CallTree` trie: slab-based inner/leaf nodes, `FxHashMap` edges keyed by `(inner_id, ret_hash)` |
| `input.rs` | `Input` trait unifying plain-hash args and tracked args; `Multi` tuple wrapper (arities 0–12) |
| `constraint.rs` | `Constraint` sink recording `(call, ret)`; `CallSequence` dedup structure |
| `hash.rs` | `SipHasher13` 128-bit hashing (all keys, call hashes, return hashes) |
| `accelerate.rs` | Per-`Tracked`-instance `(call_hash → ret_hash)` map → O(1) validation, avoids re-running tracked methods |

**Key semantics that MUST be preserved in the rewrite:**
- Cache hit requires *order-independent* validation of the immutable call set: replayed calls must match recorded `(call, ret-hash)` pairs, regardless of recording order.
- `TrackedMut` mutable calls are recorded and **replayed on hit** (side effects), with no return value.
- `enabled` flag bypass (skip cache entirely when disabled).
- Age-based eviction (`evict(max_age)` clears entries whose age exceeds the limit; ages reset on hit; evict also invalidates all accelerators).
- Panic behaviors: non-deterministic memoized fn (recorded call missing from new sequence) panics in debug; impure tracked fn (same call hash, different return) panics in debug.
- Recursion works: recursive `#[memoize]` fns hit the same per-fn cache.

## Key Directories

| Path | Purpose |
|---|---|
| `refs/comemo/` | Rust reference implementation (contract source). Read before writing MoonBit code. |
| `refs/comemo/src/` | Rust library (~1600 lines across 9 files). |
| `refs/comemo/macros/` | Rust proc-macro crate (`#[memoize]`, `#[track]` codegen) — informs what MoonBit must emulate. |
| `refs/comemo/tests/tests.rs` | 17 `#[test]` + 2 quickcheck properties — the behavioral test contract to port. |
| `refs/comemo/examples/` | `basic.rs` (plain memoization), `calc.rs` (tracked dependency graph). |
| `NovaForge-Output-comemo/` | Typst study notes on comemo internals (5 chapters + appendix) — useful when porting. |
| `PORTING-PLAN.md` | 技术方案:无宏 codegen 决策、运行时模块设计、生成器架构。 |
| `MIGRATION-PLAN.md` | 总体迁移路线图:7 个阶段、18 个测试契约映射表、风险、完成定义。 |
| `cmd/main/` | MoonBit executable entry (scaffold `println("Hello")`). |
| `comemoon.mbt` / `moon.pkg` | MoonBit library root (currently empty scaffold). |

## Development Commands

```bash
moon check            # type-check, no output
moon build            # build all targets (output in _build/)
moon test             # run all tests (blackbox `_test.mbt` + whitebox `_wbtest.mbt`)
moon test --update    # refresh snapshot tests
moon run cmd/main     # run the executable
moon fmt              # format (block style, `///|` separators)
moon info             # regenerate .mbti interface files — run `moon info && moon fmt` after API changes; review .mbti diffs
moon coverage         # coverage analysis (moon coverage analyze > uncovered.log)
moon add <pkg>        # add dependency (e.g. moonbitlang/x)
```

No MoonBit CI workflow exists yet — port the Rust CI gates (`cargo test --all-features`, clippy, fmt check, doc) to `moon check`/`moon test`/`moon fmt --check` equivalents when CI is added.

## Code Conventions & Common Patterns

- **Block-style code**: separate logical blocks with `///|` markers (MoonBit convention).
- **Error handling**: MoonBit uses `Result[T, E]` / `raise` / `try` — no exceptions. comemo's Rust panics (non-determinism, impure tracked fn) map to `panic()` calls in debug paths.
- **No proc macros in MoonBit — official codegen is the chosen strategy**: `#[memoize]` / `#[track]` are replaced by (1) user-written code annotated with custom attributes (`#comemo.memoize`, `#comemo.track` — compiler-ignored, parsed by our generator), (2) a MoonBit-written generator CLI (`gen/`) that emits all boilerplate (Call enums, `tracked()` wrappers, cache declarations, memoize calls), (3) the official `rule` + `dev_build` build hooks (`moon.mod` rule + `moon.pkg` dev_build) which run the generator automatically before `moon check`/`build`/`test` with `$input`/`$output` path substitution. Generated files are COMMITTED to the repo (downstream users build without running the generator — this is the documented design intent). The Rust macros' expansion (`macros/src/memoize.rs`, `macros/src/track.rs`) is the codegen spec. Verified working end-to-end on moon 0.1.20260724. See `PORTING-PLAN.md` for the full design.
- **Rust dep replacements**:
  - `siphasher` → implement/copy SipHash13 128-bit (or use `moonbitlang/x` hash if available).
  - `rustc-hash` FxHashMap + `u128` keys → MoonBit `HashMap` with custom hasher.
  - `slab` (arena) → MoonBit `Array`-backed free-list arena.
  - `parking_lot` locks → MoonBit `Mutex`/`RwLock` (in `moonbitlang/core`), or thread-local/unsafe where single-threaded.
  - `quickcheck` → property tests via loops over generated inputs in `_wbtest.mbt`.
- **Naming**: follow MoonBit conventions (snake_case fns, CamelCase types); keep public API names parallel to comemo (`memoize`, `evict`, `Tracked`, `TrackedMut`, `Track`, `Constraint`).
- **Tests**: prefer `assert_eq`/`assert_true` over Show-debugging; use `debug_inspect` + `derive(Debug)` for snapshot tests.

## Important Files

| File | Why it matters |
|---|---|
| `moon.mod` | Module metadata: `name = "username/comemoon"`, `preferred_target = "wasm"`. Update `name` before publishing. |
| `moon.pkg` | Root library package (currently 0 bytes — empty = valid lib). |
| `cmd/main/moon.pkg` | Executable package config (`pkgtype(kind: "executable")`). |
| `refs/comemo/Cargo.toml` | Rust dep manifest (features: `macros`, `testing`; dev-deps: quickcheck, serial_test). |
| `refs/comemo/src/lib.rs` | Rust public API surface — the export list to mirror: `memoize`, `track`, `evict`, `Track`, `Tracked`, `TrackedMut`, `Constraint`, `testing::last_was_hit`. |
| `NovaForge-Output-comemo/ch3-core.typ` | Deep dive on CallTree/constraint internals — read before porting `tree.rs`. |

## Runtime/Tooling Preferences

- **Toolchain**: MoonBit `moon` ≥ 0.1.20260724 (installed at `~/.moon/bin/moon`). Note: this version uses `moon.mod` (not `moon.mod.json`) and `.mbt` sources.
- **Rust reference**: Rust 1.88, edition 2024, workspace comemo + comemo-macros; rustfmt profile `use_small_heuristics="Max"`, max_width 90.
- **Targets**: `preferred_target = "wasm"` currently; native target useful for the speed/memory goal — verify performance claims against the Rust baseline (add benchmarks under `bench/` when the port lands).

## Testing & QA

**Contract to port from Rust (all in `refs/comemo/tests/tests.rs`, all `#[serial]` due to the global hit/miss oracle):**

- `test_basic`, `test_calc` — basic memoization + calc dependency graph
- `test_evict` — age-based eviction
- `test_tracked_trait`, `test_memoized_methods`, `test_kinds`, `test_lifetime`, `test_chain`, `test_variance` — Tracked/trait/method/arg-kind semantics
- `test_purely_mutable`, `test_mutable_nested` — TrackedMut mutation replay
- `test_many_with_same_key` — 1000 same-key entries must stay non-quadratic (accelerator's role)
- `test_non_deterministic`, `test_deterministic_out_of_order`, `test_impure_tracked_method` — panic/debug behaviors
- `test_with_disabled` — `enabled` bypass
- `test_memoize_quickcheck` — property test over mixed args
- Plus tree invariants: `assert_consistency`, `test_call_tree`, `test_call_tree_quickcheck` (in `src/tree.rs`)

**MoonBit test layout:**
- `comemoon_test.mbt` — blackbox tests against public API (import via `@comemoon`).
- `comemoon_wbtest.mbt` — whitebox tests for internal helpers/invariants.
- Port the hit/miss oracle (`testing.rs` `last_was_hit()`) to assert cache behavior.
- MoonBit lacks a `#[serial]` equivalent — the oracle state must be per-test reset or keyed to avoid cross-test contamination.
