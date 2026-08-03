// 第四章：过程宏层
#import "preamble.typ": *

= 四、过程宏层（comemo-macros）

#knowtitle[定位：零样板体验的来源——编译期把普通函数/impl 块改写为接入运行时的代码]

comemo-macros 是独立的 proc-macro crate（#src[macros/Cargo.toml:14-15] 声明 `proc-macro = true`，依赖只有 proc-macro2 / quote / syn 三件套）。对外只导出两个属性宏：`#[memoize]`（入口 #src[macros/src/lib.rs:133-139]）与 `#[track]`（入口 #src[macros/src/lib.rs:211-216]）。缓存查找、参数打包、调用追踪、约束生成全部在编译期由宏生成；宏本身不含任何运行时逻辑，生成的代码只是对运行时机制（`internal::memoize`、`Cache`、`Call`、`Surfaces`、`Sink`）的调用拼装。

== `#[memoize]` 的展开流程

*expand*（#src[macros/src/memoize.rs:6-16]）：要求被标注项是 `syn::Item::Fn`，然后两步：`prepare`（解析+校验）→ `process`（代码生成）。

*prepare*（:44-63）：属性参数解析成 `Meta { enabled: Option<syn::Expr> }`（`enabled` 是自定义关键字，:172-174）；逐参数调 `prepare_arg`；无返回值的函数输出规范化为 `()`。

*prepare_arg*（:66-97）：宏层#key[并不区分 hashed / Tracked / TrackedMut 三类参数]——区分完全推迟到运行时由 `Input` trait 按类型分派。宏只做语法级校验：

- `&mut self` 接收者禁止（:69-71）；
- 参数模式必须是简单标识符：拒绝解构（:76-85）；
- `&mut T` 类型的普通参数禁止（:87-92）。

*process*（:100-170）：生成四组 token 后整体替换函数体：

+ 每个参数一条编译期断言 `assert_hashable_or_trackable(&arg)`（:102-110），用 `quote_spanned!` 把错误定位到原函数；
+ 参数值元组：`self` 被替换为 `hash(&self)`（:113-119）——方法场景下 self 一律走哈希；
+ 参数类型元组：self 的类型槽位记为 `()`（:121-125）；
+ 内层闭包：原函数体原封不动变成闭包体（:134-137）；
+ 外层函数剥掉参数上的 `mut`，`enabled` 缺省补 `true`，用 `parse_quote!` 换入新函数体（:149-167）。

生成的代码骨架（与 #src[macros/src/memoize.rs:149-167] 的 `parse_quote!` 逐行对应）：

```rust
fn evaluate(script: &str, files: Tracked<Files>) -> i32 {
    // 每个被 memoize 的函数独占一份函数内 static 缓存
    static __CACHE: ::comemo::internal::Cache<
        <::comemo::internal::Multi<(&str, Tracked<Files>)>
            as ::comemo::internal::Input>::Call,
        i32,
    > = ::comemo::internal::Cache::new(|| {
        // 初始化时把本缓存的驱逐函数挂进全局注册表
        ::comemo::internal::register_evictor(|max_age| __CACHE.evict(max_age));
        ::core::default::Default::default()
    });

    ::comemo::internal::assert_hashable_or_trackable(&script);
    ::comemo::internal::assert_hashable_or_trackable(&files);

    ::comemo::internal::memoize(
        &__CACHE,
        ::comemo::internal::Multi((script, files)),
        &mut ::core::default::Default::default(), // 栈上 (storage, constraint)
        true,            // enabled 表达式，缺省 true（每次调用求值）
        |::comemo::internal::Multi((script, files))| -> i32 { /* 原函数体 */ },
    )
}
```

要点：`__CACHE` 是函数内 static；`Cache` 的类型参数用 `<Multi<...> as Input>::Call`——不同参数类型组合对应不同 Call 类型，由运行时 `Input` trait 计算；`enabled` 表达式在每次调用时求值，为 false 时运行时跳过哈希与缓存（动机见文档 #src[macros/src/lib.rs:108-131]：廉价小函数绕开缓存开销）。

== `#[track]` 的展开流程

入口 #src[macros/src/lib.rs:211-216] → `track::expand`（#src[macros/src/track.rs:4-63]）。支持两种目标：

- *inherent impl 块*（:9-28）：拒绝类型泛型与 const 泛型（生命周期允许），逐成员 `prepare_impl_method`；
- *trait 定义*（:29-41）：trait 不能有任何泛型参数（连生命周期也不行），类型被改写为 `dyn TraitName + '__comemo_dynamic`——trait 场景下追踪对象是 trait object；
- 其他项一律报错（:42）。

*校验链*：`prepare_method`（:100-192）逐条规则：

#table(
  columns: (1fr, auto),
  fill: (_, row) => if row == 0 { sectionbg },
  [*规则*], [*行号*],
  [不能 `unsafe` / `async` / `const`], [#src[:101-111]],
  [方法不能有类型/const 泛型（生命周期可以）], [#src[:113-120]],
  [必须有 `self` 接收者，且必须按引用（`&self` / `&mut self`）], [#src[:122-129]],
  [参数必须是简单标识符，禁解构、禁 `mut` 绑定、禁 `impl Trait`], [#src[:141-155]],
  [参数不能是 `&mut T`；`&T` 记为 `Kind::Reference`], [#src[:156-164]],
  [返回值不能是 `&mut` 引用], [#src[:171-176]],
  [可变方法（`&mut self`）不能有返回值], [#src[:178-182]],
)

最后在 `expand` 末尾做全块级校验：#key[同一个 impl/trait 不能混合可变与不可变方法]（:45-50），生成物包进匿名常量 `const _: () = { ... }` 避免污染命名空间（:56-62）。

*生成物的四个部分*：

#figure(
  block(width: 100%, inset: 4pt)[
    #align(center)[
      #box(fill: sectionbg, inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em, weight: "bold")[\#\[track\] impl Files]]
    ]
    #v(0.3em)
    #align(center)[#sym.arrow.b]
    #v(0.3em)
    #align(center)[
      #box(fill: rgb("#e8f6ef"), inset: (x: 6pt, y: 5pt), radius: 3pt)[#text(size: 0.78em)[① Call 枚举\ `__ComemoCall`/`__ComemoVariant`]]
      #h(0.3em)
      #box(fill: rgb("#e8f6ef"), inset: (x: 6pt, y: 5pt), radius: 3pt)[#text(size: 0.78em)[② surface 类型\ `__ComemoSurface(Mut)`]]
    ]
    #v(0.25em)
    #align(center)[
      #box(fill: rgb("#e8f6ef"), inset: (x: 6pt, y: 5pt), radius: 3pt)[#text(size: 0.78em)[③ Track / Surfaces / Call trait 实现]]
      #h(0.3em)
      #box(fill: rgb("#e8f6ef"), inset: (x: 6pt, y: 5pt), radius: 3pt)[#text(size: 0.78em)[④ wrapper 方法（真实调用 + Sink::emit）]]
    ]
  ],
  caption: [\#\[track\] 宏的四个生成物（create\_variants / create / create\_call(\_mut) / create\_wrapper）],
)

+ *Call 枚举*：`create_variant`（:333-337）为每个方法生成元组变体 `方法名(<参数类型 as ToOwned>::Owned, ...)`——参数一律存 owned 形式。外包 `pub struct __ComemoCall(__ComemoVariant)`（:214-215），并实现 `Call::is_mutable()`。两者 derive `Clone, PartialEq, Hash`——这就是调用记录可哈希、可比较的来源。
+ *surface 类型*：`#[repr(transparent)] pub struct __ComemoSurface<'t, ...>(Tracked<'t, T>)` 与 `__ComemoSurfaceMut`（:312-328）。它们是 `Tracked` 解引用后的目标类型，上面挂着 wrapper 方法。
+ *Track / Surfaces / Call 三个 trait 实现*（:267-310）：`Track::call` 逐变体 match（`create_call`，:340-357）：不可变方法真实调用并把返回值哈希成 u128，可变方法直接返回 0；`Track::call_mut`（`create_call_mut`，:360-376）：可变方法真实执行，不可变方法什么都不做。#key[这两个方法就是运行时"重放"的落点]。`Surfaces` 实现用 `repr(transparent)` 保证布局一致后直接指针强转（`unsafe`，:291-308）。
+ *wrapper 方法*：`create_wrapper`（:379-409）在 surface 类型上生成与原方法同签名的方法，按三种情形选择拆包函数（`to_parts_ref` / `to_parts_mut_ref` / `to_parts_mut_mut`）：

```rust
let (value, sink) = ::comemo::internal::to_parts_ref(self.0);
if let Some(sink) = sink {              // 处于被追踪的 memoized 调用中
    let variant = __ComemoVariant::read(path.to_owned());
    let output = value.read(path);      // 先真实调用
    ::comemo::internal::Sink::emit(sink, __ComemoCall(variant),
        ::comemo::internal::hash(&output));
    output
} else {                                // 未被追踪：直接调用，零开销
    value.read(path)
}
```

== utils.rs 的辅助

`parse_key_value<K, V>`（#src[macros/src/utils.rs:9-21]）：用 `peek` 试探关键字，存在则解析 `key = value`——支撑 `#[memoize(enabled = ...)]` 的语法。`eat_comma`（:24-28）：吃掉可选逗号。

== 手写等价展开示例（示意）

以 #src[examples/calc.rs] 的 `#[track] impl Files { fn read(&self, path: &str) -> String }` 为蓝本（*示意，省略泛型与 where 子句细节*）：

```rust
const _: () = {
    // ① Call 枚举（create_variant, track.rs:333-337）
    #[derive(Clone, PartialEq, Hash)]
    enum __ComemoVariant { read(<&str as ToOwned>::Owned /* = String */) }
    #[derive(Clone, PartialEq, Hash)]
    pub struct __ComemoCall(__ComemoVariant);
    impl ::comemo::internal::Call for __ComemoCall {
        fn is_mutable(&self) -> bool { match &self.0 { __ComemoVariant::read(..) => false } }
    }

    // ③ Track 实现（create_call / create_call_mut, track.rs:340-376）
    impl ::comemo::Track for Files {
        type Call = __ComemoCall;
        fn call(&self, call: &Self::Call) -> u128 {
            match call.0 { __ComemoVariant::read(ref path) =>
                ::comemo::internal::hash(&self.read(path)) } // 真实调用 + 哈希返回值
        }
        fn call_mut(&mut self, call: &Self::Call) {
            match call.0 { __ComemoVariant::read(..) => {} } // 不可变方法：空操作
        }
    }
    // ② surface 类型 + ③ Surfaces 实现（track.rs:283-328，repr(transparent) 指针强转）
    #[repr(transparent)]
    pub struct __ComemoSurface<'t>(::comemo::Tracked<'t, Files>);
    // ④ wrapper 方法（create_wrapper, track.rs:379-409）：真实调用 + Sink::emit
};
```

`#[memoize]` 侧的展开见上文"生成的代码骨架"。

== 本章源码精读路线

+ #src[macros/src/lib.rs:23-131]（memoize 宏文档）：先读。三类参数与四条限制是理解运行时的前提。
+ #src[macros/src/memoize.rs:6-16]：入口与分派；memoize 也可用于方法（impl 块里的方法经 `syn::Item` 解析后同样是 Fn）。
+ #src[macros/src/memoize.rs:44-97]：读校验逻辑，对照文档限制找对应 `bail!`。
+ #src[macros/src/memoize.rs:100-170]（process）：本章核心。重点：self 为什么被换成 `hash(&self)`；static `__CACHE` 的类型参数为什么用 `<Multi<...> as Input>::Call`；`register_evictor` 把每个函数的缓存挂进全局驱逐体系。
+ #src[macros/src/track.rs:4-63]（expand）：两种目标分派与"禁混合可变性"总开关；`const _: () = {}` 防名字污染。
+ #src[macros/src/track.rs:100-192]（prepare_method）：对照文档逐条看校验；`Kind::Reference` 判定决定后面 `to_owned()` 加不加。
+ #src[macros/src/track.rs:195-229] 与 :232-330：生成物全景；`repr(transparent)` + 指针强转是 surface 零成本的原因。
+ #src[macros/src/track.rs:333-409]（四个 create\_\*）：与"四部分"一一对应；`create_wrapper` 中 sink 为 `None` 的快路径说明未追踪时开销为零。
+ #src[macros/src/utils.rs:9-28]：一分钟扫完。

== 易错点与设计权衡

- *为什么 tracked 方法参数要 `ToOwned`：调用记录要活下来*。每次 tracked 调用被存入 `__ComemoVariant` 枚举，进而进入缓存的约束结构，生命周期远长于方法调用本身——引用参数必须转成 owned 才能存。`Kind::Reference` 分支在真实调用时把 owned 值再借回去，避免无谓克隆。
- *为什么可变 tracked 方法无返回值：重放语义决定*。命中时不执行函数体，只通过 `Track::call_mut` 重放历史变更；若可变方法有返回值，调用方拿到的将是上次缓存的值，语义无法保证。
- *为什么不能混合可变与不可变方法*：`Surfaces` 实现只有一份。如果同一类型既能不可变追踪又能可变追踪，不可变追踪路径会漏记对状态的依赖，缓存命中时状态却已变化——作者干脆一刀切：要么全不可变（用 `Tracked`），要么全可变（用 `TrackedMut`）。
- *memoize 宏层不区分三种参数是刻意的*：参数是 hashed 还是 tracked 完全由类型在运行时经 `Input` trait 分派，宏只做语法校验。这让同一套宏代码覆盖三类参数。
- *`&mut` 参数被禁不是能力问题而是纯度保证*：普通 `&mut T` 的变更无法被追踪/重放，宏在三处拦截（#src[macros/src/memoize.rs:69-71]、:87-92、#src[macros/src/track.rs:157-158]）。
- *`enabled` 表达式放在运行时求值*：牺牲一次布尔求值换来"同一签名、可选缓存"，对 Typst 中大量廉价小函数是关键优化。
