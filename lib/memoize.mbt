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
  key : () -> UInt64
  attach : (Recorder[C]) -> Recorder[C]?
  oracle : (C) -> UInt64
  replay_mut : (C) -> Unit
  detach : (Recorder[C]?) -> Unit
}

///| Constructs an input. A named constructor is required because MoonBit

///| treats records with function fields as read-only (cannot be built with a

///|
/// literal from outside the defining package).
pub fn[C] Input::new(
  key : () -> UInt64,
  attach : (Recorder[C]) -> Recorder[C]?,
  oracle : (C) -> UInt64,
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
    call_hash : UInt64,
    ret : UInt64,
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
  key : UInt64,
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  //| Inline lookup (avoids per-call closure allocations of the generic
  //| Input/memoize path, which cost ~30ns on the hot path).
  match cache.lookup_pure(key) {
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

///| ---------------------------------------------------------------------------

///| Multi-input support (mirrors Rust's `Multi<(...)>` for 2 tracked params).

///| The generator produces a merged Call enum (CM) and uses `Input2` to

///| route calls from either parameter into it.

///| ---------------------------------------------------------------------------

///| An input with two tracked parameters.

///| `attach` returns both params' previous recorders (for restore);

///| `detach` restores them; `oracle`/`replay_mut` dispatch on the merged

///|
/// call.
pub struct Input2[C1, C2, CM] {
  key : () -> UInt64
  attach : (Recorder[CM]) -> (Recorder[C1]?, Recorder[C2]?)
  oracle : (CM) -> UInt64
  replay_mut : (CM) -> Unit
  detach : ((Recorder[C1]?, Recorder[C2]?)) -> Unit
}

///|
pub fn[C1, C2, CM] Input2::new(
  key : () -> UInt64,
  attach : (Recorder[CM]) -> (Recorder[C1]?, Recorder[C2]?),
  oracle : (CM) -> UInt64,
  replay_mut : (CM) -> Unit,
  detach : ((Recorder[C1]?, Recorder[C2]?)) -> Unit,
) -> Input2[C1, C2, CM] {
  { key, attach, oracle, replay_mut, detach }
}

///|
/// Memoize with two tracked parameters.
pub fn[C1 : RustHashable, C2 : RustHashable, CM : RustHashable, O] memoize2(
  cache : Cache[CM, O],
  input : Input2[C1, C2, CM],
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  let key = (input.key)()
  let lookup_res = cache.lookup(key, input.oracle)
  match lookup_res {
    Some(entry) => {
      for call in entry.mutable {
        (input.replay_mut)(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }
  let constraint = Constraint::new()
  let prev = (input.attach)(fn(
    call : CM,
    call_hash : UInt64,
    ret : UInt64,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })
  let output = func()
  (input.detach)(prev)
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}

///| ---------------------------------------------------------------------------

///| An input with 3 tracked parameters. `attach` returns all params'

///| previous recorders (for restore); `detach` restores them; `oracle`/

///| `replay_mut` dispatch on the merged call.

///|
/// ---------------------------------------------------------------------------
pub struct Input3[C1, C2, C3, CM] {
  key : () -> UInt64
  attach : (Recorder[CM]) -> (Recorder[C1]?, Recorder[C2]?, Recorder[C3]?)
  oracle : (CM) -> UInt64
  replay_mut : (CM) -> Unit
  detach : ((Recorder[C1]?, Recorder[C2]?, Recorder[C3]?)) -> Unit
}

///|
pub fn[C1, C2, C3, CM] Input3::new(
  key : () -> UInt64,
  attach : (Recorder[CM]) -> (Recorder[C1]?, Recorder[C2]?, Recorder[C3]?),
  oracle : (CM) -> UInt64,
  replay_mut : (CM) -> Unit,
  detach : ((Recorder[C1]?, Recorder[C2]?, Recorder[C3]?)) -> Unit,
) -> Input3[C1, C2, C3, CM] {
  { key, attach, oracle, replay_mut, detach }
}

///|
/// Memoize with 3 tracked parameters.
pub fn[
  C1 : RustHashable,
  C2 : RustHashable,
  C3 : RustHashable,
  CM : RustHashable,
  O,
] memoize3(
  cache : Cache[CM, O],
  input : Input3[C1, C2, C3, CM],
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  let key = (input.key)()
  let lookup_res = cache.lookup(key, input.oracle)
  match lookup_res {
    Some(entry) => {
      for call in entry.mutable {
        (input.replay_mut)(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }
  let constraint = Constraint::new()
  let prev = (input.attach)(fn(
    call : CM,
    call_hash : UInt64,
    ret : UInt64,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })
  let output = func()
  (input.detach)(prev)
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}

///| ---------------------------------------------------------------------------

///| An input with 4 tracked parameters. `attach` returns all params'

///| previous recorders (for restore); `detach` restores them; `oracle`/

///| `replay_mut` dispatch on the merged call.

///|
/// ---------------------------------------------------------------------------
pub struct Input4[C1, C2, C3, C4, CM] {
  key : () -> UInt64
  attach : (Recorder[CM]) -> (
    Recorder[C1]?,
    Recorder[C2]?,
    Recorder[C3]?,
    Recorder[C4]?,
  )
  oracle : (CM) -> UInt64
  replay_mut : (CM) -> Unit
  detach : ((Recorder[C1]?, Recorder[C2]?, Recorder[C3]?, Recorder[C4]?)) -> Unit
}

///|
pub fn[C1, C2, C3, C4, CM] Input4::new(
  key : () -> UInt64,
  attach : (Recorder[CM]) -> (
    Recorder[C1]?,
    Recorder[C2]?,
    Recorder[C3]?,
    Recorder[C4]?,
  ),
  oracle : (CM) -> UInt64,
  replay_mut : (CM) -> Unit,
  detach : ((Recorder[C1]?, Recorder[C2]?, Recorder[C3]?, Recorder[C4]?)) -> Unit,
) -> Input4[C1, C2, C3, C4, CM] {
  { key, attach, oracle, replay_mut, detach }
}

///|
/// Memoize with 4 tracked parameters.
pub fn[
  C1 : RustHashable,
  C2 : RustHashable,
  C3 : RustHashable,
  C4 : RustHashable,
  CM : RustHashable,
  O,
] memoize4(
  cache : Cache[CM, O],
  input : Input4[C1, C2, C3, C4, CM],
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  let key = (input.key)()
  let lookup_res = cache.lookup(key, input.oracle)
  match lookup_res {
    Some(entry) => {
      for call in entry.mutable {
        (input.replay_mut)(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }
  let constraint = Constraint::new()
  let prev = (input.attach)(fn(
    call : CM,
    call_hash : UInt64,
    ret : UInt64,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })
  let output = func()
  (input.detach)(prev)
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}

///| ---------------------------------------------------------------------------

///| An input with 5 tracked parameters. `attach` returns all params'

///| previous recorders (for restore); `detach` restores them; `oracle`/

///| `replay_mut` dispatch on the merged call.

///|
/// ---------------------------------------------------------------------------
pub struct Input5[C1, C2, C3, C4, C5, CM] {
  key : () -> UInt64
  attach : (Recorder[CM]) -> (
    Recorder[C1]?,
    Recorder[C2]?,
    Recorder[C3]?,
    Recorder[C4]?,
    Recorder[C5]?,
  )
  oracle : (CM) -> UInt64
  replay_mut : (CM) -> Unit
  detach : (
    (Recorder[C1]?, Recorder[C2]?, Recorder[C3]?, Recorder[C4]?, Recorder[C5]?),
  ) -> Unit
}

///|
pub fn[C1, C2, C3, C4, C5, CM] Input5::new(
  key : () -> UInt64,
  attach : (Recorder[CM]) -> (
    Recorder[C1]?,
    Recorder[C2]?,
    Recorder[C3]?,
    Recorder[C4]?,
    Recorder[C5]?,
  ),
  oracle : (CM) -> UInt64,
  replay_mut : (CM) -> Unit,
  detach : (
    (Recorder[C1]?, Recorder[C2]?, Recorder[C3]?, Recorder[C4]?, Recorder[C5]?),
  ) -> Unit,
) -> Input5[C1, C2, C3, C4, C5, CM] {
  { key, attach, oracle, replay_mut, detach }
}

///|
/// Memoize with 5 tracked parameters.
pub fn[
  C1 : RustHashable,
  C2 : RustHashable,
  C3 : RustHashable,
  C4 : RustHashable,
  C5 : RustHashable,
  CM : RustHashable,
  O,
] memoize5(
  cache : Cache[CM, O],
  input : Input5[C1, C2, C3, C4, C5, CM],
  enabled : Bool,
  func : () -> O,
) -> O {
  if !enabled {
    register_miss()
    return func()
  }
  let key = (input.key)()
  let lookup_res = cache.lookup(key, input.oracle)
  match lookup_res {
    Some(entry) => {
      for call in entry.mutable {
        (input.replay_mut)(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }
  let constraint = Constraint::new()
  let prev = (input.attach)(fn(
    call : CM,
    call_hash : UInt64,
    ret : UInt64,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })
  let output = func()
  (input.detach)(prev)
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}

///|
/// Specialized memoize for a single TrackedMut parameter (hot path for
/// Typst's sink pattern). Inlines the lookup + attach + replay logic to
/// avoid the generic `Input` closure allocation.
pub fn[C : RustHashable, A, O] memoize_tracked_mut(
  cache : Cache[C, O],
  key : UInt64,
  tm : TrackedMut[A, C],
  oracle : (C) -> UInt64,
  replay_mut : (C) -> Unit,
  enabled : Bool,
  func : (TrackedMut[A, C]) -> O,
) -> O {
  if !enabled {
    register_miss()
    return func(tm)
  }
  let lookup_res = cache.lookup(key, oracle)
  match lookup_res {
    Some(entry) => {
      //| Replay mutations.
      for call in entry.mutable {
        replay_mut(call)
      }
      register_hit()
      return entry.output
    }
    None => ()
  }
  let constraint = Constraint::new()
  let prev = tm.attach(fn(
    call : C,
    call_hash : UInt64,
    ret : UInt64,
    mutable : Bool,
  ) -> Unit {
    constraint.record(call, call_hash, ret, mutable)
  })
  let output = func(tm)
  tm.detach(prev)
  match cache.insert(key, constraint, output) {
    Ok(_) => ()
    Err(_) => ()
  }
  register_miss()
  output
}
