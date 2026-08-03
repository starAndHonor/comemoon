# 差距修复计划(comemo 最新版对齐)

> 状态:✅ G1+G2 已完成,2026-08-02。G3-G6 记录为已知限制/不适用。目标:对齐 comemo 最新 commit `5944487` 的 API 与行为,
> 补齐 Typst 实际使用暴露的 3 个缺口。参考实现:`refs/comemo`(最新),`refs/typst`(下游)。

## 差距清单(按优先级)

| # | 缺口 | Typst 使用证据 | 影响 |
|---|---|---|---|
| G1 | **多 tracked 参数**(Multi 0-12 元组) | `compile_impl(world: Tracked<dyn World>, traced: Tracked<Traced>, ...)` | 高:多 tracked 场景无法表达 |
| G2 | **trait 上 track** | `#[comemo::track] pub trait World`、`trait Introspector` | ✅ 已完成 |
| G3 | **带生命周期 impl** | `#[comemo::track] impl<'a> Context<'a>` | 中:生命周期参数 impl |
| G4 | **TrackedMut 独立类型** | `sink.track_mut()`(downgrade/reborrow) | 低:语义已有(call_mut),缺 API |
| G5 | **Constraint::validate 公开** | `constraint.validate(value)` | 低:内部已有加速器验证 |
| G6 | **并发安全** | Rust 有 parking_lot 锁 | 低:wasm 单线程目标,多线程缺失 |

**范围决策**:G1-G3 是"对齐 Typst 实际用法"必需的;G4-G6 记录为已知限制(单线程目标可接受)。

## 依赖顺序

```
G1(Multi) → G2(trait track) → G3(生命周期)→ 验证
```

## G1:多 tracked 参数(Multi 等价物)

### 现状
`Input[C]` 只有单一 Call 类型 → 一个 memoize fn 只能跟踪 1 种 Call。

### 方案:Rust 宏生成的 `MultiCall` 等价物

Rust 的 `Multi<($(A, B, ...))>` 生成:
- `MultiCall<$($param::Call),*>` 枚举(每个 tracked 参数一个变体)
- `call`/`call_mut`/`attach` 按变体分发到对应参数

**MoonBit 无宏 → 生成器产出 Multi 等价物**(扩展 gen.py):

```
# 用户侧:
#comemo.track
struct World { ... }
struct Traced { ... }

# 生成器产出(对每个 memoize 用的 tracked 参数组合):
enum WorldTracedCall {
  World(WorldCall)
  Traced(TracedCall)
} derive(Eq, Hash)

impl RustHashable for WorldTracedCall { ... }  # 变体 tag + 内层 hash
```

### 关键设计

1. **Call 合并枚举**:`MultiCall<C1, C2, ...>` 的 MoonBit 版 = 生成一个合并枚举,每个变体包装一个 tracked 的 Call
2. **Input 扩展**:`Input[C]` 改为支持多个 tracked——但 MoonBit 无元组泛型遍历,所以:
   - **方案 A**:生成器对每个"参数组合"产出专用的 Input 构造(样板但类型安全)
   - **方案 B**:运行时提供 `Input2[C1, C2]`/`Input3[C1, C2, C3]`(2-3 参数,覆盖 Typst 实际场景)
3. **推荐 B**:实现 `Input2`/`Input3`(Typst 最多 3 tracked),生成器选型。arity 上限 = 3(Typst 实测:compile_impl 2 tracked + 1 普通)

### 改动文件
- `lib/memoize.mbt`:加 `Input2[C1,C2]`/`Input3[C1,C2,C3]` + `memoize2`/`memoize3`
- `gen/gen.py`:识别多 tracked 参数的 memoize,产出合并 Call 枚举 + 选型 Input2/3
- `lib/comemo_gen.mbt`:生成产物
- 测试:`gen_test.mbt` 加多参数场景(World + Traced)

## G2:trait 上 track(✅ 已完成)

### 实现(2026-08-02)
- 生成器:`#comemo.track` 标记 trait → 泛型 surface `WorldTracked[T]` + `fn[T : World]` 约束 + 显式 `World::method(v, ...)` 调用
- 测试:`g2_trait_track`(双实现共享跟踪逻辑)+ `g2_generated_trait_track`(生成 API)
- 22/22 测试全绿

### 经验
- trait 方法格式 `fetch(Self, ...)`(无 fn 前缀)→ 生成器独立正则
- 跨包 trait 泛型约束有可见性限制 → 测试内 trait 需同文件定义

### 可行性验证记录

### 可行性验证(2026-08-02)
独立测试确认:trait 方法经 `Tracked[T, WorldCall]` + `fn[T : World]` 泛型约束
+ `World::query(w, s)` 显式调用,编译运行正常(输出 3 = "abc".length())。

### 现状
`#comemo.track` 只支持 struct;Typst 用 `#[track] pub trait World`。

### 方案
生成器解析 `#comemo.track` 标记的 trait(而非 struct):
- trait 方法 → Call 枚举变体(同 struct 路径)
- surface 包装类型 = trait 的泛型包装 `WorldTracked[T]`
- Tracked 值类型 = 泛型 `T`(实现 trait),不是具体 struct

### MoonBit 限制
trait 不能作类型参数(之前验证过)→ `Tracked[A, C]` 的 A 必须具体类型。
**解法**:surface 用泛型 `struct WorldTracked[T] { t : Tracked[T, WorldCall] }`,方法约束 `fn[T : World]`。

### 改动文件
- `gen/gen.py`:识别 trait 标记 → 泛型 surface + 方法约束
- 测试:复用 `test_types.mbt` 的 Loader trait 场景扩展

## G3:带生命周期 impl

### 现状
`#comemo.track` 假设无生命周期;Typst 用 `impl<'a> Context<'a>`。

### 分析(2026-08-02 修正)
拆成两种情形:

| 情形 | 支持 | 理由 |
|---|---|---|
| **内部借用** `Context<'a>`('a 只用于内部 `&'a` 字段) | 不适用 | MoonBit 值语义:内部引用用 `Ref[X]` 持有,无需生命周期参数。Typst 的 Context/Locator 均属此类(`'a` 来自 `StyleChain<'a>` 内部 `&'a [..]`) |
| **外部类型参数** `Context<'a, T>`(T 是真实外部类型) | ✅ 可支持 | 等价 MoonBit `Context[T]` + 泛型 impl(已实测:`struct Context[W]` + `fn[W] Context::name` 编译运行正常) |

**结论**:Typst 场景(内部借用)在 MoonBit 中确为"不适用"——但不是因为"无生命周期",而是内部借用由 `Ref[X]` 替代。若未来遇到真实的外部类型参数情形,生成器需扩展解析 `struct Name[TypeParams]`,当前未实现。

## G4-G6:记录为已知限制

| 缺口 | 处理 |
|---|---|
| TrackedMut 独立类型 | 记录:downgrade/reborrow 等价物(`Tracked::get` + `call_mut`),不单独实现 |
| Constraint::validate 公开 | 记录:内部 validate(加速器)已覆盖行为 |
| 并发安全 | 记录:wasm 单线程目标;多线程需锁,未来工作 |

## 验证策略

每步后 `moon check` + `moon test`:

1. **G1 后**:`gen_test` 加多 tracked 场景(World + Traced),验证:
   - 两个 tracked 参数的调用都被记录
   - 改 A 的 tracked 值只失效 A 相关的调用序列
   - 与 Rust `test_calc` 的嵌套语义一致
2. **G2 后**:trait track 场景(仿 Loader)验证:
   - trait 方法被跟踪
   - 泛型 surface 可实例化多个实现
3. **最终**:20 现有测试 + 新增测试全绿;CI 通过

## 工作量

- G1(核心):~1.5 小时(Input2/3 + 生成器扩展 + 测试)
- G2:trait track ~1 小时
- G3:记录(不实现)
- 验证 + 文档:~30 分钟
- 总计:~3 小时
