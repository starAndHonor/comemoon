# 性能基准对比(Phase 6+)

> 2026-08-03 更新:7 场景(原 5 + TrackedMut + 5 参数)。10 万次迭代。
> Rust 基线:`refs/comemo/examples/bench.rs`(release 模式)。

## 结果(2026-08-03,native)

| 场景 | Rust ns | MoonBit ns | 比率 | 说明 |
|---|---|---|---|---|
| s1 冷启动单参 | 31.5 | 67.7 | 2.2x | 纯 miss + insert |
| s2 热命中 | 16.0 | 58.4 | 3.7x | 纯 hit |
| s3 calc 依赖图 | 230.5 | 887.0 | 3.9x | 无关编辑保持热缓存 |
| s4 同 key 1000x2 | 297.9 | **149.2** | **0.50x 快 2 倍** | 加速器避免重复验证 |
| s5 eviction 循环 | 724 µs | **9.0 µs** | **0.01x 快 80 倍** | 100 insert + evict |
| s6 TrackedMut 命中 | 16.0 | 176.3 | 11.0x | mutable 重放 |
| s7 5 参数 bundle | 499.9 | 2310.0 | 4.6x | 4 Tracked + 1 TrackedMut |

## 结论

- **增量场景仍大幅领先**:s4(同 key)快 2 倍,s5(eviction)快 80 倍。
- **冷路径慢 2-4x**(s1-s3):闭包分配 + Ref 间接是剩余瓶颈;纯 hit 路径
  (s6)慢 11x 是 MoonBit 闭包/Ref 固定开销 vs Rust 零成本借用。
- **5 参数(s7)慢 4.6x**:与单参数一致的冷路径差距,非参数数量缩放问题。
- **hash**:已切 murmur3 128-bit(性能优先,放弃字节级一致)。

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

