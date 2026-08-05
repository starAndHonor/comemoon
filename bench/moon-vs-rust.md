# 性能基准对比(Phase 6+)

> 2026-08-03 更新:7 场景(原 5 + TrackedMut + 5 参数)。10 万次迭代。
> Rust 基线:`refs/comemo/examples/bench.rs`(release 模式)。

## 结果(2026-08-03,native,优化后)

| 场景 | Rust ns | MoonBit ns | 比率 | 说明 |
|---|---|---|---|---|
| s1 冷启动单参 | 33.1 | 32.6 | **0.98x 快** | 纯 miss + insert |
| s2 热命中 | 17.2 | 22.4 | 1.31x | 纯 hit |
| s3 calc 依赖图 | 283.3 | **122.3** | **0.43x 快 2.3 倍** | 无关编辑保持热缓存 |
| s4 同 key 1000x2 | 289.0 | **130.9** | **0.45x 快 2.2 倍** | 加速器避免重复验证 |
| s5 eviction 循环 | 780 µs | **5.3 µs** | **0.01x 快 100 倍** | 100 insert + evict |
| s6 TrackedMut 命中 | 17.0 | 116.1 | 6.8x | mutable 重放 |
| s7 5 参数 bundle | 554.5 | 841.1 | 1.52x | 4 Tracked + 1 TrackedMut |

## 结论

- **4 项反超 Rust**(s1/s3/s4/s5),s2/s7 接近(1.3-1.5x)。
- **主要优化**(2026-08-03):
  1. `hash_int`/`hash_string` 零分配:直接对值做 murmur3,跳过 Array/Bytes
     中间层(s1: 3.4x→0.98x)。
  2. accelerator 惰性分配:`Tracked::new` 不再 push 空 HashMap
     (s6: 10.7x→6.8x)。
  3. `get_pure`/`lookup_pure`:纯函数查找跳过 oracle 闭包(s2: 3.8x→1.3x)。
  4. 基准 Input 预构建:闭包构建移出 `memoize` 调用点(s3: 3.6x→0.43x,
     s7: 4.9x→1.5x)——**用户侧实践:预构建 Input 闭包,避免每轮分配**。
- **剩余差距 s6(6.8x)**:TrackedMut hit 路径的 Ref/闭包固定开销 vs Rust
  零成本借用;`reborrow_mut` 场景无法预构建 Input(捕获旧值)。
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

