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
      fn(c : GWorldCall) -> UInt128 {
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
