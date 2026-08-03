# UInt128 迁移计划(从 UInt64 切换到 128-bit hash)

> 状态:✅ 已完成,2026-08-02。目标:hash 从 64-bit(SipHash13 截断)切换为
> 128-bit(murmur3 x64_128),性能提升 ~13 倍,保留 128-bit 键宽度。
> 上次集成因无序替换引发连锁类型错误而回退;本计划按依赖顺序列出全部改动点。

## 核心决策

- **hash 值类型**:`UInt64` → `UInt128`(自定义 `#valtype { hi: UInt64, lo: UInt64 }`,来自 moonbit-community/murmur3)
- **算法**:SipHash13 → **murmur3 x64_128**(`sum128(Bytes) -> UInt128`)
- **内部键**:CallTree/CallSequence/Accelerator 的 map 键全部从 `UInt64` 升为 `UInt128`
- **保持不变的**:`siphash.mbt` / `siphash_stream.mbt` 的**算法内部** UInt64 状态
  (compress 轮函数不涉及 hash 键,保留;若不再使用可删除,见步骤 0)

## 依赖顺序(必须按此执行)

```
murmur3 引入 → UInt128 类型 → hash.mbt 接口 → 运行时消费方 → 生成代码 → 测试 → 文档
```

## 文件清单(14 个,按层分组)

### 第 0 层:新增/基础(无依赖)

| 文件 | 改动 | 说明 |
|---|---|---|
| `lib/murmur3_uint128.mbt`(新) | `UInt128` 结构 + **补 Eq + Hash impl** | 从 murmur3 repo vendor;Eq/Hash 用于 map 键 |
| `lib/murmur3_murmur.mbt`(新) | Digest/BMixer 基础设施 | vendor,不改 |
| `lib/murmur3_murmur128.mbt`(新) | Digest128 流式 hasher | vendor,不改 |
| `lib/murmur3_murmur128_gen.mbt`(新) | `sum128`/`seed_sum128` 一次性 | vendor,不改 |
| `lib/siphash.mbt` / `siphash_stream.mbt` | **删除**(如无其他引用) | SipHash13 被 murmur3 取代;若保留则算法内部 UInt64 不动 |

### 第 1 层:hash 接口(消费方依赖它)

| 文件 | 行 | 改动 |
|---|---|---|
| `lib/hash.mbt` | 23 | `hash()` 返回 `UInt64` → `UInt128` |
| | 30 | `hash128()` 返回 `(UInt64, UInt64)` → `UInt128` |
| | 40, 45 | trait `rust_hash(Self) -> UInt128 = _` + 默认 impl 用 murmur3 |
| | 53, 59, 82, 90, 95, 102 | `hash_int`/`hash_string`/`hash_unit`/`hash_unit_value`/`hash_bool`/`hash_char` 返回 `UInt128` |
| | 139-167 | `append_*_le` 辅助保留(供编码用) |
| | 195-236 | `test_hash_*` 系列返回 `UInt128`;`test_hash_opt`/`test_hash_array` 的 inner 参数类型同步 |
| 新增 | — | `hash_bytes(Array[Byte]) -> UInt128`(murmur3 核心入口) |
| 新增 | — | `hash_zero() -> UInt128`(测试 oracle 占位) |
| 新增 | — | `hash_combine2(a, b) -> UInt128`(多参数 key 组合,替代 `*31+` 运算) |

### 第 2 层:运行时消费方(依赖 hash 接口)

| 文件 | 行 | 改动 |
|---|---|---|
| `lib/constraint.mbt` | 14, 16, 37, 66, 85 | `vec: Array[(C, UInt64)?]`、`map: HashMap[UInt64, Int]`、`ret: UInt64` → `UInt128` |
| | 120 | `Recorder[C] = (C, UInt64, UInt64, Bool) -> Unit` → 两个 `UInt128` |
| | 142-143, 166-167 | `call_hash`/`ret`/`h` 参数 → `UInt128` |
| `lib/tree.mbt` | 18, 22, 257, 266 | `start`/`edges`/`new_edges`/`new_start` map 键 `UInt64` → `UInt128` |
| | 75-76, 112, 117, 201-202 | `key`/`oracle`/`predecessor`/`from` → `UInt128` |
| `lib/tracked.mbt` | 62-63, 106, 126, 153-154 | `call_hash`/`ret_hash` 类型 → `UInt128` |
| `lib/memoize.mbt` | 23, 25, 37, 39, 88-89, 123, 131 | `key`/`oracle`/`call_hash`/`ret` → `UInt128`;`dummy_oracle` 返回 `hash_zero()` |
| `lib/cache.mbt` | 63-64, 79 | `key`/`oracle` → `UInt128` |
| `lib/accelerate.mbt` | 22, 53, 65-66 | 加速器 map `UInt64→UInt128` 键 |

### 第 3 层:生成代码(gen.py 产出)

| 文件 | 改动 |
|---|---|
| `lib/comemo_gen.mbt` | 生成器输出的 `RustHashable impl` 的 `rust_hash` 返回类型同步 |
| `gen/gen.py` | `hash_fn_for()` 映射表:类型→hash 函数名(返回值已是 UInt128,无需改签名生成) |

### 第 4 层:测试(消费方,最后)

| 文件 | 改动 |
|---|---|
| `lib/memoize_test.mbt` | `test_hash_*` 返回类型、`cs.insert(X, N)` 的 ret 转 `UInt128::{hi:0, lo:N.to_uint64()}`、`tree.insert(0, ...)` key 转 UInt128、`fn(_) { 0 }` oracle → `hash_zero()` |
| `lib/tree_wbtest.mbt` | 同上模式;`Op` 的 key/ret 数据转 UInt128 |
| `lib/gen_test.mbt` | oracle/ret_hash 返回类型同步 |
| `lib/bench_wbtest.mbt` | 同上 |
| `cmd/main/main.mbt` | demo 的 key/hash 调用同步 |

### 第 5 层:验证与文档

| 文件 | 改动 |
|---|---|
| `lib/hash.mbt` 测试 | SipHash13 黄金值测试 → **自洽性测试**(确定性、碰撞、不同值不同 hash) |
| `lib/siphash.mbt` 测试 | 若 siphash 删除,其黄金值测试一并删除 |
| `PORTING-PLAN.md` | hash 实现章节更新(murmur3 替代 SipHash13) |
| `bench/moon-vs-rust.md` | 性能预期更新(hash 快 13x) |
| `MIGRATION-UINT128.md` | 完成后标记 ✅ |

## 验证策略

每层完成后立即 `moon check`,0 错误才进入下一层:

1. **第 0 层后**:`moon check` 通过(新文件独立)
2. **第 1 层后**:hash.mbt 单独编译;`hash_int(42)` 返回 UInt128
3. **第 2 层后**:运行时编译通过(此时测试会因类型不匹配报错,预期)
4. **第 3 层后**:生成代码同步
5. **第 4 层后**:`moon test` 全绿(21 个测试,黄金值测试已替换为自洽)
6. **最终**:`moon test --target native` + `moon bench --target native`(对比基准)

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 上次的连锁类型错误 | 本计划按层推进,每层 check 通过才继续;避免全局 regex 替换 |
| `UInt128` 无 `Mul`/`Add` 运算符 | 测试里的 `*31+` 组合改用 `hash_combine2`(已列入第 1 层) |
| `N.to_uint64()` 字面量 Double 问题 | 用 `(N).to_uint64()` 括号包裹(已踩过) |
| 生成代码与手写测试类型不同步 | 第 3 层先于第 4 层,生成器产物先行 |
| murmur3 无 Eq/Hash | vendor 后手动补 impl(已验证可行) |

## 工作量估算

- 第 0-1 层(hash 核心):~30 分钟
- 第 2 层(运行时):~30 分钟
- 第 3-4 层(生成+测试):~40 分钟
- 第 5 层(验证+文档):~20 分钟
- 总计:~2 小时
