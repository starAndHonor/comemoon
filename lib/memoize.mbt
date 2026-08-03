///| An input to a memoized function.
///

///| Replaces Rust's `Input` trait (which needs associated types and trait

///| objects MoonBit lacks). The user supplies:

///| - `key`: hashes the non-tracked argument parts.

///| - `attach`: installs the recording callback onto the tracked parts

///|   (mirrors `Input::attach`).

///| - `oracle`: replays a recorded call on the current tracked value and

///|   returns the hash of its result (mirrors `Input::call`).

///| - `replay_mut`: re-executes a recorded mutable call for its side effect

///|
///   (mirrors `Input::call_mut`, used on cache hit).
pub struct Input[C] {
  key : () -> UInt128
  attach : (Recorder[C]) -> Recorder[C]?
  oracle : (C) -> UInt128
  replay_mut : (C) -> Unit
  detach : (Recorder[C]?) -> Unit
}

///| Constructs an input. A named constructor is required because MoonBit

///| treats records with function fields as read-only (cannot be built with a

///|
/// literal from outside the defining package).
pub fn[C] Input::new(
  key : () -> UInt128,
  attach : (Recorder[C]) -> Recorder[C]?,
  oracle : (C) -> UInt128,
  replay_mut : (C) -> Unit,
  detach : (Recorder[C]?) -> Unit,
) -> Input[C] {
  { key, attach, oracle, replay_mut, detach }
}

///| Executes a function, trying to use a cached result for it.
///

///| Mirrors `comemo::memoize` (Rust): bypass when disabled; hash key →

///| lookup with oracle replay → on hit replay mutations and return clone;

///|
/// on miss attach constraint, run `func`, insert.
pub fn[C : RustHashable, O] memoize(
  cache : Cache[C, O],
  input : Input[C],
  enabled : Bool,
  func : () -> O,
) -> O {
  //| Early bypass if memoization is disabled.
  if !enabled {
    register_miss()
    return func()
  }

  //| Compute the hash of the input's key part.
  let key = (input.key)()

  //| Check if there is a cached output.
  let lookup_res = cache.lookup(key, input.oracle)
  match lookup_res {
    Some(entry) => {
      //| Replay mutations.
      for call in entry.mutable {
        (input.replay_mut)(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }

  //| Attach the constraint.
  let constraint = Constraint::new()
  let prev = (input.attach)(fn(
    call : C,
    call_hash : UInt128,
    ret : UInt128,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })

  //| Execute the function with the constraint attached.
  let output = func()

  //| Restore the previous recorder so chain links don't accumulate.
  (input.detach)(prev)

  //| Insert the result into the cache.
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(AlreadyExists) => ()
    Err(MissingCall) =>
      //| A missing call indicates a bug from a comemo user.
      panic()
  }

  //| Mirrors Rust: `register_miss` runs after insertion so that nested
  //| memoized calls (whose hits would otherwise win) don't override it.
  register_miss()

  output
}

///| Memoize for pure-argument functions (no tracked parameters).

///|
/// Call type is unused (no tracking); key is computed by the caller.
pub fn[C : RustHashable, O] memoize_pure(
  cache : Cache[C, O],
  key : UInt128,
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  //| Inline lookup (avoids per-call closure allocations of the generic
  //| Input/memoize path, which cost ~30ns on the hot path).
  let zero : UInt128 = hash_zero()
  match cache.lookup(key, fn(_c : C) -> UInt128 { zero }) {
    Some(entry) => {
      register_hit()
      return entry.output
    }
    None => ()
  }
  let output = func()
  let constraint = Constraint::new()
  //| No tracked calls in a pure fn: insert with empty sequence.
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}