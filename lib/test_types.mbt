///| Test-only tracked types (enums + their RustHashable impls).

///| Defined in the main package because MoonBit test files (separate

///|
/// compilation units) cannot impl custom traits.
pub(all) enum CtxCall {
  Location
  Styles
} derive(Hash, Eq)

///|
pub impl RustHashable for CtxCall with fn write_rust(self, bytes) {
  match self {
    Location => append_u64_le(bytes, 0)
    Styles => append_u64_le(bytes, 1)
  }
}

///|
pub(all) enum OOCall {
  OOLocation
  OOStyles
} derive(Hash, Eq)

///|
pub impl RustHashable for OOCall with fn write_rust(self, bytes) {
  match self {
    OOLocation => append_u64_le(bytes, 0)
    OOStyles => append_u64_le(bytes, 1)
  }
}

///|
pub(all) enum TesterCall {
  SelfRef
  ByValue(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for TesterCall with fn write_rust(self, bytes) {
  match self {
    SelfRef => append_u64_le(bytes, 0)
    ByValue(h) => {
      append_u64_le(bytes, 1)
      write_rust_string(bytes, h)
    }
  }
}

///|
pub(all) enum EmitterCall {
  Emit(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for EmitterCall with fn write_rust(self, bytes) {
  match self {
    Emit(m) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, m)
    }
  }
}

///|
pub(all) enum CounterCall {
  Add(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for CounterCall with fn write_rust(self, bytes) {
  match self {
    Add(n) => {
      append_u64_le(bytes, 0)
      append_i64_le(bytes, n.to_int64())
    }
  }
}

///|
pub(all) enum ChainCall {
  Contains(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for ChainCall with fn write_rust(self, bytes) {
  match self {
    Contains(v) => {
      append_u64_le(bytes, 0)
      append_i64_le(bytes, v.to_int64())
    }
  }
}

///|
pub(all) enum LoaderCall {
  Load(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for LoaderCall with fn write_rust(self, bytes) {
  match self {
    Load(p) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, p)
    }
  }
}

///|
/// Call type wrapping an Int (for CallSequence unit tests).
pub(all) enum IntCall {
  I(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for IntCall with fn write_rust(self, bytes) {
  match self {
    I(v) => append_i64_le(bytes, v.to_int64())
  }
}

///|
/// Call type wrapping a String (for CallTree unit tests).
pub(all) enum StrCall {
  S(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for StrCall with fn write_rust(self, bytes) {
  match self {
    S(v) => write_rust_string(bytes, v)
  }
}

//| G1 验证:两个 tracked 参数的合并 Call 枚举(模拟 Typst World+Traced)

///|
pub(all) enum WorldCall {
  Query(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for WorldCall with fn write_rust(self, bytes) {
  match self {
    Query(s) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, s)
    }
  }
}

///|
pub(all) enum TracedCall {
  Span
} derive(Hash, Eq)

///|
pub impl RustHashable for TracedCall with fn write_rust(self, bytes) {
  match self {
    Span => append_u64_le(bytes, 0)
  }
}

///|
/// 合并枚举:每个 tracked 参数一个变体,包装其 Call
pub(all) enum WorldTracedCall {
  W(WorldCall)
  T(TracedCall)
} derive(Hash, Eq)

///|
pub impl RustHashable for WorldTracedCall with fn write_rust(self, bytes) {
  match self {
    W(c) => {
      append_u64_le(bytes, 0)
      c.write_rust(bytes)
    }
    T(c) => {
      append_u64_le(bytes, 1)
      c.write_rust(bytes)
    }
  }
}

//| ---------------------------------------------------------------------------
//| G2: trait track(泛型 surface,镜像 Typst 的 `#[track] trait World`)
//| ---------------------------------------------------------------------------

///|
/// 被跟踪的 trait(Typst 的 World 简化版)
pub trait GWorld {
  fn query(Self, selector : String) -> Int
  fn font(Self) -> Int
}

///|
/// 该 trait 的 Call 枚举(生成器会产出)
pub(all) enum GWorldCall {
  Query(String)
  Font
} derive(Hash, Eq)

///|
pub impl RustHashable for GWorldCall with fn write_rust(self, bytes) {
  match self {
    Query(s) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, s)
    }
    Font => append_u64_le(bytes, 1)
  }
}

///|
/// 泛型 surface:任何实现 GWorld 的类型都可被跟踪(生成器会产出)
pub(all) struct GWorldTracked[T] {
  t : Tracked[T, GWorldCall]
}

///|
pub fn[T] GWorldTracked::new(value : T) -> GWorldTracked[T] {
  { t: Tracked::new(value) }
}

///|
pub fn[T : GWorld] GWorldTracked::query(
  self : GWorldTracked[T],
  selector : String,
) -> Int {
  self.t.call(
    GWorldCall::Query(selector),
    fn(w : T) -> Int { GWorld::query(w, selector) },
    test_hash_int,
  )
}

///|
pub fn[T : GWorld] GWorldTracked::font(self : GWorldTracked[T]) -> Int {
  self.t.call(
    GWorldCall::Font,
    fn(w : T) -> Int { GWorld::font(w) },
    test_hash_int,
  )
}

///|
/// 两个具体实现
pub struct GRealWorld {
  data : String
}

///|
impl GWorld for GRealWorld with fn query(self, selector) {
  self.data.length() + selector.length()
}

///|
impl GWorld for GRealWorld with fn font(self) {
  self.data.length()
}

///|
pub struct GFakeWorld {
  n : Int
}

///|
impl GWorld for GFakeWorld with fn query(self, selector) {
  self.n + selector.length()
}

///|
impl GWorld for GFakeWorld with fn font(self) {
  self.n
}

//| G2 测试(同文件定义 trait,避免跨包约束问题)

///|
let g2_cache : Cache[GWorldCall, Int] = Cache::new()

///|
fn[T : GWorld] g2_eval_internal(
  world : GWorldTracked[T],
  script : String,
) -> Int {
  let wt = world.t
  memoize(
    g2_cache,
    Input::new(
      fn() { hash_string(script) },
      fn(rec : Recorder[GWorldCall]) -> Recorder[GWorldCall]? { wt.attach(rec) },
      fn(c : GWorldCall) -> UInt64 {
        match c {
          Query(s) =>
            wt.validate(
              GWorldCall::Query(s),
              fn(w : T) -> Int { GWorld::query(w, s) },
              test_hash_int,
            )
          Font =>
            wt.validate(
              GWorldCall::Font,
              fn(w : T) -> Int { GWorld::font(w) },
              test_hash_int,
            )
        }
      },
      fn(_c : GWorldCall) -> Unit { () },
      fn(prev : Recorder[GWorldCall]?) -> Unit { wt.detach(prev) },
    ),
    true,
    fn() { world.query("sel") + world.font() },
  )
}

///|
test "g2_trait_track" {
  let rw : GWorldTracked[GRealWorld] = GWorldTracked::new({ data: "abc" })
  reset_oracle()
  let r1 = g2_eval_internal(rw, "s")
  if r1 != 9 || last_was_hit() {
    panic()
  } // query=3+3=6, font=3 → 9, miss
  reset_oracle()
  if g2_eval_internal(rw, "s") != 9 || !last_was_hit() {
    panic()
  } // hit

  let fw : GWorldTracked[GFakeWorld] = GWorldTracked::new({ n: 5 })
  reset_oracle()
  if g2_eval_internal(fw, "s") != 13 || last_was_hit() {
    panic()
  } // query=5+3=8, font=5 → 13, miss
  reset_oracle()
  if g2_eval_internal(fw, "s") != 13 || !last_was_hit() {
    panic()
  } // hit
}

//| ---------------------------------------------------------------------------
//| G4: TrackedMut 语义测试
//| ---------------------------------------------------------------------------

///|
let g4_cache : Cache[G4CounterCall, Int] = Cache::new()

///|
fn g4_eval(c : TrackedMut[G4Counter, G4CounterCall], n : Int) -> Int {
  let st = c
  memoize(
    g4_cache,
    Input::new(
      fn() { hash_int(n) },
      fn(rec : Recorder[G4CounterCall]) -> Recorder[G4CounterCall]? {
        st.attach(rec)
      },
      fn(call : G4CounterCall) -> UInt64 {
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
      st.call(
        G4CounterCall::Count,
        fn(s : G4Counter) -> Int { s.count() },
        hash_int,
      )
    },
  )
}

///|
test "g4_trackedmut_mutable_replay" {
  let c : TrackedMut[G4Counter, G4CounterCall] = TrackedMut::new({ total: 0 })
  //| miss:func 执行 Add(5) → total=5,output=5(Count 返回值)
  let r1 = g4_eval(c, 5)
  if r1 != 5 || c.get().total != 5 {
    panic()
  }
  //| hit:mutable 重放 Add(5) → total=10,output 是缓存的 5
  let r2 = g4_eval(c, 5)
  if r2 != 5 || c.get().total != 10 {
    panic()
  }
  //| downgrade 共享同一值
  let d = c.downgrade()
  if d.get().total != 10 {
    panic()
  }
  //| 改参数:miss,执行 Add(3) → total=13,output=13
  let r3 = g4_eval(c, 3)
  if r3 != 13 || c.get().total != 13 {
    panic()
  }
}

///|
test "g4_trackedmut_downgrade_shared" {
  let c : TrackedMut[G4Counter, G4CounterCall] = TrackedMut::new({ total: 1 })
  let d = c.downgrade()
  d.get().total = 99
  if c.get().total != 99 {
    panic()
  }
}

///|
test "g5_memoize5_bundle_impl" {
  let w : Tracked[G5World, BundleCall] = Tracked::new({ data: "W" })
  let i : Tracked[G5Intro, BundleCall] = Tracked::new({ data: "I" })
  let t : Tracked[G5Traced, BundleCall] = Tracked::new({ data: "T" })
  let r : Tracked[G5Route, BundleCall] = Tracked::new({ data: "R" })
  let s : TrackedMut[G5Sink, BundleCall] = TrackedMut::new({ buf: 0 })
  //| miss:5 个调用都执行,W5+I5+T5+R5+out,sink buf = "5"
  //| data len=1, query=1+5=6 → 4 个 = 24;sink buf = "5"
  let r1 = g5_eval(w, i, t, r, s, 5)
  if r1 != 24 || s.get().buf != 5 {
    panic()
  }
  //| hit:mutable(SinkPush) 重放 → buf = 10,output 缓存
  let r2 = g5_eval(w, i, t, r, s, 5)
  if r2 != 24 || s.get().buf != 10 {
    panic()
  }
  //| 改参数:miss,query=1+9=10 → 4 个 = 40
  let r3 = g5_eval(w, i, t, r, s, 9)
  if r3 != 40 || s.get().buf != 19 {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| G6: dyn World 等价 —— 泛型 surface + 泛型 compile 函数(运行时多态)
//| ---------------------------------------------------------------------------

//| 两个不同的 World 实现(等价 Rust 传不同 &dyn World)

///|
struct G6RealWorld {
  data : String
}

///|
struct G6FakeWorld {
  data : String
}

///|
impl GWorld for G6RealWorld with fn query(self, sel) {
  self.data.length() + sel.length()
}

///|
impl GWorld for G6RealWorld with fn font(self) {
  2
}

///|
impl GWorld for G6FakeWorld with fn query(self, sel) {
  sel.length() * 10
}

///|
impl GWorld for G6FakeWorld with fn font(self) {
  1
}

//| 泛型 compile:等价 `compile(world: Tracked<dyn World>)` —— 任意实现

///|
fn[W : GWorld] g6_compile(world : GWorldTracked[W], script : String) -> Int {
  let st = world.t
  let cache : Cache[GWorldCall, Int] = Cache::new()
  memoize(
    cache,
    Input::new(
      fn() { hash_string(script) },
      fn(rec : Recorder[GWorldCall]) -> Recorder[GWorldCall]? { st.attach(rec) },
      fn(call : GWorldCall) -> UInt64 {
        match call {
          Query(sel) =>
            st.validate(
              GWorldCall::Query(sel),
              fn(v : W) -> Int { GWorld::query(v, sel) },
              hash_int,
            )
          Font =>
            st.validate(
              GWorldCall::Font,
              fn(v : W) -> Int { GWorld::font(v) },
              hash_int,
            )
        }
      },
      fn(_c : GWorldCall) -> Unit { () },
      fn(prev : Recorder[GWorldCall]?) -> Unit { st.detach(prev) },
    ),
    true,
    fn() {
      st.call(
        GWorldCall::Query(script),
        fn(v : W) -> Int { GWorld::query(v, script) },
        hash_int,
      ) +
      st.call(GWorldCall::Font, fn(v : W) -> Int { GWorld::font(v) }, hash_int)
    },
  )
}

///|
test "g6_dyn_world_polymorphism" {
  //| 真实 World:query = 4+3=7, font = 2 → 9
  let real : GWorldTracked[G6RealWorld] = GWorldTracked::new({ data: "real" })
  let r1 = g6_compile(real, "doc")
  if r1 != 9 {
    panic()
  }
  //| Fake World(测试用)——同一泛型函数,不同实现:query = 30, font = 1 → 31
  let fake : GWorldTracked[G6FakeWorld] = GWorldTracked::new({ data: "fake" })
  let r2 = g6_compile(fake, "doc")
  if r2 != 31 {
    panic()
  }
  //| 同一 World 再次编译:hit
  let r3 = g6_compile(real, "doc")
  if r3 != 9 {
    panic()
  }
}

//| ---------------------------------------------------------------------------
//| G7: 6 参数 memoize(eval_closure 模式:5 Tracked + 1 TrackedMut)
//| ---------------------------------------------------------------------------

///|
pub(all) enum SixCall {
  Ctx(String)
  Route(String)
  Traced(String)
  Intro(String)
  World(String)
  SinkAdd(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for SixCall with fn write_rust(self, bytes) {
  match self {
    Ctx(k) => {
      write_rust_u64(bytes, 0)
      write_rust_string(bytes, k)
    }
    Route(k) => {
      write_rust_u64(bytes, 1)
      write_rust_string(bytes, k)
    }
    Traced(k) => {
      write_rust_u64(bytes, 2)
      write_rust_string(bytes, k)
    }
    Intro(k) => {
      write_rust_u64(bytes, 3)
      write_rust_string(bytes, k)
    }
    World(k) => {
      write_rust_u64(bytes, 4)
      write_rust_string(bytes, k)
    }
    SinkAdd(k) => {
      write_rust_u64(bytes, 5)
      write_rust_string(bytes, k)
    }
  }
}

///|
struct G7Ctx {
  v : Int
}

///|
struct G7Route {
  v : Int
}

///|
struct G7Traced {
  v : Int
}

///|
struct G7Intro {
  v : Int
}

///|
struct G7World {
  v : Int
}

///|
struct G7Sink {
  mut acc : Int
}

///|
fn G7Ctx::get(self : G7Ctx, k : String) -> Int {
  self.v + k.length()
}

///|
fn G7Route::get(self : G7Route, k : String) -> Int {
  self.v + k.length()
}

///|
fn G7Traced::get(self : G7Traced, k : String) -> Int {
  self.v + k.length()
}

///|
fn G7Intro::get(self : G7Intro, k : String) -> Int {
  self.v + k.length()
}

///|
fn G7World::get(self : G7World, k : String) -> Int {
  self.v + k.length()
}

///|
fn G7Sink::add(self : G7Sink, k : String) -> Unit {
  self.acc = self.acc + k.length()
}

///|
let g7_cache : Cache[SixCall, Int] = Cache::new()

///|
fn g7_eval(
  ctx : Tracked[G7Ctx, SixCall],
  route : Tracked[G7Route, SixCall],
  traced : Tracked[G7Traced, SixCall],
  intro : Tracked[G7Intro, SixCall],
  world : Tracked[G7World, SixCall],
  sink : TrackedMut[G7Sink, SixCall],
  k : String,
) -> Int {
  memoize6(
    g7_cache,
    Input6::new(
      fn() { hash_string(k) },
      fn(
        rec : Recorder[SixCall],
      ) -> (
        Recorder[SixCall]?,
        Recorder[SixCall]?,
        Recorder[SixCall]?,
        Recorder[SixCall]?,
        Recorder[SixCall]?,
        Recorder[SixCall]?,
      ) {
        (
          ctx.attach(rec),
          route.attach(rec),
          traced.attach(rec),
          intro.attach(rec),
          world.attach(rec),
          sink.attach(rec),
        )
      },
      fn(call : SixCall) -> UInt64 {
        match call {
          Ctx(kk) =>
            ctx.validate(
              SixCall::Ctx(kk),
              fn(x : G7Ctx) -> Int { x.get(kk) },
              hash_int,
            )
          Route(kk) =>
            route.validate(
              SixCall::Route(kk),
              fn(x : G7Route) -> Int { x.get(kk) },
              hash_int,
            )
          Traced(kk) =>
            traced.validate(
              SixCall::Traced(kk),
              fn(x : G7Traced) -> Int { x.get(kk) },
              hash_int,
            )
          Intro(kk) =>
            intro.validate(
              SixCall::Intro(kk),
              fn(x : G7Intro) -> Int { x.get(kk) },
              hash_int,
            )
          World(kk) =>
            world.validate(
              SixCall::World(kk),
              fn(x : G7World) -> Int { x.get(kk) },
              hash_int,
            )
          SinkAdd(kk) =>
            sink.validate(
              SixCall::SinkAdd(kk),
              fn(x : G7Sink) -> Unit { x.add(kk) },
              hash_unit_value,
            )
        }
      },
      fn(call : SixCall) -> Unit {
        match call {
          SinkAdd(kk) =>
            sink.call_mut(
              SixCall::SinkAdd(kk),
              fn(x : G7Sink) -> Unit { x.add(kk) },
              hash_unit_value,
            )
          _ => ()
        }
      },
      fn(
        prev : (
          Recorder[SixCall]?,
          Recorder[SixCall]?,
          Recorder[SixCall]?,
          Recorder[SixCall]?,
          Recorder[SixCall]?,
          Recorder[SixCall]?,
        ),
      ) -> Unit {
        ctx.detach(prev.0)
        route.detach(prev.1)
        traced.detach(prev.2)
        intro.detach(prev.3)
        world.detach(prev.4)
        sink.detach(prev.5)
      },
    ),
    true,
    fn() {
      sink.call_mut(
        SixCall::SinkAdd(k),
        fn(x : G7Sink) -> Unit { x.add(k) },
        hash_unit_value,
      )
      ctx.call(SixCall::Ctx(k), fn(x : G7Ctx) -> Int { x.get(k) }, hash_int) +
      route.call(
        SixCall::Route(k),
        fn(x : G7Route) -> Int { x.get(k) },
        hash_int,
      ) +
      traced.call(
        SixCall::Traced(k),
        fn(x : G7Traced) -> Int { x.get(k) },
        hash_int,
      ) +
      intro.call(
        SixCall::Intro(k),
        fn(x : G7Intro) -> Int { x.get(k) },
        hash_int,
      ) +
      world.call(
        SixCall::World(k),
        fn(x : G7World) -> Int { x.get(k) },
        hash_int,
      )
    },
  )
}

///|
test "g7_memoize6_eval_closure" {
  let ctx : Tracked[G7Ctx, SixCall] = Tracked::new({ v: 1 })
  let route : Tracked[G7Route, SixCall] = Tracked::new({ v: 2 })
  let traced : Tracked[G7Traced, SixCall] = Tracked::new({ v: 3 })
  let intro : Tracked[G7Intro, SixCall] = Tracked::new({ v: 4 })
  let world : Tracked[G7World, SixCall] = Tracked::new({ v: 5 })
  let sink : TrackedMut[G7Sink, SixCall] = TrackedMut::new({ acc: 0 })
  //| miss:每个 get = v + len("ab")=v+2 → 3+4+5+6+7=25;sink acc = 2
  let r1 = g7_eval(ctx, route, traced, intro, world, sink, "ab")
  if r1 != 25 || sink.get().acc != 2 {
    panic()
  }
  //| hit:mutable 重放 SinkAdd → acc = 4,output 缓存 25
  let r2 = g7_eval(ctx, route, traced, intro, world, sink, "ab")
  if r2 != 25 || sink.get().acc != 4 {
    panic()
  }
  //| 改参数:miss
  let r3 = g7_eval(ctx, route, traced, intro, world, sink, "abc")
  if r3 != 30 || sink.get().acc != 7 {
    panic()
  }
}
