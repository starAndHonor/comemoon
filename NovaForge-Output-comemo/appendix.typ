// 附录：关键类型速查表与术语表
#import "preamble.typ": *

= 附录 A：关键类型与函数速查表

== A.1 公开 API（用户侧）

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*名称*], [*位置*], [*作用*],
  [`#[memoize]`], [#src[macros/src/lib.rs:133]], [属性宏：把函数包装为受约束记忆化函数；支持 `enabled = <expr>`],
  [`#[track]`], [#src[macros/src/lib.rs:211]], [属性宏：为 impl 块/trait 实现 `Track`，使方法调用可被跟踪],
  [`Tracked<'a, T>`], [#src[src/track.rs:162]], [不可变跟踪容器，`Deref` 到宏生成的 surface 类型],
  [`TrackedMut<'a, T>`], [#src[src/track.rs:223]], [可变跟踪容器，命中时变更被重放],
  [`Track` trait], [#src[src/track.rs:12]], [`track()` / `track_mut()` / `track_with()` / `track_mut_with()`],
  [`Constraint<C>`], [#src[src/constraint.rs:16]], [约束：记录一次执行的调用序列，`validate` 验证是否仍成立],
  [`evict(max_age)`], [#src[src/memoize.rs:101]], [全局缓存驱逐：清除 age 超过 `max_age` 的条目；`evict(0)` 全清],
  [`testing::last_was_hit()`], [#src[src/testing.rs:9]], [测试断言入口（需 `testing` feature）],
)

== A.2 运行时核心（internal）

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*名称*], [*位置*], [*作用*],
  [`memoize()`], [#src[src/memoize.rs:17]], [主调度：旁路 → key 哈希 → lookup/重放 → attach/执行 → insert],
  [`Cache<C, Out>`], [#src[src/memoize.rs:114]], [单函数缓存：`LazyLock<RwLock<CacheData>>`，`const fn new`],
  [`CacheEntry`], [#src[src/memoize.rs:137]], [output + 待重放 mutable 调用 + age（AtomicUsize）],
  [`register_evictor`], [#src[src/memoize.rs:109]], [宏生成代码把每个 Cache 的 evictor 注册进全局表],
  [`CallTree<C, T>`], [#src[src/tree.rs:15]], [四表结构：inner/leaves Slab + start/edges FxHashMap],
  [`CallTree::get / insert / retain`], [#src[src/tree.rs:57 / :80 / :158]], [oracle 重放查询 / 前缀对齐插入 / 自叶向根剪枝],
  [`NodeId(isize)`], [#src[src/tree.rs:234]], [非负=inner 下标，负=`~i`=leaf 下标],
  [`InsertError`], [#src[src/tree.rs:264]], [`AlreadyExists` / `MissingCall`（非确定性信号）],
  [`CallSequence<C>`], [#src[src/constraint.rs:82]], [去重调用序列：vec + map + cursor；`insert`/`next`/`extract`],
  [`Input<'a>` trait], [#src[src/input.rs:13]], [输入抽象：Call/Storage/key/call/call_mut/attach 五件套],
  [`MergedSink`], [#src[src/input.rs:156]], [串联嵌套调用的 sink 链；emit 短路传播],
  [`Multi<T>` / `multi!`], [#src[src/input.rs:180 / :182]], [0–12 元组输入的 Input 实现],
  [`Sink` / `Call` / `Surfaces`], [#src[src/track.rs:59 / :79 / :92]], [事件汇 / 调用抽象 / surface 类型族],
  [`accelerate::{id, get, evict}`], [#src[src/accelerate.rs:18 / :36 / :24]], [约束验证加速器：单调 ID + epoch offset],
  [`hash::hash`], [#src[src/hash.rs:7]], [SipHasher13 128 位预哈希，全库统一原语],
)

== A.3 宏展开关键点

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*名称*], [*位置*], [*作用*],
  [`memoize::expand`], [#src[macros/src/memoize.rs:6]], [prepare（校验）→ process（生成）],
  [`process`], [#src[macros/src/memoize.rs:100]], [生成 static `__CACHE` + `internal::memoize` 调用],
  [`track::expand`], [#src[macros/src/track.rs:4]], [分派 impl/trait；禁混合可变性；`const _: ()` 包裹],
  [`prepare_method`], [#src[macros/src/track.rs:100]], [全部方法级校验],
  [`create_variants`], [#src[macros/src/track.rs:195]], [`__ComemoCall` / `__ComemoVariant` 与 `is_mutable`],
  [`create`], [#src[macros/src/track.rs:232]], [Track/Surfaces 实现与 surface 类型],
  [`create_call(_mut)`], [#src[macros/src/track.rs:340 / :360]], [重放落点：真实调用 + 哈希 / 真实执行副作用],
  [`create_wrapper`], [#src[macros/src/track.rs:379]], [wrapper 方法：拆包 → 真实调用 → Sink::emit],
)

#pagebreak()
= 附录 B：术语表

#table(
  columns: (auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*术语*], [*含义*],
  [memoization（记忆化）], [缓存函数返回值，同一组参数只执行一次],
  [constrained memoization（受约束记忆化）], [缓存条目同时绑定参数哈希与执行期间观察到的访问记录；被观察部分不变即可命中],
  [incremental computation（增量计算）], [输入变化后只重算受影响部分的计算范式],
  [access tracking（访问跟踪）], [把 tracked 值上的方法调用记录为 (调用, 返回哈希) 事件],
  [constraint（约束）], [一次执行留下的调用序列记录，用于下次调用的命中验证],
  [mutation replay（变更重放）], [缓存命中时把记录的可变调用重新应用到参数上],
  [call tree（调用树）], [以 (调用, 返回哈希) 序列为路径的前缀树，存储缓存条目],
  [oracle（神谕）], [约束验证时对当前 tracked 输入重放历史调用的函数],
  [surface 类型], [`#[track]` 宏生成的包装类型，`Tracked` 的 Deref 目标，拦截所有方法调用],
  [sink（事件汇）], [接收 tracked 调用事件的目的地（如 Constraint）],
  [accelerator（加速器）], [缓存"调用哈希 → 返回哈希"，避免约束验证时重复执行昂贵方法],
  [reorderably deterministic（可重序确定）], [两次执行中，前缀匹配的调用序列必须包含彼此的全部调用（顺序可不同）],
  [age / eviction（代龄/逐出）], [条目距上次命中经历的逐出次数；`evict(max_age)` 清除超龄条目],
)
