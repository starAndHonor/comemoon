# 性能基准对比(Phase 6+)

> 2026-08-03 更新:7 场景(原 5 + TrackedMut + 5 参数)。10 万次迭代。
> Rust 基线:`refs/comemo/examples/bench.rs`(release 模式)。

## 结果(2026-08-03,native,优化后)

| 场景 | Rust ns | MoonBit ns | 比率 | 说明 |
|---|---|---|---|---|
| s1 冷启动单参 | 33.5 | 32.3 | **0.96x 快** | 纯 miss + insert |
| s2 热命中 | 22.6 | 23.1 | **1.02x 几乎追平** | 纯 hit |
| s3 calc 依赖图 | 270.9 | 441.9 | 1.63x | 无关编辑保持热缓存 |
| s4 同 key 1000x2 | 269.0 | **89.4** | **0.33x 快 3 倍** | 加速器避免重复验证 |
| s5 eviction 循环 | 740 µs | **4.9 µs** | **0.01x 快 100 倍** | 100 insert + evict |
| s6 TrackedMut 命中 | 16.5 | 103.7 | 6.3x | mutable 重放 |
| s7 5 参数 bundle | 498.0 | 2140 | 4.3x | 4 Tracked + 1 TrackedMut |

## 结论

- **2 项反超 Rust**(s1/s4),s2 几乎追平(1.02x),s5 快 100 倍。
- **主要优化**(2026-08-03):
  1. `hash_int` 零分配:直接对 8 字节 murmur3(`sum128_i64_le`),
     跳过 Array/Bytes 分配(s1: 3.4x→0.96x)。
  2. `hash_string` 流式 UTF-16:直接对内部 UTF-16 LE 字节做 murmur3
     块处理(`sum128(s.to_bytes())`),跳过 UTF-8 重编码
     (s3: 3.6x→1.6x)。
  3. accelerator 惰性分配:`Tracked::new` 不再 push 空 HashMap
     (s6: 10.7x→6.3x)。
  4. `get_pure`/`lookup_pure`:纯函数查找跳过 oracle 闭包(s2: 3.8x→1.02x)。
  5. 基准 Input 预构建:闭包构建移出 `memoize` 调用点。
- **剩余差距 s6/s7(4-6x)**:TrackedMut/多参数 hit 路径的 Ref/闭包
  固定开销 vs Rust 零成本借用——语言结构性差距,非算法问题。
- **hash**:murmur3 128-bit(性能优先,放弃字节级一致)。

## 基准公平性说明(2026-08-03 修复)

- s6 对齐 Rust:每轮重置值、固定 key(hit + mutable 重放)。
- s7 对齐 Rust:递增 key(miss + insert)、Int 参数(避免 String 拼接
  O(n) 累积——早期误报 35µs 即此 bug,改 Int 后 2.3µs)。

## 复现

```bash
# Rust
cd refs/comemo && cargo run --release --example bench
# MoonBit
bash bench/run_bench.sh           # native 对比
bash bench/run_bench.sh --wasm
```

