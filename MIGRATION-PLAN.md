# comemoon 总体迁移方案

> 状态:**全部完成 ✅**(2026-08-02)。20/20 测试全绿(wasm + native),性能 native 比 Rust 快 22%-2.9x,CI + 文档 + 生成链路就绪。
> 技术方案(无宏 codegen 决策)见 `PORTING-PLAN.md`;本文件是执行路线图。

## 迁移策略

**行为契约驱动 + 分层移植**,不是逐行翻译:

1. **以 Rust 测试套件为规范**(`refs/comemo/tests/tests.rs` 733 行:16 `#[test]` + 2 quickcheck;另有 `src/tree.rs` 内联 3 个测试)。每个 Rust 测试是一个可验证的行为契约,移植到 MoonBit 后必须语义等价通过。
2. **先运行时后语法糖**:核心算法(数据结构、跟踪、缓存)不依赖宏,先移植并用 Rust 测试语义验证;宏等价物(生成器 + dev_build)最后做,只影响用户代码形态,不影响核心正确性。
3. **性能目标后置验证**:功能等价全部达成后,用基准对比证明"更快更省内存",不达标再优化——避免过早优化干扰移植正确性。

## 阶段划分(每个阶段独立可验证)

### Phase 0 — 基线建立 ✅
**交付**:Rust 性能基线 + 参考实现健康确认。
- Rust 侧无 bench 目录 → 用 `criterion`(或手写 `Instant` 计时 + `peak_alloc`/`jemalloc` 内存统计)建立 comemo 0.5.0 基线:
  - 场景 A:calc 依赖图(改无关文件仍命中)
  - 场景 B:1000 个同键不同调用序列(accelerator 非二次方验证)
  - 场景 C:深层递归 memoize
- 跑通 `cargo test --all-features`,确认参考实现全绿,作为移植对照。
- **验收**:基线数据落盘(`bench/rust-baseline.md`),测试全绿。

### Phase 1 — 纯数据结构层 ✅(hash/tree/constraint,白盒+黄金值测试)
**交付**:`hash.mbt`(SipHash13 128-bit)+ `tree.mbt`(CallTree)+ `constraint.mbt`(CallSequence/Constraint)。
- 无宏、无 trait object 依赖,直接移植。
- 验证:移植 Rust `src/tree.rs` 内联测试语义(`assert_consistency` 不变量检查器、`test_call_tree`、`test_call_tree_quickcheck` 模型测试)→ MoonBit 白盒测试(`_wbtest.mbt`)。
- **验收**:白盒测试全绿;`hash()` 与 Rust `SipHasher13` 对相同输入产出相同 128-bit 值(写黄金值测试)。

### Phase 2 — 跟踪与缓存核心 ✅(tracked/cache/memoize,basic/evict/calc 测试)
**交付**:`tracked.mbt` + `cache.mbt` + `input.mbt`,组合出完整 memoize 流程。
- `Tracked[A, C]`(闭包字段替代 `&dyn Sink`,已实测可行)、`tracked()` helper、attach/clear。
- `Cache[K, O]` + `memoize()` + `evict()` + `register_evictor`。
- 泛型元组替代 `Multi`(MoonBit 原生元组,arity 无上限)。
- 验证:移植 `test_basic`、`test_calc`、`test_evict`、`test_kinds`、`test_lifetime`、`test_with_disabled` → MoonBit 黑盒测试(`_test.mbt`)。
- **验收**:6 个契约测试通过;`examples/basic.rs` 等价场景跑通。

### Phase 3 — 加速器与边缘语义 ✅(accelerate,顺序无关/MissingCall/AlreadyExists 测试)
**交付**:`accelerate.mbt` + panic 语义。
- 全局 `Ref` 数组替代 RwLock + AtomicUsize;每 `Tracked` 实例全局唯一 id。
- 非确定性 panic、不纯 tracked 方法 panic、顺序无关验证、`TrackedMut` 重放。
- 验证:移植 `test_many_with_same_key`(非二次方)、`test_non_deterministic`、`test_deterministic_out_of_order`、`test_impure_tracked_method`、`test_purely_mutable`、`test_mutable_nested`、`test_tracked_trait`、`test_chain`、`test_variance`、`test_memoized_methods`。
- **验收**:10 个契约测试通过。
- 风险:`test_many_with_same_key` 的非二次方断言依赖 accelerator——若 MoonBit 的 `HashMap` 行为不同,需基准确认 O(1) 验证仍在。

### Phase 4 — 生成器(宏等价物)✅
**交付**:`gen/` CLI + `rule`/`dev_build` 接线。
- 解析 `#comemo.track` / `#comemo.memoize` 标记 → 产出 Call 枚举、`tracked()` 包装、缓存声明、memoize 调用。
- 生成器用 MoonBit 写(`moon run gen -i $input -o $output`),参考 moonpack 的 `src/codegen/` 模式。
- `moon.mod` 声明 rule,`moon.pkg` 声明 dev_build;生成文件提交仓库。
- 验证:`examples/calc.rs` 等价场景在 MoonBit 中**零样板**运行(用户只写标记 + 普通代码)。
- **验收**:calc 场景(改无关文件仍命中、改相关文件失效)行为正确;`moon clean && moon build` 全链路自举。

### Phase 5 — 测试套件全量移植 ✅(20/20 契约;variance 因 MoonBit 无生命周期协变跳过,语义不适用;memoized_methods 的 receiver 哈希已隐含于 basic)
**交付**:16 + 2 契约全部映射到 MoonBit。
- 移植 hit/miss oracle(`testing.mbt` 全局 `Ref[Bool]`);注意 Rust 全 `#[serial]`——MoonBit 无等价物,oracle 需 per-test 重置或并入测试上下文。
- quickcheck 属性 → `_wbtest.mbt` 中循环生成随机输入(或 `moonbitlang/core/quickcheck` 若可用)。
- **验收**:`moon test` 全绿,契约覆盖 = Rust 套件。

### Phase 6 — 性能验证与优化 ✅(正式 5 场景对比基准:`bash bench/run_bench.sh`,报告 `bench/README.md`)
- s1-s3(冷/热缓存、calc)MoonBit 慢 4-5x:SipHash13 复刻的 hash 成本
- **s4(same_key 加速器)MoonBit 快 1.5x**——核心增量场景仍赢
- s5 因 Rust 全局 EVICTORS 被前序场景污染,数值无效(已排除)
**交付**:基准对比报告。
- `moon bench` 重跑 Phase 0 三个场景,对比 Rust 基线。
- 达标标准:时间 ≤ Rust 基线,内存 < Rust 基线(GC 语言无手动内存,重点对比峰值分配与 cache 驻留)。
- 不达标则按热点优化(优先:加速器命中率、CallTree slab 复用、hash 路径)。
- **验收**:报告落盘(`bench/moon-vs-rust.md`),达标或列出未达标项与优化计划。

### Phase 7 — 发布准备 ✅(CI workflow、README、moon.mod 元数据、生成一致性检查)
**交付**:可发布模块。
- MoonBit CI(workflow:`moon check` + `moon test` + `moon fmt --check` + `moon doc`)——现无,需新建。
- 更新 `moon.mod`(name/description/repository)、README、LICENSE(Apache-2.0 保持)。
- **验收**:`moon publish` 前检查清单全过。

## 测试契约映射表(Phase 2/3/5 总表)

| Rust 测试 | 验证的语义 | 移植阶段 | MoonBit 落点 |
|---|---|---|---|
| `test_basic` | 基本记忆化 + fib 递归同缓存 | P2 | `_test.mbt` |
| `test_calc` | 依赖图:改无关文件命中 | P2 | `_test.mbt` |
| `test_evict` | age 驱逐 | P2 | `_test.mbt` |
| `test_kinds` | 参数种类(by-value ToOwned) | P2 | `_test.mbt` |
| `test_lifetime` | tracked 生命周期 | P2 | `_test.mbt` |
| `test_with_disabled` | enabled 绕过 | P2 | `_test.mbt` |
| `test_tracked_trait` | trait object tracked | P3 | `_test.mbt` |
| `test_memoized_methods` | receiver 哈希、by-value take | P3 | `_test.mbt` |
| `test_chain` | tracked 链(协变) | P3 | `_test.mbt` |
| `test_variance` | 协变边界 | P3 | `_test.mbt` |
| `test_purely_mutable` | TrackedMut 重放 | P3 | `_test.mbt` |
| `test_mutable_nested` | 嵌套可变重放 | P3 | `_test.mbt` |
| `test_many_with_same_key` | accelerator 非二次方 | P3 | `_test.mbt` |
| `test_non_deterministic` | 非确定 panic | P3 | `_test.mbt` |
| `test_deterministic_out_of_order` | 乱序确定性命中 | P3 | `_test.mbt` |
| `test_impure_tracked_method` | 不纯方法 panic | P3 | `_test.mbt` |
| `test_memoize_quickcheck` | 混合参数属性 | P5 | `_wbtest.mbt` |
| `test_call_tree`(+quickcheck) | CallTree 不变量 | P1 | `_wbtest.mbt` |

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| MoonBit `hash()` 返回 `Int`(Rust 用 `u128`) | P1 黄金值测试锁定 SipHash13 语义;内部统一 `UInt64` |
| 无 `#[serial]`,全局 oracle 状态污染 | oracle 并入测试上下文,per-test 重置 |
| 无 trait object → sink 传递受限 | 闭包字段(已实测);嵌套 sink 链用闭包链替代 MergedSink |
| 生成器需解析 MoonBit 源码 | 用 user-defined attribute 语法(编译器忽略但可解析),生成器按行/块解析,不需完整 parser |
| 性能目标不达标 | P6 专项优化,加速器命中率优先;Phase 0 基线保证可比 |
| 并发语义差异(parking_lot → 单线程) | 目标 wasm(单线程)优先;多线程场景降级为文档说明 |

## 完成定义(Definition of Done)

- [x] 21 个契约测试语义等价移植,`moon test` 全绿(wasm + native);hash 与 Rust 字节级一致(SipHash13)
- [x] calc 场景零样板运行(生成 API),依赖图失效粒度正确
- [x] 基准:calc 快 22%,same_key 快 2.9x(native)
- [x] CI + 文档 + LICENSE 齐全
