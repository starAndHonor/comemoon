///| MurmurHash64A — 64-bit MurmurHash for short keys (cache keys, call

///| hashes). Single UInt64 state, ~2x faster than MurmurHash3-128 (which

///| we previously used, before this benchmark-driven switch to 64-bit).

///|

///| 64-bit output is sufficient for memoization keys: collision probability

///| for n entries is ~n²/2⁶⁵ (birthday bound). At 1M entries ≈ 2.7×10⁻⁸ —

///| negligible for per-process caches. Rust comemo uses 128-bit SipHash13;

///| we deliberately trade a 128-bit space for a 2x faster hash because

///| MoonBit's HashMap truncates to a 32-bit `Int` hash anyway, so the extra

///| 64 bits offered no collision protection.

///|

///| Based on Austin Appleby's MurmurHash64A (public domain).

///|
/// The MurmurHash64A multiplicative constant.
let m64 : UInt64 = 0xC6A4A7935BD1E995UL

///|
/// The MurmurHash64A rotation amount.
let r64 : Int = 47

///|
/// 64-bit finalizer (murmur's fmix64 tail, adapted to the 64A structure).
fn fmix64a(h : UInt64) -> UInt64 {
  let mut h = h
  h = h ^ (h >> 33)
  h = h * 0xff51afd7ed558ccdUL
  h = h ^ (h >> 33)
  h = h * 0xc4ceb9fe1a85ec53UL
  h = h ^ (h >> 33)
  h
}

///|
/// Hash a single UInt64 (the hot path for Int keys).
pub fn hash_u64(seed : UInt64, v : UInt64) -> UInt64 {
  let mut h = seed ^ (8UL * m64)
  let mut k = v
  k = k * m64
  k = k ^ (k >> r64)
  k = k * m64
  h = h ^ k
  h = h * m64
  h = h ^ (h >> r64)
  h
}

///|
/// Hash a byte string (arbitrary length, little-endian blocks).
pub fn hash_bytes64(seed : UInt64, data : Bytes) -> UInt64 {
  let len = data.length()
  let mut h = seed ^ (len.to_uint64() * m64)
  let mut i = 0
  while i + 8 <= len {
    let mut k = data[i].to_uint64()
    k = k | (data[i + 1].to_uint64() << 8)
    k = k | (data[i + 2].to_uint64() << 16)
    k = k | (data[i + 3].to_uint64() << 24)
    k = k | (data[i + 4].to_uint64() << 32)
    k = k | (data[i + 5].to_uint64() << 40)
    k = k | (data[i + 6].to_uint64() << 48)
    k = k | (data[i + 7].to_uint64() << 56)
    k = k * m64
    k = k ^ (k >> r64)
    k = k * m64
    h = h ^ k
    h = h * m64
    i = i + 8
  }
  //| Remaining bytes (1-7).
  let mut k = 0UL
  let rem = len - i
  if rem >= 7 {
    k = k ^ (data[i + 6].to_uint64() << 48)
  }
  if rem >= 6 {
    k = k ^ (data[i + 5].to_uint64() << 40)
  }
  if rem >= 5 {
    k = k ^ (data[i + 4].to_uint64() << 32)
  }
  if rem >= 4 {
    k = k ^ (data[i + 3].to_uint64() << 24)
  }
  if rem >= 3 {
    k = k ^ (data[i + 2].to_uint64() << 16)
  }
  if rem >= 2 {
    k = k ^ (data[i + 1].to_uint64() << 8)
  }
  if rem >= 1 {
    k = k ^ data[i].to_uint64()
    k = k * m64
    k = k ^ (k >> r64)
    k = k * m64
    h = h ^ k
  }
  h = h ^ (h >> r64)
  h = h * m64
  h = h ^ (h >> r64)
  h
}

///|
/// Hash an Int (the most common memoized argument type).
pub fn hash_int64(v : Int) -> UInt64 {
  hash_u64(0UL, v.to_uint64())
}

///|
/// Hash a String (UTF-16 LE bytes, matching hash_string's encoding).
pub fn hash_string64(s : String) -> UInt64 {
  hash_bytes64(0UL, s.to_bytes())
}

///|
/// Hash zero (for oracles that never hash).
pub fn hash_zero64() -> UInt64 {
  0UL
}

///|
/// Combine two 64-bit hashes (for multi-key scenarios).
pub fn hash_combine64(a : UInt64, b : UInt64) -> UInt64 {
  hash_u64(hash_u64(0UL, a), b)
}

///|
/// Hash a Unit value (for mutable-call placeholders).
pub fn hash_unit64() -> UInt64 {
  hash_u64(0UL, 1UL)
}

//| Correctness tests: determinism + distinctness.

///|
test "hash64_deterministic" {
  let a = hash_int64(42)
  let b = hash_int64(42)
  if a != b {
    panic()
  }
  let s = "eval a.calc"
  if hash_string64(s) != hash_string64(s) {
    panic()
  }
}

///|
test "hash64_distinct" {
  if hash_int64(1) == hash_int64(2) {
    panic()
  }
  if hash_string64("a") == hash_string64("b") {
    panic()
  }
}

///|
test "hash64_collision_free" {
  //| 10000 distinct integers, no 64-bit collision.
  let seen : @hashmap.HashMap[UInt64, Unit] = @hashmap.HashMap([])
  let mut i = 0
  while i < 10000 {
    let h = hash_int64(i)
    if seen.contains(h) {
      panic()
    }
    seen[h] = ()
    i = i + 1
  }
}
