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
fn s3_eval(script : String, files : FilesTracked) -> Int {
  let tracked = files.t
  memoize(
    s3_cache,
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
    },
  )
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
