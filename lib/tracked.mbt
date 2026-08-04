///| Tracks accesses and mutations to a value.
///

///| Mirrors `comemo::Tracked` (Rust). Two substitutes for Rust features:

///| - `value : Ref[A]` mimics `&'a T`: all copies of a `Tracked` share one

///|   underlying value, so external mutation is observed by every holder

///|   (Rust's shared reference).

///| - the sink is a recording callback `Option[Recorder[C]]` instead of

///|   Rust's `&dyn Sink` trait object.

///| `record` is `Ref` so `attach` can set it in place through a shared

///|
/// reference (the memoize preamble).
pub(all) struct Tracked[A, C] {
  /// The tracked value (shared, mutable through `Ref`).
  value : Ref[A]
  /// A recording callback; `None` outside a memoized call.
  record : Ref[Recorder[C]?]
  /// A unique ID for validation acceleration.
  id : Int
}

///|
/// Creates a tracked value with no active recorder.
pub fn[A, C] Tracked::new(value : A) -> Tracked[A, C] {
  { value: { val: value }, record: { val: None }, id: accelerator_id() }
}

///| Starts tracking mutations too: returns a mutable view sharing the same

///|
/// underlying value and recorder (mirrors Rust's `Track::track_mut`).
pub fn[A, C] Tracked::track_mut(self : Tracked[A, C]) -> TrackedMut[A, C] {
  { value: self.value, record: self.record, id: accelerator_id() }
}

///| Attaches a recording callback (called in the memoize preamble).
///

///| Mirrors Rust's `MergedSink`: if a recorder is already attached (from an

///| enclosing memoized call), the new one chains to it — after recording to

///| the inner constraint, the call is propagated to the outer recorder. This

///| is what makes nested memoized calls record their tracked reads into the

///| enclosing constraint.
///

///| Returns the previously attached recorder so the caller can restore it

///| after the memoized call completes. Without this, chain links accumulate

///|
/// across calls and stale constraints get written on later invocations.
pub fn[A, C] Tracked::attach(
  self : Tracked[A, C],
  recorder : Recorder[C],
) -> Recorder[C]? {
  let prev = self.record.val
  self.record.val = Some(fn(
    call : C,
    call_hash : UInt128,
    ret : UInt128,
    mutable : Bool,
  ) -> Unit {
    recorder(call, call_hash, ret, mutable)
    match prev {
      Some(p) => p(call, call_hash, ret, mutable)
      None => ()
    }
  })
  prev
}

///|
/// Restores a previously detached recorder (the value returned by `attach`).
pub fn[A, C] Tracked::detach(self : Tracked[A, C], prev : Recorder[C]?) -> Unit {
  self.record.val = prev
}

///|
/// The current value.
pub fn[A, C] Tracked::get(self : Tracked[A, C]) -> A {
  self.value.val
}

///| Executes an immutable tracked call: runs `f` on the current value and,

///| if a recorder is attached, records `(call, hash(result))`. Mirrors the

///|
/// surface-method expansion of Rust's `#[track]` (immutable case).

///| Executes an immutable tracked call: runs `f` on the current value and,

///| if a recorder is attached, records `(call, ret_hash)`. `ret_hash` is a

///| function from the result to its Rust-style hash, supplied by the caller

///|
/// (generated code knows the return type and calls `hash_string`/etc.).
pub fn[A, C : RustHashable, R] Tracked::call(
  self : Tracked[A, C],
  call : C,
  f : (A) -> R,
  ret_hash : (R) -> UInt128,
) -> R {
  let ret = f(self.value.val)
  match self.record.val {
    Some(rec) => rec(call, hash(call), ret_hash(ret), false)
    None => ()
  }
  ret
}

///| Executes a mutable tracked call: runs `f` for its side effect and, if a

///| recorder is attached, records the call (`mutable = true`). Mirrors the

///|
/// surface-method expansion of Rust's `#[track]` (mutable case).
pub fn[A, C : RustHashable, R] Tracked::call_mut(
  self : Tracked[A, C],
  call : C,
  f : (A) -> R,
  _ret_hash : (R) -> UInt128,
) -> R {
  let ret = f(self.value.val)
  match self.record.val {
    Some(rec) => rec(call, hash(call), hash_unit(), true)
    None => ()
  }
  ret
}

///| Replays a call for validation, using the per-instance accelerator to

///| memoize `hash(call) -> hash(ret)`. Mirrors the accelerator path in

///|
/// Rust's `Input::call` for `Tracked`.

///| Replays a call for validation, using the per-instance accelerator to

///| memoize `hash(call) -> ret_hash`. `ret_hash` is supplied by the caller

///|
/// (generated code knows the return type).
pub fn[A, C : RustHashable, R] Tracked::validate(
  self : Tracked[A, C],
  call : C,
  f : (A) -> R,
  ret_hash : (R) -> UInt128,
) -> UInt128 {
  let call_hash = hash(call)
  match accelerator_get(self.id, call_hash) {
    Some(ret) => ret
    None => {
      let ret = ret_hash(f(self.value.val))
      accelerator_insert(self.id, call_hash, ret)
      ret
    }
  }
}

///| ---------------------------------------------------------------------------

///| TrackedMut: a mutable tracked parameter (mirrors `comemo::TrackedMut`).

///|

///| MoonBit has no `&mut T` borrow, so both `Tracked` and `TrackedMut` hold

///| the value in a shared `Ref[A]`. The two types differ in *semantics*:

///| a `TrackedMut` parameter's calls are recorded as `mutable = true`, which

///| makes the cache replay them (with their side effects) on a hit instead

///| of only checking their result hash.

///|
/// ---------------------------------------------------------------------------
pub(all) struct TrackedMut[A, C] {
  /// The tracked value (shared, mutable through `Ref`).
  value : Ref[A]
  /// A recording callback; `None` outside a memoized call.
  record : Ref[Recorder[C]?]
  /// A unique ID for validation acceleration.
  id : Int
}

///|
/// Creates a mutable tracked value with no active recorder.
pub fn[A, C] TrackedMut::new(value : A) -> TrackedMut[A, C] {
  { value: { val: value }, record: { val: None }, id: accelerator_id() }
}

///| Downgrades to an immutable tracked view (mirrors

///| `TrackedMut::downgrade`). The two wrappers share the underlying value

///|
/// and recorder, so writes through one are seen by the other.
pub fn[A, C] TrackedMut::downgrade(self : TrackedMut[A, C]) -> Tracked[A, C] {
  { value: self.value, record: self.record, id: accelerator_id() }
}

///| Reborrows with a fresh validation id (mirrors `TrackedMut::reborrow`,

///|
/// which returns an immutable `Tracked`).
pub fn[A, C] TrackedMut::reborrow(self : TrackedMut[A, C]) -> Tracked[A, C] {
  self.downgrade()
}

///| Reborrows mutably: a new `TrackedMut` sharing the value and recorder,

///|
/// with a fresh validation id (mirrors `TrackedMut::reborrow_mut`).
pub fn[A, C] TrackedMut::reborrow_mut(
  self : TrackedMut[A, C],
) -> TrackedMut[A, C] {
  { value: self.value, record: self.record, id: accelerator_id() }
}

///|
/// Attaches a recording callback (same chaining semantics as `Tracked`).
pub fn[A, C] TrackedMut::attach(
  self : TrackedMut[A, C],
  recorder : Recorder[C],
) -> Recorder[C]? {
  let prev = self.record.val
  self.record.val = Some(fn(
    call : C,
    call_hash : UInt128,
    ret : UInt128,
    mutable : Bool,
  ) -> Unit {
    recorder(call, call_hash, ret, mutable)
    match prev {
      Some(p) => p(call, call_hash, ret, mutable)
      None => ()
    }
  })
  prev
}

///|
/// Restores a previously detached recorder.
pub fn[A, C] TrackedMut::detach(
  self : TrackedMut[A, C],
  prev : Recorder[C]?,
) -> Unit {
  self.record.val = prev
}

///|
/// The current value.
pub fn[A, C] TrackedMut::get(self : TrackedMut[A, C]) -> A {
  self.value.val
}

///| Executes a mutable tracked call: runs `f` for its side effect and, if a

///| recorder is attached, records it as `mutable = true` with unit result

///|
/// hash. Mirrors `TrackedMut`'s surface-method expansion (mutable case).
pub fn[A, C : RustHashable, R] TrackedMut::call_mut(
  self : TrackedMut[A, C],
  call : C,
  f : (A) -> R,
  _ret_hash : (R) -> UInt128,
) -> R {
  let ret = f(self.value.val)
  match self.record.val {
    Some(rec) => rec(call, hash(call), hash_unit(), true)
    None => ()
  }
  ret
}

///| Executes an immutable tracked call through a mutable view (mirrors

///| `TrackedMut`'s `Deref` to `SurfaceMut`, which can call immutable

///|
/// methods). Records `mutable = false`.
pub fn[A, C : RustHashable, R] TrackedMut::call(
  self : TrackedMut[A, C],
  call : C,
  f : (A) -> R,
  ret_hash : (R) -> UInt128,
) -> R {
  let ret = f(self.value.val)
  match self.record.val {
    Some(rec) => rec(call, hash(call), ret_hash(ret), false)
    None => ()
  }
  ret
}

///| Replays a mutable call for validation, using the per-instance

///| accelerator to memoize `hash(call) -> ret_hash`. Mirrors `TrackedMut`

///| as a `Tracked` argument in `Input::call` (result hash matters for

///|
/// validation even though the call is mutable).
pub fn[A, C : RustHashable, R] TrackedMut::validate(
  self : TrackedMut[A, C],
  call : C,
  f : (A) -> R,
  ret_hash : (R) -> UInt128,
) -> UInt128 {
  let call_hash = hash(call)
  match accelerator_get(self.id, call_hash) {
    Some(ret) => ret
    None => {
      let ret = ret_hash(f(self.value.val))
      accelerator_insert(self.id, call_hash, ret)
      ret
    }
  }
}
