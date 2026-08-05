///| Phase 4 verification: the generated `FilesTracked` API (from

///| `user_tracked.mbt` + `comemo_gen.mbt`) makes calc-style tracked usage

///|
/// boilerplate-free — no manual Call enum, no manual surface methods.
let gen_eval_cache : Cache[FilesCall, Int] = Cache::new()

//| The oracle: replay a call on the tracked value. This is the one piece
//| that still needs the user's read semantics (the generator cannot know
//| what `Files::read` returns); the Phase 4 generator emits this wiring.

///|
fn gen_oracle(t : Tracked[Files, FilesCall], c : FilesCall) -> UInt64 {
  match c {
    Read(path) =>
      t.validate(
        FilesCall::Read(path),
        fn(f : Files) -> String { f.read(path) },
        test_hash_str,
      )
    Write(_, _) => hash_zero()
  }
}

///|
fn gen_evaluate(script : String, files : FilesTracked) -> Int {
  let tracked = files.t
  memoize(
    gen_eval_cache,
    Input::new(
      fn() { hash_string(script) },
      fn(rec : Recorder[FilesCall]) -> Recorder[FilesCall]? {
        tracked.attach(rec)
      },
      fn(c : FilesCall) -> UInt64 { gen_oracle(tracked, c) },
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
          total = total + gen_evaluate(files.read(path), files)
        } else {
          total = total + parse_ok(p)
        }
        i = i + 1
      }
      total
    },
  )
}

///|
test "generated_calc" {
  let files : Files = { map: @hashmap.HashMap([]) }
  files.write("alpha.calc", "2 + eval beta.calc")
  files.write("beta.calc", "2 + 3")

  //| Construct the surface wrapper — same as Rust's `files.track()`.
  let ft : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft) != 7 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if gen_evaluate("eval beta.calc", ft) != 5 || last_was_hit() {
    panic()
  }

  //| Unreferenced file change → hit. Re-wrap like Rust's `files.track()`.
  ft.t.value.val.write("gamma.calc", "42")
  let ft3 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft3) != 7 || !last_was_hit() {
    panic()
  }

  //| Referenced file change → miss.
  ft.t.value.val.write("beta.calc", "4 + eval gamma.calc")
  let ft4 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval beta.calc", ft4) != 46 || last_was_hit() {
    panic()
  }
  let ft5 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft5) != 48 || last_was_hit() {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| G1: two tracked parameters (mirrors Rust's Multi<(...)> for World+Traced).
//| ---------------------------------------------------------------------------

///|
struct G1World {
  data : String
}

///|
fn G1World::query(self : G1World, selector : String) -> Int {
  self.data.length() + selector.length()
}

///|
struct GTraced {
  span : Int
}

///|
fn GTraced::span(self : GTraced) -> Int {
  self.span
}

//| 用户侧 surface(生成器会产出;手写验证)

///|
struct G1WorldTracked {
  t : Tracked[G1World, WorldCall]
}

///|
fn G1WorldTracked::new(value : G1World) -> G1WorldTracked {
  { t: Tracked::new(value) }
}

///|
fn G1WorldTracked::query(self : G1WorldTracked, selector : String) -> Int {
  self.t.call(
    WorldCall::Query(selector),
    fn(w : G1World) -> Int { w.query(selector) },
    test_hash_int,
  )
}

///|
struct GTracedTracked {
  t : Tracked[GTraced, TracedCall]
}

///|
fn GTracedTracked::new(value : GTraced) -> GTracedTracked {
  { t: Tracked::new(value) }
}

///|
fn GTracedTracked::span(self : GTracedTracked) -> Int {
  self.t.call(
    TracedCall::Span,
    fn(x : GTraced) -> Int { x.span },
    test_hash_int,
  )
}

//| memoize 两个 tracked:用合并 Call 枚举

///|
let g_cache : Cache[WorldTracedCall, Int] = Cache::new()

///|
fn g_eval(world : G1WorldTracked, traced : GTracedTracked) -> Int {
  let wt = world.t
  let tt = traced.t
  memoize2(
    g_cache,
    Input2::new(
      fn() { hash_zero() },
      //| attach:两个 tracked 各接 recorder,返回组合 prev
      fn(
        rec : Recorder[WorldTracedCall],
      ) -> (Recorder[WorldCall]?, Recorder[TracedCall]?) {
        let p1 = wt.attach(fn(
          c : WorldCall,
          h : UInt64,
          ret : UInt64,
          m : Bool,
        ) -> Unit {
          rec(WorldTracedCall::W(c), h, ret, m)
        })
        let p2 = tt.attach(fn(
          c : TracedCall,
          h : UInt64,
          ret : UInt64,
          m : Bool,
        ) -> Unit {
          rec(WorldTracedCall::T(c), h, ret, m)
        })
        (p1, p2)
      },
      fn(c : WorldTracedCall) -> UInt64 {
        match c {
          W(wc) =>
            wt.validate(
              wc,
              fn(w : G1World) -> Int {
                match wc {
                  Query(s) => w.query(s)
                }
              },
              test_hash_int,
            )
          T(tc) =>
            tt.validate(
              tc,
              fn(x : GTraced) -> Int {
                match tc {
                  Span => x.span
                }
              },
              test_hash_int,
            )
        }
      },
      fn(_c : WorldTracedCall) -> Unit { () },
      fn(prev : (Recorder[WorldCall]?, Recorder[TracedCall]?)) -> Unit {
        let (p1, p2) = prev
        wt.detach(p1)
        tt.detach(p2)
      },
    ),
    true,
    fn() { world.query("sel") + traced.span() },
  )
}

///|
test "g1_two_tracked_params" {
  let w : G1WorldTracked = G1WorldTracked::new({ data: "world" })
  let t : GTracedTracked = GTracedTracked::new({ span: 10 })
  reset_oracle()
  let r1 = g_eval(w, t)
  //| query("sel") = data.len(5) + "sel".len(3) = 8; + span(10) = 18
  if r1 != 18 {
    panic()
  }
  if last_was_hit() {
    panic()
  } // miss

  reset_oracle()
  let r2 = g_eval(w, t)
  if r2 != r1 || !last_was_hit() {
    panic()
  } // hit

  //| 改 traced(仅第二个 tracked):第一个的查询缓存应保留,但整体 miss
  let t2 : GTracedTracked = GTracedTracked::new({ span: 20 })
  reset_oracle()
  let r3 = g_eval(w, t2)
  if r3 != 8 + 20 || last_was_hit() {
    panic()
  } // miss(span 变了)
}
