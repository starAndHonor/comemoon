///| Benchmark suite mirroring refs/comemo/examples/bench.rs (5 scenarios).

///| Run: moon bench --target native

///| Output scenario names match the Rust side for direct comparison.
///

///| Manual timing (moon's bench auto-iterates; we fix counts for parity).

///|
/// Wall-clock via env.now_internal() (nanoseconds on native).

//| Scenario 1+2: plain memoized fn on Int args.
let s12_cache : Cache[UnitCall, Int] = Cache::new()

///|
fn double(x : Int) -> Int {
  memoize_pure(s12_cache, hash_int(x), true, fn() { 2 * x })
}

//| Scenario 3: calc dependency graph with unrelated edits.

///|
let s3_cache : Cache[FilesCall, Int] = Cache::new()

///|

///|
/// Prebuilt input for the calc scenario: builds the closures once per
/// `s3_eval` call instead of inline at each `memoize` call site.
fn s3_input(tracked : Tracked[Files, FilesCall]) -> Input[FilesCall] {
  Input::new(
    fn() { hash_zero() },
    fn(rec : Recorder[FilesCall]) -> Recorder[FilesCall]? {
      tracked.attach(rec)
    },
    fn(c : FilesCall) -> UInt128 {
      match c {
        Read(path) =>
          tracked.validate(
            FilesCall::Read(path),
            fn(f : Files) -> String { f.read(path) },
            test_hash_str,
          )
        Write(_, _) => hash_zero()
      }
    },
    fn(_c : FilesCall) -> Unit { () },
    fn(prev : Recorder[FilesCall]?) -> Unit { tracked.detach(prev) },
  )
}

///|
fn s3_eval(script : String, files : FilesTracked) -> Int {
  let tracked = files.t
  memoize(s3_cache, s3_input(tracked), true, fn() {
    let mut total = 0
    let parts = script.split("+").to_array()
    let mut i = 0
    while i < parts.length() {
      let p = parts[i].trim().to_owned()
      if p.has_prefix("eval ") {
        let path = p[5:].to_owned()
        total = total + s3_eval(files.read(path), files)
      } else {
        total = total + parse_ok(p)
      }
      i = i + 1
    }
    total
  })
}

//| Scenario 4: 1000 same-key contexts validated twice.

///|
let s4_cache : Cache[FilesCall, Int] = Cache::new()

///|
fn s4_eval(script : String, files : FilesTracked) -> Int {
  let tracked = files.t
  memoize(
    s4_cache,
    Input::new(
      fn() { hash_string(script) },
      fn(rec : Recorder[FilesCall]) -> Recorder[FilesCall]? {
        tracked.attach(rec)
      },
      fn(c : FilesCall) -> UInt128 {
        match c {
          Read(path) =>
            tracked.validate(
              FilesCall::Read(path),
              fn(f : Files) -> String { f.read(path) },
              test_hash_str,
            )
          Write(_, _) => hash_zero()
        }
      },
      fn(_c : FilesCall) -> Unit { () },
      fn(prev : Recorder[FilesCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() {
      let parts = script.split("+").to_array()
      let mut i = 0
      let mut total = 0
      while i < parts.length() {
        total = total + parse_ok(parts[i].trim().to_owned())
        i = i + 1
      }
      total
    },
  )
}

//| Scenario 5: eviction cycle.

///|
let s5_cache : Cache[UnitCall, Int64] = Cache::new()

///|
fn poly(x : Int) -> Int64 {
  memoize_pure(s5_cache, hash_int(x), true, fn() {
    let v : Int64 = x.to_int64()
    v * v + 3 * v + 7
  })
}

///|
test (b : @bench.T) {
  //| S1: cold-ish (new arg each call)
  let mut seed : Int = 0x12345678
  b.bench(
    fn() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
      b.keep(double(0xDEAD + seed % 1000))
    },
    count=10,
  )
}

///|
test (b : @bench.T) {
  //| S2: warm hits
  b.bench(fn() { b.keep(double(42)) }, count=10)
}

///|
test (b : @bench.T) {
  //| S3: calc with unrelated edits
  let files : Files = { map: @hashmap.HashMap([]) }
  files.write("a.calc", "1 + eval b.calc")
  files.write("b.calc", "2 + 3")
  files.write("c.calc", "8 + 3")
  let mut i = 0
  b.bench(
    fn() {
      files.write("c.calc", (i % 100).to_string() + " + 3")
      i = i + 1
      let ft : FilesTracked = FilesTracked::new(files)
      b.keep(s3_eval("eval a.calc", ft))
    },
    count=10,
  )
}

///|
test (b : @bench.T) {
  //| S4: single evaluate on a fresh context (accelerator makes repeats cheap).
  //| Rust side does 2000 evaluates; moon bench auto-iterates this closure.
  let files : Files = { map: @hashmap.HashMap([]) }
  files.write("x.calc", "42")
  let ft : FilesTracked = FilesTracked::new(files)
  b.bench(fn() { b.keep(s4_eval("eval x.calc", ft)) }, count=10)
}

///|
test (b : @bench.T) {
  //| S5: single eviction cycle (100 inserts + evict)
  b.bench(
    fn() {
      let mut acc : Int64 = 0
      let mut k = 0
      while k < 100 {
        acc = acc + poly(k)
        k = k + 1
      }
      evict(10)
      b.keep(acc)
    },
    count=10,
  )
}

//| Scenario 6: TrackedMut — mutable calls replayed on hit (miss path:
//| key increments each round, so every round inserts).

///|
let s6_cache : Cache[G4CounterCall, Int] = Cache::new()

///|
fn s6_eval(n : Int, counter : TrackedMut[G4Counter, G4CounterCall]) -> Int {
  let st = counter
  memoize(
    s6_cache,
    Input::new(
      fn() { hash_int(n) },
      fn(rec : Recorder[G4CounterCall]) -> Recorder[G4CounterCall]? {
        st.attach(rec)
      },
      fn(call : G4CounterCall) -> UInt128 {
        match call {
          Add(nn) =>
            st.validate(
              G4CounterCall::Add(nn),
              fn(s : G4Counter) -> Unit { s.add(nn) },
              hash_unit_value,
            )
          Count =>
            st.validate(
              G4CounterCall::Count,
              fn(s : G4Counter) -> Int { s.count() },
              hash_int,
            )
        }
      },
      fn(call : G4CounterCall) -> Unit {
        match call {
          Add(nn) =>
            st.call_mut(
              G4CounterCall::Add(nn),
              fn(s : G4Counter) -> Unit { s.add(nn) },
              hash_unit_value,
            )
          Count => ()
        }
      },
      fn(prev : Recorder[G4CounterCall]?) -> Unit { st.detach(prev) },
    ),
    true,
    fn() {
      st.call_mut(
        G4CounterCall::Add(n),
        fn(s : G4Counter) -> Unit { s.add(n) },
        hash_unit_value,
      )
      n
    },
  )
}

///|
test (b : @bench.T) {
  let mut c : G4Counter = { total: 0 }
  let mut i = 0
  let tm : TrackedMut[G4Counter, G4CounterCall] = TrackedMut::new(c)
  b.bench(
    fn() {
      c = { total: i }
      i = i + 1
      let tmr = tm.reborrow_mut()
      b.keep(s6_eval(1, tmr))
    },
    count=10,
  )
}

//| Scenario 7: 5 tracked params (bundle_impl pattern), miss path.

///|
let s7_cache : Cache[BundleCall, Int] = Cache::new()

///|

///|
/// Prebuilt 5-param input: `w`/`i`/`t`/`r`/`s` are stable across rounds in
/// the benchmark, so the closures are built once per `s7_eval` call
/// instead of inline at each `memoize5` call site.
fn s7_input(
  w : Tracked[G5World, BundleCall],
  i : Tracked[G5Intro, BundleCall],
  t : Tracked[G5Traced, BundleCall],
  r : Tracked[G5Route, BundleCall],
  s : TrackedMut[G5Sink, BundleCall],
) -> Input5[
  BundleCall,
  BundleCall,
  BundleCall,
  BundleCall,
  BundleCall,
  BundleCall,
] {
  Input5::new(
    fn() { hash_zero() },
    fn(
      rec : Recorder[BundleCall],
    ) -> (
      Recorder[BundleCall]?,
      Recorder[BundleCall]?,
      Recorder[BundleCall]?,
      Recorder[BundleCall]?,
      Recorder[BundleCall]?,
    ) {
      (
        w.attach(rec),
        i.attach(rec),
        t.attach(rec),
        r.attach(rec),
        s.attach(rec),
      )
    },
    fn(call : BundleCall) -> UInt128 {
      match call {
        WorldQuery(kk) =>
          w.validate(
            BundleCall::WorldQuery(kk),
            fn(x : G5World) -> Int { x.query(kk) },
            hash_int,
          )
        IntroQuery(kk) =>
          i.validate(
            BundleCall::IntroQuery(kk),
            fn(x : G5Intro) -> Int { x.query(kk) },
            hash_int,
          )
        TracedPush(kk) =>
          t.validate(
            BundleCall::TracedPush(kk),
            fn(x : G5Traced) -> Int { x.push(kk) },
            hash_int,
          )
        RouteResolve(kk) =>
          r.validate(
            BundleCall::RouteResolve(kk),
            fn(x : G5Route) -> Int { x.resolve(kk) },
            hash_int,
          )
        SinkPush(kk) =>
          s.validate(
            BundleCall::SinkPush(kk),
            fn(x : G5Sink) -> Unit { x.push(kk) },
            hash_unit_value,
          )
      }
    },
    fn(call : BundleCall) -> Unit {
      match call {
        SinkPush(kk) =>
          s.call_mut(
            BundleCall::SinkPush(kk),
            fn(x : G5Sink) -> Unit { x.push(kk) },
            hash_unit_value,
          )
        _ => ()
      }
    },
    fn(
      prev : (
        Recorder[BundleCall]?,
        Recorder[BundleCall]?,
        Recorder[BundleCall]?,
        Recorder[BundleCall]?,
        Recorder[BundleCall]?,
      ),
    ) -> Unit {
      w.detach(prev.0)
      i.detach(prev.1)
      t.detach(prev.2)
      r.detach(prev.3)
      s.detach(prev.4)
    },
  )
}

///|
fn s7_eval(
  w : Tracked[G5World, BundleCall],
  i : Tracked[G5Intro, BundleCall],
  t : Tracked[G5Traced, BundleCall],
  r : Tracked[G5Route, BundleCall],
  s : TrackedMut[G5Sink, BundleCall],
  k : Int,
) -> Int {
  memoize5(s7_cache, s7_input(w, i, t, r, s), true, fn() {
    s.call_mut(
      BundleCall::SinkPush(k),
      fn(x : G5Sink) -> Unit { x.push(k) },
      hash_unit_value,
    )
    w.call(
      BundleCall::WorldQuery(k),
      fn(x : G5World) -> Int { x.query(k) },
      hash_int,
    ) +
    i.call(
      BundleCall::IntroQuery(k),
      fn(x : G5Intro) -> Int { x.query(k) },
      hash_int,
    ) +
    t.call(
      BundleCall::TracedPush(k),
      fn(x : G5Traced) -> Int { x.push(k) },
      hash_int,
    ) +
    r.call(
      BundleCall::RouteResolve(k),
      fn(x : G5Route) -> Int { x.resolve(k) },
      hash_int,
    )
  })
}

///|
test (b : @bench.T) {
  let w : Tracked[G5World, BundleCall] = Tracked::new({ data: "W" })
  let i : Tracked[G5Intro, BundleCall] = Tracked::new({ data: "I" })
  let t : Tracked[G5Traced, BundleCall] = Tracked::new({ data: "T" })
  let r : Tracked[G5Route, BundleCall] = Tracked::new({ data: "R" })
  let s : TrackedMut[G5Sink, BundleCall] = TrackedMut::new({ buf: 0 })
  let mut k = 0
  b.bench(
    fn() {
      k = k + 1
      b.keep(s7_eval(w, i, t, r, s, k))
    },
    count=10,
  )
}
