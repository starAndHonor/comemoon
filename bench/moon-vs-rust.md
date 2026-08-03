# 性能基准对比(Phase 6)

> 2026-08-02。场景:calc 依赖图(改无关文件仍命中),10 万次迭代。
> Rust 基线:`refs/comemo/examples/bench.rs`(release 模式)。

## 结果

### 场景 A:calc 依赖图(10 万次迭代)

| 实现 | 每次迭代 | 相对 Rust |
|---|---|---|
| Rust comemo (release) | 425.6 ns | 1.00x |
| MoonBit comemoon (native, 内置 Hasher) | 333 ns | 0.78x(快 22%) |
| MoonBit comemoon (native, SipHash13 复刻) | 1.09 µs | 2.6x(慢) |
| MoonBit comemoon (wasm, SipHash13) | 3.87 µs | 9.1x(慢) |

### 场景 B:1000 个同 key 上下文 × 2 遍(加速器验证)

| 实现 | 总耗时 | 相对 Rust |
|---|---|---|
| Rust comemo (release) | 609 µs | 1.00x |
| MoonBit comemoon (native, SipHash13) | **337 µs** | **0.55x(快 1.8 倍)** |

## 结论

- **hash 与 Rust 完全一致**(SipHash13 128-bit 复刻,黄金值对照)——这是
  2026-08-02 的硬性要求,已满足。
- **同 key 场景仍快于 Rust 1.8 倍**:加速器避免重复验证,抵消 SipHash 开销。
- **calc 场景慢 2.6x(native)/9.1x(wasm)**:纯 MoonBit SipHash13 的逐字节
  字符串哈希是瓶颈。若需恢复性能:内置 Hasher 快但 hash 值不一致;或用
  FFI/优化字节处理。这是"一致性 vs 性能"的明确权衡。

## 复现

```bash
# Rust
cd refs/comemo && cargo run --release --example bench
# MoonBit
moon bench            # wasm
moon bench --target native
```
