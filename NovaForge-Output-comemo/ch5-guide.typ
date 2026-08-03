// 第五章：示例、测试体系与源码阅读指南
#import "preamble.typ": *

= 五、示例、测试体系与源码阅读指南

#knowtitle[定位：示例与测试是 comemo 的"活文档"——先读示例建立直觉，再用测试反查精确语义]

`examples/basic.rs`（37 行）展示无跟踪的纯 memoization 最小用法；`examples/calc.rs`（67 行）用玩具脚本语言演示增量计算的核心价值；`tests/tests.rs`（733 行）把每个公开机制固化为可执行的行为契约，其中 `test!` 宏（#src[tests/tests.rs:12-21]）直接断言"这次调用是 Hit 还是 Miss"。支撑这一断言能力的是 `testing` feature。

== examples/basic.rs 逐行讲解（最小上手例子）

只用到 `#[memoize]`，不涉及 Tracked 输入，证明 comemo 退化为普通 memoizer 也能用。

- `empty(); // [Miss]`（#src[examples/basic.rs:7]）：缓存为空，首次必 miss；第 8、9 行 `[Hit]`：无参数，键恒定，此后永远命中。
- `double(2)` miss → `double(4)` miss（参数不同 → 键不同）→ `double(2)` hit（#src[:11-13]）。
- `sum(2, 3)` 与 `sum(4, 2)` 是不同的键（#src[:15-18]）——memoize 不做参数交换归一化。
- 要点：每个被标注的函数拥有独立的静态缓存，无需任何结构改造。

== examples/calc.rs 的 Hit/Miss 逐条分析

calc 语言支持 `+` 加法和 `eval <path>` 引用其他文件。`evaluate` 被 `#[memoize]` 标注（#src[examples/calc.rs:40-41]），递归调用自身求值子脚本；`Files` 是被跟踪的输入，`read` 经 `#[track]`（:56-59）成为受约束的访问点，`write` 是普通可变方法（:65-68）。

+ *第 1 次（:18-19）`[Miss]` → 7*：缓存为空，顶层必 miss。执行中 alpha 通过 `files.read` 读 beta（约束：beta 的内容哈希），递归求值得 7。
+ *第 2 次（:21-23）`[Miss]` → 5*：顶层键 `"eval beta.calc"` 从未出现过 → 顶层 miss。但递归调用 `evaluate("2 + 3", files)` 的键与约束和第 1 次完全一致，#key[内层命中]，beta 的求值没有重跑——顶层 miss ≠ 全部重算。
+ *第 3 次（:28-29）`[Hit]` → 7*：`gamma.calc` 被改写，但 alpha 的执行只约束了 beta 的内容，gamma 不在约束集合里 → 顶层直接命中。#key[无关文件的改变不会引起重算]。
+ *第 4 次（:34-35）`[Miss]` → 48*：beta 被改写为 `"4 + eval gamma.calc"`，约束包含 beta 的旧内容哈希，重验失败 → miss 并重新执行，得 2 + (4 + 42) = 48。

#formula[顶层 Hit/Miss 由"参数键 + 上次执行留下的约束集合是否仍满足"决定；子表达式的复用来自递归调用各自独立的缓存条目。]

== src/testing.rs 与 testing feature 的联动

- `src/testing.rs`（21 行）是线程局部布尔标志：`LAST_WAS_HIT: Cell<bool>`（:3-5），公开读取器 `last_was_hit()`（:9-11），内部写入器 `register_hit()` / `register_miss()`（:14-21）。
- 写入点在 `src/memoize.rs`：enabled 旁路（:41-42）与重算出口（:88-89）`register_miss()`；命中路径（:61-62）`register_hit()`。三处都用 `#[cfg(feature = "testing")]` 门控，#key[生产构建零开销]。
- `testing = []` 是空 feature（#src[Cargo.toml:46]）；`[[test]] required-features = ["macros", "testing"]`（#src[Cargo.toml:61-64]）意味着#key[裸 `cargo test` 会静默跳过整个集成测试套件]——必须 `cargo test --all-features`。
- 测试侧的 `test!` 宏（#src[tests/tests.rs:12-21]）先断言结果值，再断言 `last_was_hit()`，把命中/未命中变成一等测试断言。thread_local + `#[serial]` 避免并行测试串扰（缓存是函数级静态全局状态）。

== tests/tests.rs 测试版图

共 13 个 `#[test]` + 1 个 `#[quickcheck]`，全部 `#[serial]`：

#table(
  columns: (auto, auto, 1fr),
  fill: (_, row) => if row == 0 { sectionbg },
  [*类别*], [*测试函数*], [*覆盖的行为契约*],
  [基础 memoize], [`test_basic` :26], [空参/多参/递归 fib 的 Hit-Miss 序列；大计算只算一次],
  [跟踪式增量], [`test_calc` :89], [calc 全场景，比 example 多 46/48/86 三步演进（:96-104）],
  [缓存逐出], [`test_evict` :123], [`evict(2)` 需多次调用才逐出（分代），`evict(0)` 立即全清],
  [跟踪 trait 对象], [`test_tracked_trait` :149], [`Tracked<dyn Loader>`、`#[track]` 用于 trait],
  [memoize 方法], [`test_memoized_methods` :181], [`&self` 方法与按值 self 方法],
  [参数形态], [`test_kinds` :207], [返回值借用 self/参数；tracked 返回值带生命周期；空 impl 合法],
  [生命周期与链式], [`test_lifetime` :284 / `test_chain` :312 / `test_variance` :339], [带生命周期的被跟踪类型；链式结构前缀共享时 Hit；`Tracked<T>` 对 T 协变],
  [可变跟踪重放], [`test_purely_mutable` :377 / `test_mutable_nested` :414], [`TrackedMut` 的 emit 在命中时被重放；嵌套 memoize 间传递 TrackedMut 一起重放],
  [同键多约束], [`test_many_with_same_key` :442], [同一键下多条不同约束条目，重验能挑出仍成立的那条],
  [确定性检查], [`test_non_deterministic` :486 / `test_deterministic_out_of_order` :516], [约束依赖路径的非确定函数 debug 下 panic；乱序但总体确定的函数允许],
  [纯度检查], [`test_impure_tracked_method` :569], [tracked 方法内部有副作用时 debug 构建 panic],
  [条件禁用], [`test_with_disabled` :593], [`#[memoize(enabled = ...)]`：小输入不缓存，大输入正常],
  [性质测试], [`test_memoize_quickcheck` :607], [随机输入下 memoize 版与朴素直算版结果与副作用完全一致],
)

#infobox[quickcheck 验证的不变量不是性能，而是#key[语义等价性]——任意随机输入下，memoize 版（含 Tracked 读取与 TrackedMut 变更重放）与朴素直算版产生相同返回值和相同副作用。这是整个 crate 最重要的性质：缓存不可观察。]

注意：没有真正的多线程并发测试；最接近的是 `test_deterministic_out_of_order`，其注释明确"内部使用多线程的确定性函数"是被支持的场景（#src[tests/tests.rs:511-513]）。

== 源码阅读指南：三遍阅读法（本指南的压轴）

#knowtitle[第一遍：文档与示例——建立"它做什么"的直觉]

路径：README.md → examples/basic.rs → examples/calc.rs。

- *目标*：理解 `#[memoize]` / `#[track]` 的表面语法，以及 Hit/Miss 的判定直觉（参数键 + 约束重验）。
- *预期收获*：能解释 calc.rs 四个 assert 各自的 Hit/Miss 原因。
- *动手验证*：`cargo run --example calc`；给 calc.rs 加一个自己的 assert（比如改 gamma 后再 eval alpha），用直觉预测 Hit/Miss 再跑一遍对照。

#knowtitle[第二遍：运行时核心——理解"它怎么做到"]

路径：src/lib.rs（模块导览与公开 API，:99-103 看 feature 门控与 re-export）→ src/track.rs → src/input.rs → src/constraint.rs → src/tree.rs → src/memoize.rs（:17-93 是核心路径）→ src/accelerate.rs → src/hash.rs。

- *目标*：能说清一次 memoized 调用的完整生命周期：查键 → 约束重验 → 命中返回 / 重算并记录新约束。
- *卡住时的调试建议*：
  - 开一个最小复现（复制 basic.rs 结构），开 `testing` feature 后在每次调用后打印 `comemo::testing::last_was_hit()`，观察预期与实际的分歧点；
  - 注意大量正确性检查（非确定性、不纯跟踪方法）只在 *debug_assertions* 下启用——release 构建行为不同，调试时别用 `--release`；
  - 读 memoize.rs 时对照 tests.rs 的 `test!` 序列，每条 Hit/Miss 都能在 memoize.rs 里找到对应分支。

#knowtitle[第三遍：宏与测试——理解"糖怎么化"与"契约是什么"]

路径：macros/src/lib.rs → macros/src/memoize.rs → macros/src/track.rs → macros/src/utils.rs → tests/tests.rs（按测试版图挑感兴趣的读）。

- *目标*：把第二遍看到的运行时 API 与宏生成的代码对上号；知道每个公开行为有哪个测试兜底。
- *反查契约的方法*：想确认某机制的语义时，先 grep 测试函数名（如 `grep -n "fn test_evict" tests/tests.rs`），读它的 `test!` 序列——那是该机制最精确、可执行的规格说明；再回运行时源码找实现。遇到边缘行为，`should_panic` 消息（#src[tests/tests.rs:485]）往往比文档更权威。

== 易错点

- *裸 `cargo test` 会"假绿"*：必须 `cargo test --all-features`（CI 也是这么跑的）。
- *`last_was_hit` 是线程局部 + 串行假设*：自己写测试时别忘了 `#[serial]`。
- *示例注释的 "Miss" 有歧义风险*：calc.rs 第 2 个 `[Miss]` 指顶层 miss，但内层 beta 求值是命中的。读测试版 `test_calc` 更精确。
- *debug 与 release 的行为差异*：非确定性检查与不纯方法检查只在 `debug_assertions` 下存在。这是刻意的性能权衡：正确性护栏是开发期工具，运行时零开销；代价是 release 下非确定性函数会静默产生无效缓存。
- *逐出不是即时的*：`evict(2)` 要连续调用多次才生效——逐出按"代"工作；`evict(0)` 才是立即全清。读 evict 实现前先看 `test_evict`，否则容易误判为 bug。
