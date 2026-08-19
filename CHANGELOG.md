# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-08-19

### Changed

- Rewrote README in standard open-source format: centered header with
  CI/mooncakes/license/tests badges, Why/Features/Quick start/Demo/API
  overview/How-it-works sections, and a condensed 3-item "Differences from
  Rust comemo" section.
- `moon.mod` `readme` field now points at `README.md`; `README.mbt.md` is the
  `moon package`-derived copy served on mooncakes.io.

## [0.1.0] - 2026-08-05

Initial release. MoonBit port of [comemo](https://github.com/typst/comemo)
v0.5.1 — incremental computation through constrained memoization.

### Added

- Full constrained-memoization runtime: dependency tracking, constraint
  recording/replay, CallTree validation, age-based eviction.
- `Tracked` / `TrackedMut` wrappers; mutable calls replayed on cache hit with
  downgrade / reborrow / track_mut views.
- Trait-level tracking via `#comemo.track` on traits, generating generic
  surfaces (`WorldTracked[T]`, `fn[T : World]` bounds).
- Multi-parameter memoization: `memoize` … `memoize6` (0–6 tracked params).
- Per-instance validation accelerator (call→return-hash map, O(1) revalidation).
- Build-time code generator (`gen/gen.py`) wired through MoonBit's official
  `rule` / `dev_build` hooks; generated code committed.
- 31 tests covering the comemo behavioral contract, green on wasm + native.
- Calc dependency-graph demo in `cmd/main/`.
- CI: check, wasm + native tests, fmt check, generator consistency check.
