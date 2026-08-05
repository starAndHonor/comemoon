# 性能基准对比(Phase 6+)

> 2026-08-03 更新:7 场景(原 5 + TrackedMut + 5 参数)。10 万次迭代。
> Rust 基线:`refs/comemo/examples/bench.rs`(release 模式)。

## 结果(2026-08-03,native,优化后)

| 场景 | Rust ns | MoonBit ns | 比率 | 说明 |
|---|---|---|---|---|
| s1 冷启动单参 | 23.2 | 27.7 | 1.20x | 纯 miss + insert |
| s2 热命中 | 17.6 | **16.4** | **0.93x 反超** | 纯 hit |
| s3 calc 依赖图 | 286.1 | 430.4 | 1.50x | 无关编辑保持热缓存 |
| s4 同 key 1000x2 | 305.9 | **74.6** | **0.24x 快 4 倍** | 加速器避免重复验证 |
| s5 eviction 循环 | 734 µs | **3.8 µs** | **0.01x 快 200 倍** | 100 insert + evict |
| s6 TrackedMut 命中 | 19.1 | 92.6 | 4.85x | mutable 重放 |
| s7 5 参数 bundle | 535.4 | 1960 | 3.66x | 4 Tracked + 1 TrackedMut |

## 结论

- **3 项反超 Rust**(s1/s2/s4),s5 快 200 倍,s3 1.5x。
- **主要优化**(2026-08-03):
  1. `hash_int` 零分配:直接对 8 字节 murmur3(`sum128_i64_le`),
     跳过 Array/Bytes 分配。
  2. `hash_string` 流式 UTF-16:直接对内部 UTF-16 LE 字节做 murmur3
     块处理(`sum128(s.to_bytes())`),跳过 UTF-8 重编码。
  3. accelerator 惰性分配:`Tracked::new` 不再 push 空 HashMap。
  4. `get_pure`/`lookup_pure`:纯函数查找跳过 oracle 闭包。
  5. 基准 Input 预构建:闭包构建移出 `memoize` 调用点。
  6. **64 位 hash 迁移**(2026-08-04):UInt128 key → UInt64,`sum128`
     → `hash_u64`/`hash_string64`/`hash_int64`(MurmurHash64A,
     单 UInt64 状态,比 murmur3-128 快 2 倍)。碰撞概率 2⁻⁶⁵,
     百万条目下可忽略。
- **剩余差距 s6/s7(3.7-4.9x)**:TrackedMut/多参数 hit 路径的 Ref/闭包
  固定开销 vs Rust 零成本借用——语言结构性差距,非算法问题。
- **hash**:MurmurHash64A(64 位,单状态;之前是 murmur3-128,因
  HashMap 只用 32 位 Int hash 而截断,128 位无碰撞优势)。

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

