///| Shared types for the 5-param benchmark and test (non-test file so both

///| `_test` and `_wbtest` files can reference them).

//| ---------------------------------------------------------------------------
//| G5: 5 参数 memoize(bundle_impl 模式:4 Tracked + 1 TrackedMut)
//| ---------------------------------------------------------------------------

//| 合并 Call 枚举:所有参数的调用统一路由

///|
pub(all) enum BundleCall {
  WorldQuery(Int)
  IntroQuery(Int)
  TracedPush(Int)
  RouteResolve(Int)
  SinkPush(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for BundleCall with fn write_rust(self, bytes) {
  match self {
    WorldQuery(k) => {
      append_u64_le(bytes, 0)
      write_rust_int(bytes, k)
    }
    IntroQuery(k) => {
      append_u64_le(bytes, 1)
      write_rust_int(bytes, k)
    }
    TracedPush(k) => {
      append_u64_le(bytes, 2)
      write_rust_int(bytes, k)
    }
    RouteResolve(k) => {
      append_u64_le(bytes, 3)
      write_rust_int(bytes, k)
    }
    SinkPush(k) => {
      append_u64_le(bytes, 4)
      write_rust_int(bytes, k)
    }
  }
}

//| 5 个 tracked 参数:world/introspector/traced/route 是 Tracked,sink 是 TrackedMut

///|
pub(all) struct G5World {
  data : String
}

///|
pub(all) struct G5Intro {
  data : String
}

///|
pub(all) struct G5Traced {
  data : String
}

///|
pub(all) struct G5Route {
  data : String
}

///|
pub(all) struct G5Sink {
  mut buf : Int
}

///|
fn G5World::query(self : G5World, k : Int) -> Int {
  self.data.length() + k
}

///|
fn G5Intro::query(self : G5Intro, k : Int) -> Int {
  self.data.length() + k
}

///|
fn G5Traced::push(self : G5Traced, k : Int) -> Int {
  self.data.length() + k
}

///|
fn G5Route::resolve(self : G5Route, k : Int) -> Int {
  self.data.length() + k
}

///|
fn G5Sink::push(self : G5Sink, k : Int) -> Unit {
  self.buf = self.buf + k
}

///|
let g5_cache : Cache[BundleCall, Int] = Cache::new()

///|
pub fn g5_eval(
  w : Tracked[G5World, BundleCall],
  i : Tracked[G5Intro, BundleCall],
  t : Tracked[G5Traced, BundleCall],
  r : Tracked[G5Route, BundleCall],
  s : TrackedMut[G5Sink, BundleCall],
  k : Int,
) -> Int {
  memoize5(
    g5_cache,
    Input5::new(
      fn() { hash_int(k) },
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
      fn(call : BundleCall) -> UInt64 {
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
    ),
    true,
    fn() {
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
    },
  )
}

///|
