///| A deduplicated sequence of calls to tracked functions, optimized for

///| efficient insertion into a call tree.
///

///| Semantics mirror `comemo::constraint::CallSequence` (Rust): pairs of

///| `(call, return_hash)` are inserted in order, deduplicated by call hash.

///|
/// `next` consumes in order; `extract` consumes by call hash.
pub struct CallSequence[C] {
  /// The raw calls. In order, but deduplicated via the `map`.
  vec : Array[(C, UInt64)?]
  /// A map from hashes of calls to the indices in the vector.
  map : @hashmap.HashMap[UInt64, Int]
  /// A cursor for iteration in `next`.
  mut cursor : Int
}

///|
/// Creates an empty sequence.
pub fn[C] CallSequence::new() -> CallSequence[C] {
  { vec: Array::new(), map: @hashmap.HashMap([]), cursor: 0 }
}

///| Inserts a pair of a call and its return hash.
///

///| Returns `true` when the pair was indeed inserted and `false` if the call

///|
/// was deduplicated.
pub fn[C : RustHashable] CallSequence::insert(
  self : CallSequence[C],
  call : C,
  ret : UInt64,
) -> Bool {
  let h = hash(call)
  match self.map.get(h) {
    None => {
      let i = self.vec.length()
      self.vec.push(Some((call, ret)))
      self.map[h] = i
      true
    }
    Some(i) => {
      //| Debug-only in Rust; kept unconditional here since MoonBit has no
      //| `debug_assertions` cfg. Same panic message for parity.
      match self.vec[i] {
        Some((_, ret2)) =>
          if ret != ret2 {
            //| comemo: found differing return values.
            //| is there an impure tracked function?
            panic()
          }
        None => ()
      }
      false
    }
  }
}

///|
/// Retrieves the next call in order.
pub fn[C] CallSequence::next(self : CallSequence[C]) -> (C, UInt64)? {
  while self.cursor < self.vec.length() {
    if self.vec[self.cursor] is Some(_) {
      let pair = self.vec[self.cursor]
      self.vec[self.cursor] = None
      return pair
    }
    self.cursor = self.cursor + 1
  }
  None
}

///| Retrieves the return hash of an arbitrary upcoming call. Removes the

///|
/// call from the sequence; it will not be yielded by `next` anymore.
pub fn[C : RustHashable] CallSequence::extract(
  self : CallSequence[C],
  call : C,
) -> UInt64? {
  let h = hash(call)
  match self.map.get(h) {
    None => None
    Some(i) => {
      let res = match self.vec[i] {
        Some((_, ret)) => Some(ret)
        None => None
      }
      self.vec[i] = None
      res
    }
  }
}

///| Records calls performed on a trackable type.
///

///| Mirrors `comemo::constraint::Constraint` (Rust): immutable calls go into

///| a deduplicated `CallSequence` (for the tree path); mutable calls go into

///| a plain list (replayed on cache hit). The `mutable` flag on `record`

///|
/// replaces Rust's `Call::is_mutable` dynamic dispatch.
pub struct Constraint[C] {
  /// The immutable calls, ready for integration into a call tree.
  immutable : CallSequence[C]
  /// The mutable calls, for insertion as part of the call tree output value.
  mutable : Array[C]
}

///|
/// The type of a recording callback attached to a `Tracked` value.
pub type Recorder[C] = (C, UInt64, UInt64, Bool) -> Unit

///|
/// Creates an empty constraint.
pub fn[C] Constraint::new() -> Constraint[C] {
  { immutable: CallSequence::new(), mutable: Array::new() }
}

///| Records one call. `mutable = true` pushes to the replay list (return hash

///| is ignored); otherwise the `(call, ret)` pair is deduplicated into the

///|
/// sequence.

///| Records a call. `call_hash` is the precomputed hash of `call` (the

///|
/// recorder supplies it — it knows how to hash C).
pub fn[C] Constraint::record(
  self : Constraint[C],
  call : C,
  call_hash : UInt64,
  ret : UInt64,
  mutable : Bool,
) -> Unit {
  if mutable {
    self.mutable.push(call)
  } else {
    ignore(self.immutable.insert_with_hash(call, call_hash, ret))
  }
}

///| Consumes the constraint, returning the immutable sequence (tree path) and

///|
/// the mutable calls (replay list).
pub fn[C] Constraint::take(self : Constraint[C]) -> (CallSequence[C], Array[C]) {
  (self.immutable, self.mutable)
}

///|
/// Inserts with a precomputed call hash (used by Constraint::record).
fn[C] CallSequence::insert_with_hash(
  self : CallSequence[C],
  call : C,
  h : UInt64,
  ret : UInt64,
) -> Bool {
  match self.map.get(h) {
    None => {
      let i = self.vec.length()
      self.vec.push(Some((call, ret)))
      self.map[h] = i
      true
    }
    Some(i) => {
      match self.vec[i] {
        Some((_, ret2)) => if ret != ret2 { panic() }
        None => ()
      }
      false
    }
  }
}
