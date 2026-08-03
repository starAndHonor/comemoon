// 第二章：跟踪层与输入抽象
#import "preamble.typ": *

= 二、跟踪层与输入抽象

#knowtitle[定位：把"对值的普通方法调用"转化为"可记录、可重放的调用事件"]

跟踪层（tracking layer）涉及四个文件：#src[src/track.rs] 定义 `Tracked`/`TrackedMut` 包装类型与 `Track`/`Call`/`Sink`/`Surfaces` 四个 trait；#src[src/input.rs] 定义 `Input` trait 统一输入抽象，并提供 `MergedSink` 串联嵌套调用的 sink 链、`multi!` 宏支持元组输入；#src[src/accelerate.rs] 提供约束验证加速器；#src[src/hash.rs] 提供全库统一的 128 位预哈希。

== `Tracked<'a, T, C>` 的结构与 Deref 机制

定义于 #src[src/track.rs:162-176]，三个字段（均 `pub(crate)`）：

- `value: &'a T`（#src[src/track.rs:167]）——被跟踪值的不可变引用；
- `sink: Option<&'a dyn Sink<Call = C>>`（#src[src/track.rs:173]）——调用事件的接收方，初始为 `None`，在 memoized 函数序言中被设为栈上存储的约束 sink（字段文档 #src[src/track.rs:168-172]）；
- `id: usize`（#src[src/track.rs:175]）——验证加速器的唯一 ID，由 `accelerate::id()` 分配。

*Deref 到 surface 类型*：`impl Deref for Tracked`（#src[src/track.rs:181-191]），`Target = T::Surface<'a>`。注释（#src[src/track.rs:178-180]）点明设计意图：自动 deref 使 `#[track]` 标注的方法可用，而 T 的其他方法不可达——#key[surface 类型是访问的唯一入口，因此所有访问都能被拦截记录]。

*Copy/Clone 语义*：`Tracked` 是 `Copy`（#src[src/track.rs:203]）。它只含共享引用、`Option<&dyn Sink>` 和 `usize`，可以像普通引用一样自由传递、多处共用同一跟踪上下文。

== `TrackedMut` 与 `Tracked` 的差异

- 定义于 #src[src/track.rs:223-235]：`value: &'a mut T` + `sink`，#key[没有 `id` 字段]——可变调用有副作用，不能用加速器缓存返回哈希。
- 实现 `Deref` 与 `DerefMut`（#src[src/track.rs:277-297]），后者经 `surface_mut_mut` 暴露可变 surface，使可变方法也能被拦截。
- 三个关联函数刻意做成关联函数而非方法，避免与 T 上同名方法冲突（注释 #src[src/track.rs:241-243]）：`downgrade`（#src[src/track.rs:246]，可变降级为不可变，此时才分配 accelerator id）、`reborrow` / `reborrow_mut`（#src[src/track.rs:259]、#src[src/track.rs:272]）。
- `TrackedMut` 不是 `Copy`（含 `&mut`），必须线性传递以保证 `call_mut` 副作用只发生一次。

== 四个 trait 的方法与契约

- *`Track`（#src[src/track.rs:12-56]）*：可跟踪类型。关联类型 `type Call: Call` 是该类型所有可能被跟踪调用的枚举；`call(&self, &Call) -> u128` 执行调用并返回*结果哈希*；`call_mut(&mut self, &Call)` 执行可变调用。四个便捷构造器：`track()`（:25）、`track_mut()`（:31）、`track_with(sink)`（:37）、`track_mut_with(sink)`（:50）。
- *`Sink`（#src[src/track.rs:59-68]）*：调用事件的目的地，要求 `Send + Sync`。`emit(call, ret: u128) -> bool` 的返回值含义（文档 #src[src/track.rs:63-66]）：#key[返回 `false` 表示该调用已被去重，调用方应避免再向层级更高的其他 sink 发送]。`&S` 的 blanket impl（:70-76）让 sink 引用本身也是 sink。
- *`Call`（#src[src/track.rs:79-82]）*：一次被跟踪调用的抽象，要求 `Clone + PartialEq + Hash + Send + Sync`；唯一方法 `is_mutable()`。`()` 的 impl（:85-89，恒为 false）供纯哈希输入占位。
- *`Surfaces`（#src[src/track.rs:92-121]）*：surface 类型族。两个 GAT：`Surface<'a>` 与 `SurfaceMut<'a>`；三个访问器 `surface_ref` / `surface_mut_ref` / `surface_mut_mut`。surface 类型由 `#[track]` 宏生成（见第四章）。

== `Tracked` 的 variance 问题与 Chain 解法

文档注释 #src[src/track.rs:125-161]（「\#\# Variance」节）：默认类型参数 `C = <T as Track>::Call` 中 T 出现在关联类型投影里，由于编译器限制，此时 `Tracked<'a, T>` 对 T 是 #key[invariant（不变）]的。

- *后果*：无法构造可用的 tracked 类型"链"，如 `struct Chain<'a> { outer: Tracked<'a, Self>, data: u32 }`（#src[src/track.rs:131-136]）——invariance 阻止生命周期缩短。而该模式有用，例如检测 memoized 递归算法中的环。
- *解法*（#src[src/track.rs:144-152]）：手动指定调用类型 `Tracked<'a, Self, <Chain<'static> as Track>::Call>`，切断 C 对 `'a` 的依赖使 T 恢复协变。`'static` 的用意：让编译器确信关联约束类型不依赖 `'a`——事实上所有约束都是 `'static` 的。

== `Input` trait 五件套与三个实现

定义于 #src[src/input.rs:13-41]：

- `type Call: Call`（:16）——该输入所有 tracked 部分可能产生的调用枚举；
- `type Storage<S: Sink<Call = Self::Call> + 'a>: Default`（:20）——存放"合并后 sink"的外部存储类型；
- `fn key<H: Hasher>(&self, &mut H)`（:23）——只对*非 tracked 部分*哈希，作为缓存键；
- `fn call(&self, &Call) -> u128`（:29）——在 tracked 部分上重放调用并返回结果哈希；
- `fn call_mut(&mut self, &Call)`（:34）——重放可变调用，无返回哈希；
- `fn attach<S>(&mut self, storage: &'a mut Storage<S>, sink: S)`（:38-40）——把给定 sink 整合进输入的 tracked 部分。

#table(
  columns: (auto, auto, auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*实现*], [*Call*], [*Storage*], [*key*], [*call / call_mut / attach*],
  [`T: Hash`（#src[:43-68]）], [`()`], [`()`], [真正哈希自身],
  [`call` 恒返回 0；`call_mut` 空操作；`attach` 空操作],
  [`Tracked<'a, T>`（#src[:70-116]）], [`T::Call`], [`Option<MergedSink>`], [空操作],
  [`call` 走加速器 + sink 转发（:81-102）；`call_mut` 空操作；`attach` 包进 MergedSink（:110-115）],
  [`TrackedMut<'a, T>`（#src[:118-153]）], [`T::Call`], [同上], [空操作],
  [`call` 直接执行 + 转发；`call_mut` 真执行副作用并 emit（:138-143）],
)

要点：#key[tracked 输入的 `key` 为空——它们不参与缓存键，而是通过约束验证缓存有效性；纯哈希输入则相反，只进键、无约束]。两者职责正交互补。

#warning[`Storage` 关联类型为什么需要外部传入的 `&mut Default` 存储（#src[src/input.rs:20]、:38-40）：`attach` 要把生命周期为 `'a` 的合并 sink 存进 `sink: Option<&'a dyn Sink>` 字段，但 `MergedSink` 是函数局部值，不能引用局部变量。解法是让调用方（宏生成的序言）在栈上持有 `Storage<S>`，`attach` 用 `storage.insert(...)` 把值放进外部存储再取引用——存储所有权在调用方帧上，引用才能活到 `'a`。]

== 嵌套 memoize 的正确性枢纽：命中也必须转发

#src[src/input.rs:93-99] 的原注释（`Tracked` 的 `call` 内）：

#block(
  fill: rgb("#f4f6f7"),
  stroke: (left: 2.5pt + faintgray),
  inset: (left: 8pt, top: 5pt, bottom: 5pt),
  width: 100%,
)[#text(size: 0.88em, style: "italic")[The `call` method is used during the constraint validation tree traversal. It's crucial that we also send calls to the outer sink here so that the outer sink observes the calls when we have a cache hit. We do _not_ replay the constraints in another way.]]

含义：`call` 在约束验证树遍历时被用来重放调用；即使加速器和 memoize 缓存命中（没有真正执行函数体），也必须把（调用, 返回哈希）emit 到外层 sink。这是#key[嵌套 memoize 正确性的关键]：外层函数的约束必须记录"我这次执行间接依赖了内层 tracked 值的哪些调用"，否则外层缓存命中时这些依赖丢失，下次验证就无法发现内层值已变。comemo 没有第二条约束重放路径——验证路径与记录路径是同一条 emit 链路。

== `MergedSink`：嵌套调用的 sink 串联

- 定义 #src[src/input.rs:155-159]：`prev: Option<&'a dyn Sink>` + `sink: S`，`Copy + Clone`。
- `emit` 实现（#src[src/input.rs:168-176]）：`self.sink.emit(call.clone(), ret) && prev.emit(call, ret)`——#key[短路逻辑]：当前 sink 若已去重（返回 false），就不再向 prev 传播（注释 :170-171）。
- 串联场景：外层 memoized 函数 f 把 constraint sink attach 到 tracked 输入；f 内部调用内层 memoized 函数 g 并传入该输入，g 的序言再次 attach，形成 `MergedSink { prev: 外层 sink, sink: g 的 sink }`。于是内层的一次 tracked 调用同时进入两级约束，两级缓存各自都能验证。

== `multi!` 宏：元组输入（至多 12 元）

- 入口 #src[src/input.rs:182-251]，实例化支持 0 至 12 元组（#src[src/input.rs:255-270]）。`Multi<T>(pub T)`（:180）是元组输入的包装。
- 每个实例生成三样东西：
  + `impl Input for Multi<(A, B, ...)>`（:184-213）：`Call = MultiCall<A::Call, B::Call, ...>`；`key` 逐元素哈希；`call`/`call_mut` 按 `MultiCall` 变体分发；`attach` 把 sink 包上 `MappedSink::<idx, _>` 后逐元素下传。
  + `pub enum MultiCall<A, B, ...>`（:217-219）：变体以类型参数命名，`is_mutable` 委派给内部调用。
  + `pub struct MappedSink<const I: usize, S>(S)`（:232）：把元素级 `emit` 映射为整体级 `MultiCall` 变体再发给外层 sink。const 泛型 `I` 仅为区分同一元组中同类型元素的不同 impl。
- 效果：混合输入（有的参数可哈希、有的 tracked）被拆解——哈希部分进缓存键，tracked 部分各自 attach 合并 sink。

== accelerate.rs：约束验证加速器

*动机*：约束验证时需要对 tracked 值*重复重放*所有记录的调用以获得返回哈希；这些 tracked 方法可能昂贵（如文件读取）。加速器把"调用哈希 → 返回哈希"缓存起来，同一 tracked 实例在一次验证周期内同一调用只执行一次（使用点 #src[src/input.rs:82-91]）。

数据结构：

- `static ACCELERATORS: RwLock<(usize, Vec<Accelerator>)>`（#src[src/accelerate.rs:7]）——全局表，元组首元素是 *offset*；
- `static ID: AtomicUsize`（:10）——单调递增的 ID 源；
- `type Accelerator = Mutex<FxHashMap<u128, u128>>`（:15）。

ID / offset / epoch 式清理（三个函数配合）：

+ `id()`（:18-21）：`ID.fetch_add(1)` 发新 ID。每个 `Tracked` 构造时拿一个（#src[src/track.rs:26]）。
+ `evict()`（:24-33）：每次 memoize 缓存逐出时调用。*把 offset 更新为当前 ID 值*（:29），并清空所有现存加速器但保留已分配内存（:32）。由于 ID 单调增，旧 ID `id < offset` 从此全部失效——不必逐个删除，一次 offset 推进即完成 "epoch 切换"。
+ `get(id)`（:36-54）：`id.checked_sub(offset)` 把全局 ID 换算为 vec 下标；旧 epoch 的 id 直接返回 `None`，退化为真实调用。下标越界则 drop 读锁 → `resize` → 重拿读锁并*再次* `checked_sub` 校验（:43-50）——因为放锁期间另一线程可能 evict 推进了 offset（注释 :47-49）。最后经 `RwLockReadGuard::map` 返回映射到单个 Accelerator 的读守卫。
+ `resize`（:57-62）：`#[cold]`，写锁下惰性补槽位。

== hash.rs：128 位预哈希

`pub fn hash<T: Hash>(value: &T) -> u128`（#src[src/hash.rs:7-11]）：用 `SipHasher13` 的 128 位变体对任意可哈希值做预哈希。全库所有"值 → u128"的哈希都走它：加速器键/值、约束中的返回哈希、缓存键。#key[128 位宽度让冲突概率可忽略，使 comemo 可以把"哈希相等"当作"值相等"来构建整条增量验证链]（以哈希代值，避免存储/比较任意大对象）。

== 本章源码精读路线

建议顺序：*track.rs → input.rs → accelerate.rs → hash.rs*。

+ #src[src/track.rs:12-56]（`Track` trait）：`call` 返回的是"结果的哈希"而非结果本身——全库"以哈希代值"的第一次出现。注意 `track()` 里 `id: accelerate::id()` 而 `track_mut()` 没有 id 的不对称。
+ #src[src/track.rs:59-89]（`Sink` 与 `Call`）：`emit` 返回值的去重短路语义是 `MergedSink` 正确性的前提。
+ #src[src/track.rs:92-121]（`Surfaces`）：GAT 声明方式；访问器以 `Tracked` 整体为参数（宏生成的 surface 方法需要 sink 和 id）。
+ #src[src/track.rs:123-211]（`Tracked` + Variance 文档）：Variance 文档逐行读 Chain 两个例子。
+ #src[src/track.rs:213-297]（`TrackedMut`）：三个关联函数为什么不做成方法。
+ #src[src/track.rs:309-339]（`to_parts_*`）：memoize 主流程用它们拆出 value 与 sink。
+ #src[src/input.rs:13-41]（`Input` trait）：精读每个成员的文档注释，`Storage` 与 `attach` 是最难懂的设计点。
+ #src[src/input.rs:70-116]（`Tracked` impl）：本章核心。`call` 分两层读：加速器查表（:82-91）→ sink 转发（:93-99 的注释必须逐字读）。
+ #src[src/input.rs:118-176]（`TrackedMut` + `MergedSink`）：对比两个 `call_mut`；`MergedSink::emit` 的 `&&` 短路。
+ #src[src/input.rs:178-270]（`multi!` 宏）：只读一个实例理解变体分发即可。
+ #src[src/accelerate.rs]（全文 63 行）：按 `id()` → `get()` → `evict()` → `resize()` 顺序读；`get` 的放锁-扩容-重取-再校验是唯一的并发精巧处。
+ #src[src/hash.rs]（全文 11 行）：确认 SipHasher13 与 128 位输出。

== 易错点与设计权衡

- *cache hit 也必须向 sink 转发调用*（#src[src/input.rs:93-99]）：最易误解处。以为"加速器命中 = 不用 emit"是错的——外层约束依赖这些事件做验证。
- *加速器的并发设计：先读锁、放锁、resize、再读锁、再校验*（#src[src/accelerate.rs:39-51]）。offset 设计用"单调 ID + epoch offset"把逐出从 O(n) 删除变为 O(1) 比较，`evict` 清表时保留容量避免反复分配。
- *`Sink::emit` 返回值的短路语义是性能优化而非可选项*（#src[src/track.rs:63-67]）：忽略返回值不会错但会重复记录。
- *`Tracked` 是 `Copy` 而 `TrackedMut` 不是*：不可变跟踪上下文可多处共享；可变路径必须线性传递。
- *invariance 陷阱*：写 tracked 链会莫名报错，解法是显式给 `<Chain<'static> as Track>::Call`；初学者容易以为是生命周期标注错误。
- *`key` 与约束的分工*：纯哈希输入只进缓存键、tracked 输入只进约束。误以为 tracked 值也进键会导致把不可哈希的大对象塞进键。
