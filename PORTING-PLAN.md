# comemoon 移植方案(已确定)

> 状态:已决策,2026-08-02。目标:用 MoonBit 重写 Rust `comemo` v0.5.0(增量计算/约束记忆化),追求更好的速度与内存占用。
> 参考实现:`refs/comemo/`(行为契约)。概念笔记:`NovaForge-Output-comemo/`。

## 核心决策:无宏,用官方构建时代码生成

MoonBit(0.1.20260724)明确不支持过程宏:

- `macro` 是保留关键字("reserved for possible future use"),`$` 语法不存在
- trait 不能带类型参数、无关联类型(`type Call` 不支持)、无 trait object(`&dyn Sink` 不可行)
- 无自定义 derive(只有内置 Eq/Compare/Debug/Hash 等)

但官方文档明确:"MoonBit is designed not to support runtime reflection. **We prefer to use compile-time code generation**",并提供两个官方机制支撑编译期代码生成。**本方案即采用这两条官方机制**,不发明私有惯例。

## 机制一:`rule` + `dev_build` 构建钩子(官方,已实测)

- `moon.mod` 声明模块级可复用规则:`rule(name: "comemo-gen", command: "moon run gen -i $input -o $output")`
- `moon.pkg` 声明生成步骤:`dev_build(rule: "comemo-gen", input: "user_code.mbt", output: "comemo_gen.mbt")`
- 在 `moon check` / `moon build` / `moon test` **之前**自动运行;`$input`/`$output` 由 moon 注入,命令以模块根为 cwd
- 生成的 `.mbt` 参与编译、可被其他包导入(**已验证**:生成 `pub fn` 后可 `@pkg.fn()` 调用)
- 文档原话:"Commit the generated output files to the repository so downstream users can build against them directly" → **生成文件必须提交**,下游用户零依赖、不执行任意命令(安全设计)
- 规则可声明在包级(moon.pkg,仅本包可见)或模块级(moon.mod,全模块可见);解析优先级:包级 > 模块级
- 另有 `scripts.postadd`(模块添加后运行)与 `--moonbit-unstable-prebuild`(实验性,慎用)可参考

## 机制二:user-defined attribute(官方)

`#comemo.track` / `#comemo.memoize` 形式,编译器忽略但外部工具可解析源码使用。生成器据此定位需要生成样板的声明。

## 用户侧代码形态(样板 ≈ 0)

```mbt
#comemo.track
struct Files { data : String }

impl Files {
  fn read(self, name : String) -> String { ... }   // 普通方法,无需包装
}

#comemo.memoize
fn evaluate(script : String, files : Files) -> Int {
  let a = files.read("alpha.calc")                 // 调用点与 Rust 完全一致
  ...
}
```

生成器产出(提交仓库):Call 枚举、`tracked()` helper 包装方法、缓存声明、memoize 调用包装。

## 运行时层(纯 MoonBit,不依赖宏与 trait object,与 Rust 一一对应)

| Rust 模块 | MoonBit 替代 | 备注 |
|---|---|---|
| `memoize.rs` (`Cache`, `memoize`, `evict`) | `cache.mbt` | `Cache[K, O]` 泛型结构体;顶层 `Ref` 可变状态替代 `static` |
| `track.rs` (`Track`/`Sink`/`Tracked`) | `tracked.mbt` | **闭包替代 `&dyn Sink`**:`Tracked[A, C] { value : A; record : Ref[Option[(C, Int) -> Unit]] }`;`tracked()` helper 每方法 1 行样板;无记录器时零开销快路径 |
| `tree.rs` (`CallTree`) | `tree.mbt` | 纯数据结构,直接移植(inner/leaves slab、edges map、NodeId isize 编码) |
| `input.rs` (`Input`, `Multi`) | `input.mbt` | 泛型元组直接支持 arity 0-N(MoonBit 原生元组) |
| `constraint.rs` (`Constraint`, `CallSequence`) | `constraint.mbt` | 纯数据结构,直接移植 |
| `hash.rs` (SipHash13 128-bit) | `hash.mbt` + `murmur3_*.mbt` | **murmur3 x64_128**(vendored from moonbit-community/murmur3):128-bit `UInt128{hi,lo}` 值类型,快 ~1.7x,不再与 Rust 字节一致(进程内 hash,一致性非必需)。编码辅助(write_rust_*/append_*)保留。 |
| `accelerate.rs` | `accelerate.mbt` | 全局 `Ref` 数组替代 RwLock + AtomicUsize |
| `testing.rs` (hit/miss oracle) | `testing.mbt` | 全局 `Ref[Bool]`;注意 Rust 测试全 `#[serial]`,MoonBit 无等价物,需 per-test 重置 |

**必须保留的语义**:键 = 参数哈希 + 调用序列;顺序无关的不可变调用集验证;`TrackedMut` 可变调用命中后重放;`enabled` 绕过;age 驱逐(evict 同时清空加速器);debug panic(非确定性、不纯 tracked 方法);递归 memoize 命中同一缓存。

**UInt128 迁移计划(2026-08-02)**:hash 从 64-bit SipHash13 切换到 128-bit murmur3(性能快 13x,保留 128-bit 键)。完整文件清单与分层推进步骤见 **`MIGRATION-UINT128.md`**。

**Hash 复刻关键决策(2026-08-02)**:
- 用户要求 hash 与 Rust 完全一致(非仅自洽)。实现 `siphash.mbt`(SipHash-1-3 128-bit,字节级复刻 siphasher crate)+ `hash.mbt`(Rust std Hash 编码)。
- **MoonBit 禁止对核心类型(Int/String/Unit)实现用户自定义 trait** → 核心类型用顶层函数(`hash_int`/`hash_string`/`hash_unit`),自定义类型(Call 枚举)用 `RustHashable` trait(生成器产出 pub impl)。
- trait 与 impl 都需 `pub`,枚举需 `pub(all)`,blackbox 测试(独立编译单元)内不能 impl trait → 测试类型定义在主包 `test_types.mbt`。
- Rust 的流式 Hash vs MoonBit 的返回值:复合类型用 `write_rust`(流式编码到字节数组)而非独立 hash,生成器产出 `write_rust` 流式实现。
- `Recorder[C]` 回调签名 `(C, call_hash, ret, mutable)`——call_hash 由 `Tracked::call` 计算(有 RustHashable 约束),`Constraint::record` 直接接收。

**关键移植发现(2026-08-02,来自 test_mutable_nested)**:
- Rust 的命中重放走 `input.call_mut`,而 `TrackedMut::call_mut` **会 emit 到外层 sink**——嵌套时内层 b 的 hit 重放会把自己的可变调用**传播给外层 a 的 constraint**(a.mutable 因此收到 Add(3))。MoonBit 的 `replay_mut` 必须**经 `tracked.call_mut` 执行**(走 record 链),而非裸执行副作用,否则外层 mutable 记录丢失。
- `TrackedMut` 的验证(oracle)也执行副作用(Rust `TrackedMut::call` 执行 `value.call`);但 mutable call 不进树路径(只进 entry.mutable),验证时不重放。

## 项目结构

```
comemoon/
├── moon.mod                    # 模块配置 + rule(comemo-gen)
├── lib/                        # 运行时库(唯一包)
│   ├── moon.pkg                #   import + dev_build(comemo-gen)
│   ├── siphash.mbt             #   SipHash-1-3 128-bit 算法
│   ├── siphash_stream.mbt      #   增量 SipHash
│   ├── hash.mbt                #   Rust Hash 编码 + RustHashable trait
│   ├── tree.mbt                #   CallTree
│   ├── constraint.mbt          #   CallSequence / Constraint / Recorder
│   ├── tracked.mbt             #   Tracked 包装
│   ├── cache.mbt               #   Cache / evict
│   ├── memoize.mbt             #   memoize 入口 + Input
│   ├── accelerate.mbt          #   验证加速器
│   ├── testing.mbt             #   hit/miss oracle
│   ├── util.mbt                #   parse_ok 等辅助
│   ├── test_types.mbt          #   测试用类型(主包定义,因测试不能 impl trait)
│   ├── user_tracked.mbt        #   用户侧:#comemo.track 标记 + 普通方法
│   ├── comemo_gen.mbt          #   dev_build 生成(提交仓库)
│   └── *_test.mbt / *_wbtest.mbt  # 测试(同包)
├── gen/gen.py                  # 代码生成器(Python)
├── bench/                      # 基准:run_bench.sh + 报告
├── cmd/main/                   # 可执行示例(calc 依赖图 demo)
└── refs/comemo/                # Rust 参考实现(行为契约)
```

## 生态先例

- **moonpack**(001-Elsa/MoonBit-Submit):MoonBit 原生 schema-first 序列化库,采用 `src/codegen/`(MoonBit 写生成器)+ CLI 入口 + `generated/` 目录(生成文件提交)模式。本方案与其一致。
- 生成器用 MoonBit 写(而非 Python 等),保证工具链单一、可随项目编译分发。

## 开发顺序建议

> 总体迁移路线图(阶段划分、测试契约映射、风险、完成定义)见 **`MIGRATION-PLAN.md`**。本节仅列模块级顺序:

1. `hash.mbt`(SipHash13)+ `tree.mbt`(CallTree):纯数据结构、无宏依赖,先落地并用 Rust 的 `test_call_tree`/`test_call_tree_quickcheck` 语义验证
2. `constraint.mbt`(CallSequence)+ `tracked.mbt`(Tracked + helper):核心跟踪机制
3. `cache.mbt`(memoize/evict)+ `input.mbt`:组合成完整 memoize 流程
4. `accelerate.mbt`:性能优化(非功能性,最后)
5. `gen/` 生成器 + `rule`/`dev_build` 接线:把用户样板归零
6. 移植测试契约(见 AGENTS.md Testing & QA):17 个 Rust 测试 + 2 个 quickcheck 属性

## 验证记录

- 2026-08-02:`rule` + `dev_build` 钩子在 moon 0.1.20260724 实测通过:`echo ... > $output` 生成 `generated.mbt` → `moon clean && moon run cmd/main` 输出 42(生成文件被编译、跨包引用成功)
- 同一会话实测确认:闭包捕获、函数字段、`derive(Hash, Eq)`、`HashMap`、顶层 `Ref` 状态均可用;`trait Track[C]`、关联类型、trait object 均不可用
