// 第一章：总体原理与概念模型
#import "preamble.typ": *

= 一、总体原理与概念模型

#knowtitle[定位：comemo 是什么、解决什么问题]

- comemo 是 Typst 排版引擎的*增量计算（incremental computation）*核心库，一句话定位：#key["Incremental computation through constrained memoization"]（#src[src/lib.rs:2]、#src[README.md:5]）。
- 它要解决的问题：基础记忆化（memoization）把"整组参数"当作缓存键，粒度过粗——"lacks the necessary granularity"（#src[README.md:14-15]）。以 `.calc` 语言解释器为例，`evaluate` 需要整个文件集合 `&Files` 作为输入，于是 "a change to any file invalidates all memoized results"（#src[README.md:49-51]），任何一个无关文件改动都会让全部缓存失效。
- #key[受约束记忆化（constrained memoization）]的核心思想：缓存条目不只绑定参数哈希，还绑定调用期间*实际观察到的访问记录*（约束）；只要这些被观察到的部分没变，即使输入整体变了也能命中（#src[README.md:53-63]、#src[src/lib.rs:48-62]）。
- crate 分两层：`comemo` 本体提供运行时（#src[src/lib.rs:91-97] 的七个模块），`comemo-macros` 提供 `#[memoize]` 与 `#[track]` 两个属性宏（#src[macros/src/lib.rs:133-139]、#src[macros/src/lib.rs:211-216]）。用户接入只需三步：给函数加 `#[memoize]`、给 impl 块加 `#[track]`、把参数包进 `Tracked`（#src[README.md:56-58]）。

== 基础记忆化 vs 受约束记忆化

- *基础记忆化*：函数 "caches its return values so that it only needs to be executed once per set of unique arguments"（#src[README.md:12-13]）。缓存键 = 全部参数的哈希。
- *`.calc` 反例*：脚本由数字加法与 `eval <path>` 语句构成（#src[README.md:17-22]：`alpha.calc` = `"2 + eval beta.calc"` 等），解释器递归读取依赖文件（#src[examples/calc.rs:40-49]）。若把整个 `Files` 哈希为键，改 `gamma.calc` 也会使只依赖 `beta.calc` 的 `alpha.calc` 结果失效。
- *受约束记忆化*：把"输入值"换成"输入值 + 本次执行实际读到了什么"。#src[examples/calc.rs:28-29] 演示：修改 `gamma.calc` 后 `evaluate("eval alpha.calc", ...)` 仍 `[Hit]`，因为 `gamma.calc` 未被 `alpha.calc` 引用；而 #src[examples/calc.rs:34-35] 修改 `beta.calc` 后 `[Miss]`。
- *另一个粒度收益：嵌套命中*。#src[examples/calc.rs:21-23]——顶层字符串没见过（顶层 miss），但内部 `"2 + 3"` 的求值不会重算（内层 hit）。

#figure(
  block(width: 100%, inset: 4pt)[
    #align(center)[
      #box(fill: sectionbg, inset: (x: 10pt, y: 6pt), radius: 3pt)[#text(size: 0.85em, weight: "bold")[基础记忆化：缓存键 = 全部参数哈希]]
      #h(1em)
      #box(fill: rgb("#fdeaea"), inset: (x: 10pt, y: 6pt), radius: 3pt)[#text(size: 0.85em)[任一输入字节变化 → 全部失效]]
    ]
    #v(0.4em)
    #align(center)[#text(size: 1.1em)[#sym.arrow.b.double] #text(size: 0.85em, fill: sectioncolor)[constrained memoization：键 + 约束]]
    #v(0.4em)
    #align(center)[
      #box(fill: sectionbg, inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.85em)[参数哈希 key]]
      #h(0.5em)#sym.plus#h(0.5em)
      #box(fill: rgb("#e8f6ef"), inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.85em)[(tracked 调用, 返回哈希) 约束序列]]
      #h(0.5em)#sym.arrow.r#h(0.5em)
      #box(fill: rgb("#e8f6ef"), inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.85em)[重放验证仍成立 → 命中]]
    ]
  ],
  caption: [基础记忆化与受约束记忆化的失效粒度对比],
)

== 三大机制的交互（概念层）

+ #key[访问跟踪（access tracking）]：`#[track]` 让类型的方法可被观测；`Tracked<T>` 容器在方法调用时把"调用了哪个方法、传了什么参数、返回值的哈希"记录到一个 sink（#src[src/track.rs:12] 的 `Track` trait、#src[src/track.rs:59] 的 `Sink`、#src[src/track.rs:162] 的 `Tracked`）。
+ #key[约束记录与验证（constraint recording/validation）]：一次 memoized 调用产生的调用序列被记录为 `Constraint`（#src[src/constraint.rs:17]；验证入口 `Constraint::validate`，#src[src/constraint.rs:35]）。下次调用时用当前输入重放验证：约束仍成立 → 命中；不成立 → 重算。底层由*调用树（call tree）*高效存储多组调用序列（#src[src/tree.rs:15-26]）。
+ #key[变更重放（mutation replay）]：对 `TrackedMut<T>` 参数的可变调用也被记录；缓存命中时函数体不执行，comemo 把记录的变更重放到参数上，保证可观察副作用一致（#src[macros/src/lib.rs:39-42]；缓存条目中有 "Mutable tracked calls that must be replayed"，#src[src/memoize.rs:137-144]）。

交互时序（伪代码）：

```
memoized_call(args):
    key = hash(hashed_args)          // 128 位哈希, src/hash.rs:7
    if 缓存中存在 key 且约束重放验证通过:
        replay 记录的 mutable 调用    // src/memoize.rs:56-59
        return 缓存结果               // hit
    else:
        attach 约束 sink → 执行函数体 // 期间 tracked 调用被记录
        存入缓存                      // miss
```

== 正确性前提（用户契约）

以下契约全部出自宏文档（#src[macros/src/lib.rs:44-90]），是 comemo 正确工作的前提：

- #key[Hash 必须喂全信息]：参数的 `Hash` 实现 "must feed all the information they expose to the hasher"，否则缓存结果可能被错误复用（#src[macros/src/lib.rs:47-50]；tracked 方法的返回值同样要求，#src[macros/src/lib.rs:170-173]）。
- #key[唯一可观察不纯性是 TrackedMut 变更]："The only observable impurity memoized functions may exhibit are mutations through `TrackedMut<T>` arguments"（#src[macros/src/lib.rs:52-54]）。comemo 能阻止普通可变参数，但无法检测所有不纯来源（全局状态、IO、随机数等），这是用户的责任。tracked 方法同理：不可观察的内部可变性（idempotent 的 interior mutability）被允许（#src[macros/src/lib.rs:157-168]）。
- #key[reorderably deterministic（可重序确定）]的精确定义（#src[macros/src/lib.rs:57-84]）。设同一 memoized 函数的两次执行 A 与 B：
  - *In-order deterministic（按序确定）*（#src[macros/src/lib.rs:61-69]）：若 A 与 B 的前 N 次 tracked 调用及其结果相同，则第 N+1 次调用也必须相同。对确定性函数这很自然，但实践中过严——例如内部使用多线程的函数可能乱序发起 tracked 调用，整体结果仍是确定的。
  - *Reorderably deterministic（可重序确定）*（#src[macros/src/lib.rs:71-78]）：若对于 A 的前 N 次调用，B 的调用序列中*某处*存在匹配调用（参数相同、返回值相同），则 A 发起的第 N+1 次调用也必须出现在 B 的调用序列的*某处*。
  - *放宽理由*：这是 in-order determinism 的松弛版，允许缓存"内部多线程但对外确定"的函数（#src[macros/src/lib.rs:74-78]）。
  - *违反后果*：debug 模式可能 panic 提醒；release 模式结果仍正确，但缓存可能失效（#src[macros/src/lib.rs:80-84]）。
- 输出须为 `Send + Sync`（存入全局缓存，#src[macros/src/lib.rs:86-87]）；参数不能用解构模式（#src[macros/src/lib.rs:89-90]）。

#warning[不能用"结果对不对"判断程序是否满足契约——release 下契约违反永远表现为*性能问题*（缓存静默失效）而非正确性问题。调试时应开 debug 断言跑一遍。]

== 三类参数（Kinds of arguments）

出自 #src[macros/src/lib.rs:28-42]：

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*类别*], [*形式*], [*语义*],
  [Hashed（默认）], [普通参数], [哈希为高质量 128 位哈希作缓存键（#src[macros/src/lib.rs:31-32]）],
  [Immutably tracked], [`Tracked<T>`], [细粒度访问跟踪；只要差异未被观察到，`T` 值不同也可命中（#src[macros/src/lib.rs:34-37]）],
  [Mutably tracked], [`TrackedMut<T>`], [可在 memoized 函数内安全变更参数；命中时重放全部变更；可变 tracked 方法不能有返回值（#src[macros/src/lib.rs:39-42]）],
)

- 可变参数只能走 tracking（不能哈希），以便命中时重放副作用（#src[macros/src/lib.rs:148-151]）。
- `Tracked` / `TrackedMut` 由 `track()` / `track_mut()` 产生（#src[src/track.rs:25]、#src[src/track.rs:31]）。

== 本章源码精读路线

自顶向下、先契约后实现：

+ *#src[README.md]（全文）*：建立问题直觉。重点 :12-15（基础记忆化定义与粒度缺陷）、:17-51（`.calc` 动机例子）、:53-63（三步接入与"依赖不变即命中"的承诺）。
+ *#src[examples/calc.rs]（全文，约 65 行）*：把概念对应到代码。`main` 中四处 `[Miss]`/`[Hit]` 注释就是约束验证的行为规格说明。
+ *#src[src/lib.rs:1-88]（模块级文档）*：与 README 几乎同文；注意 :91-97 的模块划分与 :111-117 的 `internal` 模块（"Do not rely on them"）。
+ *#src[macros/src/lib.rs:15-132]（`#[memoize]` 文档）*：契约核心。reorderably deterministic 的两条性质在 :61-69 与 :71-78，务必对照原文逐句读。
+ *#src[macros/src/lib.rs:135-189]（`#[track]` 文档）*：tracked 方法的限制清单。

== 易错点与设计权衡

- *纯度责任在用户*：comemo 只能用类型系统挡住显式可变参数，挡不住全局状态、IO、随机数、可观察的内部可变性。这类 bug 表现为缓存错误命中，极难排查。
- *`Tracked` 不是值比较*：命中条件是"差异未被观察到"，而非"值相等"。`T` 整体从不哈希，只有被调用方法的参数与返回值进入约束。
- *设计权衡：调用序列作为正确性凭证*。comemo 选择"记录 (调用, 返回哈希) 序列并重放验证"而非维护显式依赖图。好处：用户零注解成本、嵌套调用天然分层；代价：要求 reorderably deterministic，且验证成本与调用序列长度相关（为此引入加速器与调用树做内部优化）。
- *与 salsa 等按需增量框架的定位对比*：comemo 是 memoization 的增强——以函数为缓存单位、以访问跟踪缩小失效范围，API 只有两个属性宏，无显式 query 数据库概念。[推断] 相比 salsa 的 query-group + 依赖图 + revision 计数模型，comemo 更接近"自动依赖发现 + 按需重放验证"；salsa 的具体机制请以 salsa 自身文档为准。
- *缓存是全局且需手动驱逐*：条目存入全局缓存，靠 `evict(max_age)`（#src[src/memoize.rs:101-106]）按 age 清理。长时间运行的程序若从不调用 `evict`，内存只增不减。
