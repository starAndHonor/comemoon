# Benchmark: comemo (Rust) vs comemoon (MoonBit)

## Run

```bash
bash bench/run_bench.sh          # native (推荐)
bash bench/run_bench.sh --wasm   # wasm
```

Rust 侧:`cargo run --release --example bench`(refs/comemo)
MoonBit 侧:`moon bench --target native`(bench_wbtest.mbt)

两套基准跑**完全相同的场景序列**,输出统一解析为 ns/iter 对比。

## 场景

| # | 场景 | 测量内容 |
|---|---|---|
| s1 | cold_single | 单参 memoized fn,新参数(部分命中)——lookup+insert 路径 |
| s2 | warm_hits | 同参数重复调用——热缓存命中路径 |
| s3 | calc_unrelated_edit | calc 依赖图,改无关文件仍命中——tracked 失效粒度 |
| s4 | same_key_1000x2 | 1000 同 key 上下文验证两遍——加速器 O(1) 验证 |
| s5 | evict_cycle | 100 次 insert + evict(10)——驱逐路径(⚠️ 数值不可靠,见下) |

## 结果(2026-08-02, native)

| 场景 | Rust ns/iter | MoonBit ns/iter | 比值 | 结论 |
|---|---|---|---|---|
| s1_cold_single | 27.9 | 107 | 3.8x | MoonBit 慢 |
| s2_warm_hits | 21.4 | 81 | 3.8x | MoonBit 慢 |
| s3_calc_unrelated_edit | 235 | 1070 | 4.6x | MoonBit 慢 |
| s4_same_key_1000x2 | 295 | 199 | **0.67x** | **MoonBit 快 1.5x** |
| s5_evict_cycle | 743 ms | 10.8 µs | 0.01x | **无效**(测量污染) |

## 解读

### 慢的场景(s1-s3):hash 一致性是主因

MoonBit 为与 Rust hash 完全一致,实现了纯 MoonBit 的 SipHash13(每次
~50ns 基础 + 字符串逐字节)。单次 memoize 调用中 hash 占大头:

- hash_int ≈ 53ns、hash_string(11 字符)≈ 104ns
- s1/s2 每次调用 1 次 hash → 慢 ~4x 主要来自 hash
- s3 calc 含递归 + 多次字符串 hash → 4.6x

### 快的场景(s4)

- **s4 快 1.5x**:加速器让重复验证 O(1),抵消 hash 成本(核心场景)

### s5 测量污染(已确认)

`refs/comemo` 的 `#[memoize]` cache 是全局 static。s1-s3 运行后,全局
EVICTORS 注册了多个大 cache(s1 的 double 有 ~1000 entry)。s5 的
`evict(10)` 遍历**所有**注册 cache,包括 s1-s3 的——单测 evict 本身仅
95µs/1000 次(见 evictprobe),s5 慢是**前序场景污染**,非真实驱逐成本。
**s5 数值无效,排除出对比结论**。

## 性能权衡总结

- **hash 与 Rust 完全一致**(硬性要求)导致 s1-s3 慢 4-5x
- **核心增量计算场景(s4)仍快于 Rust**
- 若需恢复 s1-s3 性能:ASCII 快路径、批量字节处理、或 FFI SipHash

## 已知限制

- MoonBit 计时精度(毫秒级 API)不足以测 µs 级单次;用 moon bench 的
  自动迭代统计均值
- s5 的 Rust 数值异常大,怀疑测量偏差,待排查
- wasm 目标(默认 preferred_target)性能显著差于 native(UInt64 模拟)
