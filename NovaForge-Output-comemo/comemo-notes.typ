// comemo 原理深度介绍与源码阅读指南 — 主文件
#import "preamble.typ": *

#show: novaforge-style

// ================= 封面 =================
#align(center)[
  #v(3.5cm)
  #text(fill: titlecolor, size: 2.1em, weight: "bold")[comemo]
  #v(0.4em)
  #text(fill: titlecolor, size: 1.3em, weight: "bold")[原理深度介绍与源码阅读指南]
  #v(1em)
  #text(fill: sectioncolor, size: 1em)[Incremental Computation through Constrained Memoization]
  #v(1.6em)
  #text(size: 0.95em)[受约束记忆化 · 访问跟踪 · 调用树 · 过程宏 · 增量计算]
  #v(2.2em)
  #text(size: 0.9em, fill: faintgray)[技术栈：Rust 2024 · proc-macro（syn/quote）· SipHash-1-3 · Slab]
  #v(0.6em)
  #text(size: 0.9em, fill: faintgray)[源码版本：comemo 0.5.0（github.com/typst/comemo）]
  #v(0.6em)
  #text(size: 0.9em)[整理：NovaForge]
  #v(0.4em)
  #text(size: 0.95em, fill: rgb("#2471a3"))[最后修订：2026年8月1日]
  #v(1fr)
]

#pagebreak()

// ================= 项目概览 =================
= 项目概览

#knowtitle[一句话定位]

comemo 是 Typst 排版引擎的增量计算核心库：通过#key[受约束记忆化（constrained memoization）]，让任意纯函数的缓存失效粒度从"整个输入"细化到"实际读到的数据"，从而支撑 Typst 的毫秒级增量重排版。

#knowtitle[仓库布局]

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*路径*], [*行数*], [*职责*],
  [`src/lib.rs`], [118], [crate 文档与模块导览；公开 API re-export；`internal` 实现细节模块],
  [`src/track.rs`], [338], [`Tracked`/`TrackedMut` 包装与 `Track`/`Call`/`Sink`/`Surfaces` trait],
  [`src/input.rs`], [270], [`Input` 输入抽象、`MergedSink`、`multi!` 元组输入],
  [`src/constraint.rs`], [166], [`Constraint` 约束记录与 `CallSequence` 去重序列],
  [`src/memoize.rs`], [192], [`memoize()` 主调度、`Cache`、全局逐出],
  [`src/tree.rs`], [418], [`CallTree` 前缀树：查找/插入/剪枝 + 单元测试],
  [`src/accelerate.rs`], [63], [约束验证加速器（epoch 式清理）],
  [`src/hash.rs`], [11], [128 位 SipHash-1-3 预哈希],
  [`src/testing.rs`], [21], [测试用 hit/miss 标志（`testing` feature）],
  [`macros/src/lib.rs`], [216], [两个属性宏的入口与完整契约文档],
  [`macros/src/memoize.rs`], [174], [`#[memoize]` 展开：校验 + 代码生成],
  [`macros/src/track.rs`], [410], [`#[track]` 展开：Call 枚举/surface/wrapper 生成],
  [`examples/`], [104], [`basic.rs` 最小示例、`calc.rs` 增量解释器示例],
  [`tests/tests.rs`], [733], [13 个集成测试 + 1 个 quickcheck 性质测试],
)

#knowtitle[内容导航]

#table(
  columns: (auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*章节*], [*内容*],
  [一、总体原理与概念模型], [基础记忆化的局限；三大机制；reorderably deterministic 等正确性契约；三类参数],
  [二、跟踪层与输入抽象], [`Tracked`/`TrackedMut` 结构；四个 trait 契约；Input 五件套；MergedSink；加速器；预哈希],
  [三、约束记录与缓存内核], [Constraint 双通道；memoize() 主流程；CallTree 四表结构；查找/插入/剪枝；age 逐出],
  [四、过程宏层], [`#[memoize]` 展开流程与生成骨架；`#[track]` 四个生成物；校验规则全表],
  [五、示例、测试与阅读指南], [两个示例逐行分析；测试版图；三遍阅读法],
  [附录], [关键类型速查表；术语表],
)

#outline(title: [目 录], indent: 1.5em)

#pagebreak()

// ================= 正文 =================
#include "ch1-principles.typ"
#pagebreak()
#include "ch2-tracking.typ"
#pagebreak()
#include "ch3-core.typ"
#pagebreak()
#include "ch4-macros.typ"
#pagebreak()
#include "ch5-guide.typ"
#pagebreak()
#include "appendix.typ"

// ================= 结尾 =================
#v(2em)
#align(center)[
  #text(fill: faintgray, size: 0.9em)[
    —— 全文完 ——\
    愿这份指南帮你啃下 comemo 的每一行代码。\
    最后修订：2026年8月1日
  ]
]
