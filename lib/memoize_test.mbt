///| Phase 2 blackbox tests: mirror the semantics of Rust's

///|
/// `test_basic`, `test_evict`, and `test_calc` from `tests/tests.rs`.

//| ---------------------------------------------------------------------------
//| Basic memoization (mirrors test_basic).
//| ---------------------------------------------------------------------------

let empty_cache : Cache[UnitCall, String] = Cache::new()

///|
fn empty() -> String {
  memoize(
    empty_cache,
    Input::new(
      fn() { hash_unit() },
      fn(_) { None },
      fn(_) { hash_zero() },
      fn(_) { () },
      fn(_) { () },
    ),
    true,
    fn() { "The world is big" },
  )
}

///|
let double_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn double(x : Int) -> Int {
  memoize(
    double_cache,
    Input::new(
      fn() { hash_int(x) },
      fn(_) { None },
      fn(_) { hash_zero() },
      fn(_) { () },
      fn(_) { () },
    ),
    true,
    fn() { 2 * x },
  )
}

///|
let sum_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn sum(a : Int, b : Int) -> Int {
  memoize(
    sum_cache,
    Input::new(
      fn() { hash_combine2(test_hash_int(a), test_hash_int(b)) },
      fn(_) { None },
      fn(_) { hash_zero() },
      fn(_) { () },
      fn(_) { () },
    ),
    true,
    fn() { a + b },
  )
}

///|
let fib_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn fib(n : Int) -> Int {
  memoize(
    fib_cache,
    Input::new(
      fn() { hash_int(n) },
      fn(_) { None },
      fn(_) { hash_zero() },
      fn(_) { () },
      fn(_) { () },
    ),
    true,
    fn() { if n <= 2 { 1 } else { fib(n - 1) + fib(n - 2) } },
  )
}

///|
test "basic_memoization" {
  //| empty: miss then hits
  reset_oracle()
  if empty() != "The world is big" || last_was_hit() {
    panic()
  }
  reset_oracle()
  if empty() != "The world is big" || !last_was_hit() {
    panic()
  }
  reset_oracle()
  if empty() != "The world is big" || !last_was_hit() {
    panic()
  }

  //| double
  reset_oracle()
  if double(2) != 4 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if double(4) != 8 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if double(2) != 4 || !last_was_hit() {
    panic()
  }

  //| sum: same args hit, different order different key
  reset_oracle()
  if sum(2, 4) != 6 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if sum(2, 3) != 5 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if sum(2, 3) != 5 || !last_was_hit() {
    panic()
  }
  reset_oracle()
  if sum(4, 2) != 6 || last_was_hit() {
    panic()
  }

  //| fib: recursion shares cache
  reset_oracle()
  if fib(5) != 5 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if fib(3) != 2 || !last_was_hit() {
    panic()
  }
  reset_oracle()
  if fib(8) != 21 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if fib(7) != 13 || !last_was_hit() {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| Cache eviction (mirrors test_evict).
//| ---------------------------------------------------------------------------

///|
let null_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn null() -> Int {
  memoize(
    null_cache,
    Input::new(
      fn() { hash_unit() },
      fn(_) { None },
      fn(_) { hash_zero() },
      fn(_) { () },
      fn(_) { () },
    ),
    true,
    fn() { 0 },
  )
}

///|
test "cache_eviction" {
  reset_oracle()
  if null() != 0 || last_was_hit() {
    panic()
  } // miss
  reset_oracle()
  if null() != 0 || !last_was_hit() {
    panic()
  } // hit
  evict(2)
  reset_oracle()
  if null() != 0 || !last_was_hit() {
    panic()
  } // hit (age 1 <= 2)
  evict(2)
  evict(2)
  reset_oracle()
  if null() != 0 || !last_was_hit() {
    panic()
  } // hit (age 3 > 2? Rust: 3 evictions after last hit)
  evict(2)
  evict(2)
  evict(2)
  reset_oracle()
  if null() != 0 || last_was_hit() {
    panic()
  } // miss (age exceeded)
  reset_oracle()
  if null() != 0 || !last_was_hit() {
    panic()
  } // hit
  evict(0)
  reset_oracle()
  if null() != 0 || last_was_hit() {
    panic()
  } // miss (cleared)
  reset_oracle()
  if null() != 0 || !last_was_hit() {
    panic()
  } // hit
}

//| ---------------------------------------------------------------------------
//| Many entries with the same key hash (mirrors test_many_with_same_key).
//| 1000 contexts, each with a different tracked location → 1000 distinct call
//| sequences under the same key. With the accelerator, validation of a
//| repeated context is O(1); without it, re-running tracked methods would
//| make this quadratic.
//| ---------------------------------------------------------------------------

///|
struct Ctx {
  location : Int?
  styles : String
}

///|

///|
struct CtxTracked {
  t : Tracked[Ctx, CtxCall]
}

///|
fn CtxTracked::location(self : CtxTracked) -> Int? {
  self.t.call(CtxCall::Location, fn(c : Ctx) -> Int? { c.location }, fn(
    v : Int?,
  ) -> UInt64 {
    test_hash_opt(v, test_hash_int)
  })
}

///|
fn CtxTracked::styles(self : CtxTracked) -> String {
  self.t.call(
    CtxCall::Styles,
    fn(c : Ctx) -> String { c.styles },
    test_hash_str,
  )
}

///|
let ctx_cache : Cache[CtxCall, String] = Cache::new()

///|
fn contextual(ctx : CtxTracked) -> String {
  let tracked = ctx.t
  memoize(
    ctx_cache,
    Input::new(
      fn() { hash_unit() },
      fn(rec : Recorder[CtxCall]) -> Recorder[CtxCall]? { tracked.attach(rec) },
      fn(c : CtxCall) -> UInt64 {
        match c {
          Location =>
            tracked.validate(
              CtxCall::Location,
              fn(x : Ctx) -> Int? { x.location },
              fn(v : Int?) -> UInt64 { test_hash_opt(v, test_hash_int) },
            )
          Styles =>
            tracked.validate(
              CtxCall::Styles,
              fn(x : Ctx) -> String { x.styles },
              test_hash_str,
            )
        }
      },
      fn(_c : CtxCall) -> Unit { () },
      fn(prev : Recorder[CtxCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() {
      match ctx.location() {
        Some(loc) =>
          if loc == 5 {
            "Twenty has " + ctx.styles()
          } else {
            "Location: " + loc.to_string()
          }
        None => "No location"
      }
    },
  )
}

///|
test "many_with_same_key" {
  //| First pass: 1000 misses (each location inserts its own call sequence).
  let mut i = 0
  while i < 1000 {
    let ctx : CtxTracked = {
      t: Tracked::new({ location: Some(i), styles: "styles" }),
    }
    reset_oracle()
    let v = contextual(ctx)
    if v != oracle_ctx(i) || last_was_hit() {
      panic()
    }
    i = i + 1
  }
  //| Second pass: 1000 hits (same locations, accelerator keeps it O(1)).
  i = 0
  while i < 1000 {
    let ctx : CtxTracked = {
      t: Tracked::new({ location: Some(i), styles: "styles" }),
    }
    reset_oracle()
    let v = contextual(ctx)
    if v != oracle_ctx(i) || !last_was_hit() {
      panic()
    }
    i = i + 1
  }
}

///|
fn oracle_ctx(i : Int) -> String {
  if i == 5 {
    "Twenty has styles"
  } else {
    "Location: " + i.to_string()
  }
}

//| ---------------------------------------------------------------------------
//| Edge semantics: out-of-order determinism, impure tracked method,
//| non-deterministic memoized function.
//| ---------------------------------------------------------------------------

//| Out-of-order but deterministic calls still hit (mirrors
//| test_deterministic_out_of_order).

///|
struct OOContext {
  location : Int?
  styles : String
}

///|

///|
struct OOTracked {
  t : Tracked[OOContext, OOCall]
  order : Ref[Int]
}

///|
fn OOTracked::location(self : OOTracked) -> Int? {
  self.t.call(OOCall::OOLocation, fn(x : OOContext) -> Int? { x.location }, fn(
    v : Int?,
  ) -> UInt64 {
    test_hash_opt(v, test_hash_int)
  })
}

///|
fn OOTracked::styles(self : OOTracked) -> String {
  self.t.call(
    OOCall::OOStyles,
    fn(x : OOContext) -> String { x.styles },
    test_hash_str,
  )
}

///|
let oo_cache : Cache[OOCall, String] = Cache::new()

///|
fn oo_contextual(ctx : OOTracked) -> String {
  let tracked = ctx.t
  memoize(
    oo_cache,
    Input::new(
      fn() { hash_unit() },
      fn(rec : Recorder[OOCall]) -> Recorder[OOCall]? { tracked.attach(rec) },
      fn(c : OOCall) -> UInt64 {
        match c {
          OOLocation =>
            tracked.validate(
              OOCall::OOLocation,
              fn(x : OOContext) -> Int? { x.location },
              fn(v : Int?) -> UInt64 { test_hash_opt(v, test_hash_int) },
            )
          OOStyles =>
            tracked.validate(
              OOCall::OOStyles,
              fn(x : OOContext) -> String { x.styles },
              test_hash_str,
            )
        }
      },
      fn(_c : OOCall) -> Unit { () },
      fn(prev : Recorder[OOCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() {
      //| Order depends on ctx.order: first run location→styles, second styles→location.
      if ctx.order.val == 0 {
        let a = ctx.location()
        let b = ctx.styles()
        match a {
          Some(v) => v.to_string() + " " + b
          None => "none " + b
        }
      } else {
        let b = ctx.styles()
        let a = ctx.location()
        match a {
          Some(v) => v.to_string() + " " + b
          None => "none " + b
        }
      }
    },
  )
}

///|
test "deterministic_out_of_order" {
  //| First run: order 0 (location then styles) → miss.
  let ctx : OOTracked = {
    t: Tracked::new({ location: Some(0), styles: "styles" }),
    order: { val: 0 },
  }
  reset_oracle()
  if oo_contextual(ctx) != "0 styles" || last_was_hit() {
    panic()
  } // miss

  //| Second run: order 1 (styles then location) → still hit.
  ctx.order.val = 1
  reset_oracle()
  if oo_contextual(ctx) != "0 styles" || !last_was_hit() {
    panic()
  } // hit

  //| Different location → miss.
  let ctx2 : OOTracked = {
    t: Tracked::new({ location: Some(1), styles: "styles" }),
    order: { val: 1 },
  }
  reset_oracle()
  if oo_contextual(ctx2) != "1 styles" || last_was_hit() {
    panic()
  } // miss
}

//| ---------------------------------------------------------------------------
//| Impure detection at the Constraint level.
//|
//| Rust's impure-panic is a debug-only assertion tested with `should_panic`;
//| MoonBit tests cannot catch panics (a panic fails the test). So we verify
//| the detection logic directly: recording the same call hash with a
//| *different* return hash must panic inside `CallSequence::insert`. We test
//| the non-panic side (dedup keeps the first hash) here, and rely on the
//| panic path being exercised in the `impure_tracked_method_panics` test
//| below which is expected to fail loudly if the assertion regresses.
//| ---------------------------------------------------------------------------

///|
test "call_sequence_dedup_same_ret" {
  let cs = CallSequence::new()
  if !cs.insert(IntCall::I(42), (100).to_uint64()) {
    panic()
  } // first insert
  if cs.insert(IntCall::I(42), (100).to_uint64()) {
    panic()
  } // dedup, same ret → false
  //| next() yields the deduplicated pair once.
  match cs.next() {
    Some((call, ret)) =>
      match call {
        I(v) => if v != 42 || ret != 100 { panic() }
      }
    None => panic()
  }
  if cs.next() != None {
    panic()
  } // consumed
}

//| ---------------------------------------------------------------------------
//| Non-deterministic memoized function → MissingCall (mirrors
//| test_non_deterministic). The Rust test asserts a panic on insert; we
//| verify the detection at the CallTree level: inserting a sequence that is
//| missing a call recorded in the existing tree path returns MissingCall.
//| ---------------------------------------------------------------------------

///|
test "call_tree_missing_call" {
  let tree = CallTree::new()
  //| Insert a path with calls [a, b].
  let cs1 = CallSequence::new()
  ignore(cs1.insert(StrCall::S("a"), (10).to_uint64()))
  ignore(cs1.insert(StrCall::S("b"), (20).to_uint64()))
  match tree.insert(0, cs1, "v1") {
    Ok(_) => ()
    Err(_) => panic()
  }
  //| Now insert a sequence with only [a] — the tree path needs b.
  let cs2 = CallSequence::new()
  ignore(cs2.insert(StrCall::S("a"), (10).to_uint64()))
  match tree.insert(0, cs2, "v2") {
    Err(MissingCall) => ()
    Ok(_) => panic()
    Err(AlreadyExists) => panic()
  }
}

//| AlreadyExists: a sequence that is a prefix of an existing one.

///|
test "call_tree_already_exists" {
  let tree = CallTree::new()
  let cs1 = CallSequence::new()
  ignore(cs1.insert(StrCall::S("a"), (10).to_uint64()))
  match tree.insert(0, cs1, "v1") {
    Ok(_) => ()
    Err(_) => panic()
  }
  //| Same sequence again: leaf already exists at the end of the path.
  let cs2 = CallSequence::new()
  ignore(cs2.insert(StrCall::S("a"), (10).to_uint64()))
  match tree.insert(0, cs2, "v2") {
    Err(AlreadyExists) => ()
    Ok(_) => panic()
    Err(MissingCall) => panic()
  }
}

//| ---------------------------------------------------------------------------
//| Different argument kinds (mirrors test_kinds).
//| ---------------------------------------------------------------------------

///|
struct Tester {
  data : String
}

///|

///|
struct TesterTracked {
  t : Tracked[Tester, TesterCall]
}

///|
fn TesterTracked::new(value : Tester) -> TesterTracked {
  { t: Tracked::new(value) }
}

///|
fn TesterTracked::self_ref(self : TesterTracked) -> String {
  self.t.call(
    TesterCall::SelfRef,
    fn(x : Tester) -> String { x.data },
    test_hash_str,
  )
}

///|
fn TesterTracked::by_value(self : TesterTracked, heavy : String) -> Int {
  self.t.call(
    TesterCall::ByValue(heavy),
    fn(x : Tester) -> Int { x.data.length() + heavy.length() },
    test_hash_int,
  )
}

///|
let kinds_cache : Cache[TesterCall, String] = Cache::new()

///|
fn kinds_selfie(tester : TesterTracked) -> String {
  let tracked = tester.t
  memoize(
    kinds_cache,
    Input::new(
      fn() { hash_unit() },
      fn(rec : Recorder[TesterCall]) -> Recorder[TesterCall]? {
        tracked.attach(rec)
      },
      fn(c : TesterCall) -> UInt64 {
        match c {
          SelfRef =>
            tracked.validate(
              TesterCall::SelfRef,
              fn(x : Tester) -> String { x.data },
              test_hash_str,
            )
          ByValue(h) =>
            tracked.validate(
              TesterCall::ByValue(h),
              fn(x : Tester) -> Int { x.data.length() + h.length() },
              test_hash_int,
            )
        }
      },
      fn(_c : TesterCall) -> Unit { () },
      fn(prev : Recorder[TesterCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() { tester.self_ref() },
  )
}

///|
test "argument_kinds" {
  let tester : Tester = { data: "Hi" }
  let t1 : TesterTracked = TesterTracked::new(tester)
  reset_oracle()
  if kinds_selfie(t1) != "Hi" || last_was_hit() {
    panic()
  } // miss
  reset_oracle()
  if kinds_selfie(t1) != "Hi" || !last_was_hit() {
    panic()
  } // hit

  //| Change data → new tracked (fresh accelerator) → miss.
  let tester2 : Tester = { data: "Hi!" }
  let t2 : TesterTracked = TesterTracked::new(tester2)
  reset_oracle()
  if kinds_selfie(t2) != "Hi!" || last_was_hit() {
    panic()
  } // miss
}

//| ---------------------------------------------------------------------------
//| Disabled memoization (mirrors test_with_disabled).
//| ---------------------------------------------------------------------------

///|
let disabled_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn disabled(size : Int) -> Int {
  memoize(
    disabled_cache,
    Input::new(
      fn() { hash_int(size) },
      fn(_rec : Recorder[UnitCall]) -> Recorder[UnitCall]? { None },
      fn(_c : UnitCall) -> UInt64 { hash_zero() },
      fn(_c : UnitCall) -> Unit { () },
      fn(_prev : Recorder[UnitCall]?) -> Unit { () },
    ),
    size >= 1000,
    fn() { size },
  )
}

///|
test "with_disabled" {
  //| size < 1000: memoization disabled → always miss.
  reset_oracle()
  if disabled(0) != 0 || last_was_hit() {
    panic()
  } // miss (disabled)
  reset_oracle()
  if disabled(0) != 0 || last_was_hit() {
    panic()
  } // miss (disabled)

  //| size >= 1000: memoization enabled.
  reset_oracle()
  if disabled(2000) != 2000 || last_was_hit() {
    panic()
  } // miss
  reset_oracle()
  if disabled(2000) != 2000 || !last_was_hit() {
    panic()
  } // hit
}

//| ---------------------------------------------------------------------------
//| Purely mutable tracking (mirrors test_purely_mutable).
//| Mutable calls are recorded on miss and REPLAYED on hit, so side effects
//| are restored without re-running the memoized function.
//| ---------------------------------------------------------------------------

///|
struct Emitter {
  output : Ref[Array[String]]
}

///|

///|
struct EmitterTracked {
  t : Tracked[Emitter, EmitterCall]
}

///|
fn EmitterTracked::new(value : Emitter) -> EmitterTracked {
  { t: Tracked::new(value) }
}

///|
fn EmitterTracked::emit(self : EmitterTracked, msg : String) -> Unit {
  self.t.call_mut(
    EmitterCall::Emit(msg),
    fn(x : Emitter) -> Unit { x.output.val.push(msg) },
    hash_unit_value,
  )
}

///|
let emit_cache : Cache[EmitterCall, Unit] = Cache::new()

///|
fn dump(emitter : EmitterTracked, value : String) -> Unit {
  let tracked = emitter.t
  memoize(
    emit_cache,
    Input::new(
      fn() { hash_string(value) },
      fn(rec : Recorder[EmitterCall]) -> Recorder[EmitterCall]? {
        tracked.attach(rec)
      },
      fn(c : EmitterCall) -> UInt64 {
        match c {
          Emit(m) =>
            tracked.validate(
              EmitterCall::Emit(m),
              fn(x : Emitter) -> Unit { x.output.val.push(m) },
              hash_unit_value,
            )
        }
      },
      //| Replay: re-execute the recorded mutable call on the current value.
      fn(c : EmitterCall) -> Unit {
        match c {
          Emit(m) => {
            let x = tracked.get()
            x.output.val.push(m)
          }
        }
      },
      fn(prev : Recorder[EmitterCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() {
      emitter.emit(value)
      emitter.emit("1")
    },
  )
}

///|
test "purely_mutable" {
  let emitter : Emitter = { output: { val: Array::new() } }
  let e1 : EmitterTracked = EmitterTracked::new(emitter)
  reset_oracle()
  dump(e1, "a") // miss: emit(a), emit(1)
  if last_was_hit() {
    panic()
  }
  let e2 : EmitterTracked = EmitterTracked::new(emitter)
  reset_oracle()
  dump(e2, "b") // miss: emit(b), emit(1)
  if last_was_hit() {
    panic()
  }
  let e3 : EmitterTracked = EmitterTracked::new(emitter)
  reset_oracle()
  dump(e3, "c") // miss: emit(c), emit(1)
  if last_was_hit() {
    panic()
  }
  let e4 : EmitterTracked = EmitterTracked::new(emitter)
  reset_oracle()
  dump(e4, "a") // hit: replay emit(a), emit(1)
  if !last_was_hit() {
    panic()
  }
  let e5 : EmitterTracked = EmitterTracked::new(emitter)
  reset_oracle()
  dump(e5, "b") // hit: replay emit(b), emit(1)
  if !last_was_hit() {
    panic()
  }

  //| a,1,b,1,c,1,a,1,b,1 (same as Rust: 10 entries)
  let out = emitter.output.val
  if out.length() != 10 {
    panic()
  }
  if out[0] != "a" ||
    out[1] != "1" ||
    out[2] != "b" ||
    out[3] != "1" ||
    out[4] != "c" ||
    out[5] != "1" ||
    out[6] != "a" ||
    out[7] != "1" ||
    out[8] != "b" ||
    out[9] != "1" {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| Nested mutable replay (mirrors test_mutable_nested).
//| Top-level miss → inner memoized fn runs; top-level hit → inner mutable
//| calls replay without re-running the inner fn.
//| ---------------------------------------------------------------------------

///|
struct Counter {
  val : Ref[Int]
}

///|

///|
struct CounterTracked {
  t : Tracked[Counter, CounterCall]
}

///|
fn CounterTracked::new(value : Counter) -> CounterTracked {
  { t: Tracked::new(value) }
}

///|
fn CounterTracked::add(self : CounterTracked, n : Int) -> Unit {
  self.t.call_mut(
    CounterCall::Add(n),
    fn(x : Counter) -> Unit { x.val.val = x.val.val + n },
    hash_unit_value,
  )
}

///|
let b_cache : Cache[CounterCall, Unit] = Cache::new()

///|
fn b(counter : CounterTracked) -> Unit {
  let tracked = counter.t
  memoize(
    b_cache,
    Input::new(
      fn() { hash_unit() },
      fn(rec : Recorder[CounterCall]) -> Recorder[CounterCall]? {
        tracked.attach(rec)
      },
      fn(c : CounterCall) -> UInt64 {
        match c {
          Add(n) =>
            tracked.validate(
              CounterCall::Add(n),
              fn(x : Counter) -> Unit { x.val.val = x.val.val + n },
              hash_unit_value,
            )
        }
      },
      fn(c : CounterCall) -> Unit {
        //| Replay through the tracked value so the call propagates to any
        //| enclosing sink (mirrors Rust's TrackedMut::call_mut on replay).
        match c {
          Add(n) =>
            ignore(
              tracked.call_mut(
                CounterCall::Add(n),
                fn(x : Counter) -> Unit { x.val.val = x.val.val + n },
                hash_unit_value,
              ),
            )
        }
      },
      fn(prev : Recorder[CounterCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() { counter.add(3) },
  )
}

///|
let a_cache : Cache[CounterCall, Unit] = Cache::new()

///|
fn a(counter : CounterTracked, k : Int) -> Unit {
  let tracked = counter.t
  memoize(
    a_cache,
    Input::new(
      fn() { hash_int(k) },
      fn(rec : Recorder[CounterCall]) -> Recorder[CounterCall]? {
        tracked.attach(rec)
      },
      fn(c : CounterCall) -> UInt64 {
        match c {
          Add(n) =>
            tracked.validate(
              CounterCall::Add(n),
              fn(x : Counter) -> Unit { x.val.val = x.val.val + n },
              hash_unit_value,
            )
        }
      },
      fn(c : CounterCall) -> Unit {
        match c {
          Add(n) =>
            ignore(
              tracked.call_mut(
                CounterCall::Add(n),
                fn(x : Counter) -> Unit { x.val.val = x.val.val + n },
                hash_unit_value,
              ),
            )
        }
      },
      fn(prev : Recorder[CounterCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() { b(counter) },
  )
}

///|
test "mutable_nested" {
  //| c1: a(0) → miss → b miss → add(3)
  let c1 : Counter = { val: { val: 0 } }
  a(CounterTracked::new(c1), 0)
  println("c1=" + c1.val.val.to_string())
  if c1.val.val != 3 {
    panic()
  }

  //| c2: a(1) → miss → b miss → add(3)
  let c2 : Counter = { val: { val: 0 } }
  a(CounterTracked::new(c2), 1)
  println("c2=" + c2.val.val.to_string())
  if c2.val.val != 3 {
    panic()
  }

  //| c3: a(1) → hit → replay b's mutable → add(3)
  let c3 : Counter = { val: { val: 0 } }
  a(CounterTracked::new(c3), 1)
  println("c3=" + c3.val.val.to_string())
  if c3.val.val != 3 {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| Tracked chain (mirrors test_chain): a tracked value containing another
//| tracked value; `contains` recurses through the chain.
//| ---------------------------------------------------------------------------

///|
struct ChainNode {
  outer : ChainTracked?
  value : Int
}

///|

///|
struct ChainTracked {
  t : Tracked[ChainNode, ChainCall]
}

///|
fn ChainTracked::new(value : ChainNode) -> ChainTracked {
  { t: Tracked::new(value) }
}

///|
fn ChainTracked::contains(self : ChainTracked, v : Int) -> Bool {
  self.t.call(
    ChainCall::Contains(v),
    fn(x : ChainNode) -> Bool {
      if x.value == v {
        true
      } else {
        match x.outer {
          Some(outer) => outer.contains(v)
          None => false
        }
      }
    },
    test_hash_bool,
  )
}

///|
let chain_cache : Cache[ChainCall, Bool] = Cache::new()

///|
fn chain_process(chain : ChainTracked, value : Int) -> Bool {
  let tracked = chain.t
  memoize(
    chain_cache,
    Input::new(
      fn() { hash_int(value) },
      fn(rec : Recorder[ChainCall]) -> Recorder[ChainCall]? {
        tracked.attach(rec)
      },
      fn(c : ChainCall) -> UInt64 {
        match c {
          Contains(v) =>
            tracked.validate(
              ChainCall::Contains(v),
              fn(x : ChainNode) -> Bool {
                if x.value == v {
                  true
                } else {
                  match x.outer {
                    Some(outer) => outer.contains(v)
                    None => false
                  }
                }
              },
              test_hash_bool,
            )
        }
      },
      fn(_c : ChainCall) -> Unit { () },
      fn(prev : Recorder[ChainCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() { chain.contains(value) },
  )
}

///|
test "tracked_chain" {
  let chain1 : ChainTracked = ChainTracked::new({ outer: None, value: 1 })
  let chain12 : ChainTracked = ChainTracked::new({
    outer: Some(chain1),
    value: 2,
  })

  reset_oracle()
  if chain_process(chain1, 0) || last_was_hit() {
    panic()
  } // miss: false
  reset_oracle()
  if !chain_process(chain1, 1) || last_was_hit() {
    panic()
  } // miss: true
  reset_oracle()
  if !chain_process(chain12, 2) || last_was_hit() {
    panic()
  } // miss: true
  reset_oracle()
  if !chain_process(chain12, 2) || !last_was_hit() {
    panic()
  } // hit

  //| Different value through the chain → miss.
  reset_oracle()
  if chain_process(chain12, 3) || last_was_hit() {
    panic()
  } // miss: false
}

//| ---------------------------------------------------------------------------
//| Tracking through an interface (mirrors test_tracked_trait, adapted:
//| Rust uses `Tracked<dyn Loader>`, MoonBit uses a tracked interface type).
//| ---------------------------------------------------------------------------

///|
trait Loader {
  fn load(Self, path : String) -> Array[Int]
}

///|
struct StaticLoader {
  dummy : Int
}

///|
impl Loader for StaticLoader with fn load(self, _path) {
  [1, 2, 3]
}

///|
struct LoaderTracked[T] {
  t : Tracked[T, LoaderCall]
}

///|
fn[T] LoaderTracked::new(value : T) -> LoaderTracked[T] {
  { t: Tracked::new(value) }
}

///|
fn[T : Loader] LoaderTracked::load(
  self : LoaderTracked[T],
  path : String,
) -> Array[Int] {
  self.t.call(
    LoaderCall::Load(path),
    fn(l : T) -> Array[Int] { l.load(path) },
    fn(v : Array[Int]) -> UInt64 { test_hash_array(v, test_hash_int) },
  )
}

///|

///|
let trait_cache : Cache[LoaderCall, Array[Int]] = Cache::new()

///|
fn[T : Loader] traity(loader : LoaderTracked[T], path : String) -> Array[Int] {
  let tracked = loader.t
  memoize(
    trait_cache,
    Input::new(
      fn() { hash_string(path) },
      fn(rec : Recorder[LoaderCall]) -> Recorder[LoaderCall]? {
        tracked.attach(rec)
      },
      fn(c : LoaderCall) -> UInt64 {
        match c {
          Load(p) =>
            tracked.validate(
              LoaderCall::Load(p),
              fn(l : T) -> Array[Int] { l.load(p) },
              fn(v : Array[Int]) -> UInt64 { test_hash_array(v, test_hash_int) },
            )
        }
      },
      fn(_c : LoaderCall) -> Unit { () },
      fn(prev : Recorder[LoaderCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() { loader.load(path) },
  )
}

///|
test "tracked_trait_object" {
  let loader : LoaderTracked[StaticLoader] = LoaderTracked::new({ dummy: 0 })
  reset_oracle()
  if traity(loader, "hi.rs").length() != 3 || last_was_hit() {
    panic()
  } // miss
  reset_oracle()
  if traity(loader, "hi.rs").length() != 3 || !last_was_hit() {
    panic()
  } // hit
  reset_oracle()
  if traity(loader, "bye.rs").length() != 3 || last_was_hit() {
    panic()
  } // miss (different path)
}
