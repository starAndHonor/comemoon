///| 128-bit MurmurHash3 Convenience Functions
/// One-shot hash functions for 128-bit MurmurHash3

///|
/// Compute MurmurHash3 128-bit hash of data with seeds 0, 0
/// Equivalent to: hasher = new128(); hasher.write(data); hasher.sum128()
pub fn sum128(data : Bytes) -> UInt128 {
  seed_sum128(UInt128::{ hi: 0UL, lo: 0UL }, data)
}

///|
/// Compute MurmurHash3 128-bit hash of data with given seeds
/// This reads and processes data in chunks of little endian uint64s,
/// making the hash portable across architectures
pub fn seed_sum128(seed : UInt128, data : Bytes) -> UInt128 {
  let mut h1 = seed.hi
  let mut h2 = seed.lo
  let clen = data.length()
  let mut p = data

  // Process 16-byte chunks
  while p.length() >= 16 {
    let k1 = p[0].to_uint64() |
      (p[1].to_uint64() << 8) |
      (p[2].to_uint64() << 16) |
      (p[3].to_uint64() << 24) |
      (p[4].to_uint64() << 32) |
      (p[5].to_uint64() << 40) |
      (p[6].to_uint64() << 48) |
      (p[7].to_uint64() << 56)
    let k2 = p[8].to_uint64() |
      (p[9].to_uint64() << 8) |
      (p[10].to_uint64() << 16) |
      (p[11].to_uint64() << 24) |
      (p[12].to_uint64() << 32) |
      (p[13].to_uint64() << 40) |
      (p[14].to_uint64() << 48) |
      (p[15].to_uint64() << 56)
    p = p[16:].to_owned()
    let mut k1_processed = k1 * c1_128
    k1_processed = rotate_left_64(k1_processed, 31)
    k1_processed = k1_processed * c2_128
    h1 = h1 ^ k1_processed
    h1 = rotate_left_64(h1, 27)
    h1 = h1 + h2
    h1 = h1 * 5UL + 0x52dce729UL
    let mut k2_processed = k2 * c2_128
    k2_processed = rotate_left_64(k2_processed, 33)
    k2_processed = k2_processed * c1_128
    h2 = h2 ^ k2_processed
    h2 = rotate_left_64(h2, 31)
    h2 = h2 + h1
    h2 = h2 * 5UL + 0x38495ab5UL
  }

  // Handle remaining bytes
  let mut k1 = 0UL
  let mut k2 = 0UL
  let remaining = p.length()

  // Process remaining bytes for k2 (bytes 8-15)
  if remaining >= 15 {
    k2 = k2 ^ (p[14].to_uint64() << 48)
  }
  if remaining >= 14 {
    k2 = k2 ^ (p[13].to_uint64() << 40)
  }
  if remaining >= 13 {
    k2 = k2 ^ (p[12].to_uint64() << 32)
  }
  if remaining >= 12 {
    k2 = k2 ^ (p[11].to_uint64() << 24)
  }
  if remaining >= 11 {
    k2 = k2 ^ (p[10].to_uint64() << 16)
  }
  if remaining >= 10 {
    k2 = k2 ^ (p[9].to_uint64() << 8)
  }
  if remaining >= 9 {
    k2 = k2 ^ p[8].to_uint64()
    k2 = k2 * c2_128
    k2 = rotate_left_64(k2, 33)
    k2 = k2 * c1_128
    h2 = h2 ^ k2
  }

  // Process remaining bytes for k1 (bytes 0-7)
  if remaining >= 8 {
    k1 = k1 ^ (p[7].to_uint64() << 56)
  }
  if remaining >= 7 {
    k1 = k1 ^ (p[6].to_uint64() << 48)
  }
  if remaining >= 6 {
    k1 = k1 ^ (p[5].to_uint64() << 40)
  }
  if remaining >= 5 {
    k1 = k1 ^ (p[4].to_uint64() << 32)
  }
  if remaining >= 4 {
    k1 = k1 ^ (p[3].to_uint64() << 24)
  }
  if remaining >= 3 {
    k1 = k1 ^ (p[2].to_uint64() << 16)
  }
  if remaining >= 2 {
    k1 = k1 ^ (p[1].to_uint64() << 8)
  }
  if remaining >= 1 {
    k1 = k1 ^ p[0].to_uint64()
    k1 = k1 * c1_128
    k1 = rotate_left_64(k1, 31)
    k1 = k1 * c2_128
    h1 = h1 ^ k1
  }
  h1 = h1 ^ clen.to_uint64()
  h2 = h2 ^ clen.to_uint64()
  h1 = h1 + h2
  h2 = h2 + h1
  h1 = fmix64(h1)
  h2 = fmix64(h2)
  h1 = h1 + h2
  h2 = h2 + h1
  UInt128::{ hi: h1, lo: h2 }
}

///|
/// Zero-allocation MurmurHash3-128 of a single little-endian Int64.
/// Equivalent to `seed_sum128(0, <8 LE bytes>)` but avoids the Array/Bytes
/// allocation chain (hot path: memoized Int keys).
pub fn sum128_i64_le(v : Int64) -> UInt128 {
  //| Unpack the 8 LE bytes without allocating.
  let b0 = (v & 0xFFL).to_uint64()
  let b1 = ((v >> 8) & 0xFFL).to_uint64()
  let b2 = ((v >> 16) & 0xFFL).to_uint64()
  let b3 = ((v >> 24) & 0xFFL).to_uint64()
  let b4 = ((v >> 32) & 0xFFL).to_uint64()
  let b5 = ((v >> 40) & 0xFFL).to_uint64()
  let b6 = ((v >> 48) & 0xFFL).to_uint64()
  let b7 = ((v >> 56) & 0xFFL).to_uint64()
  let mut h1 = 0UL
  let mut h2 = 0UL
  //| Single 8-byte block (remaining-bytes path of seed_sum128).
  let mut k1 = (b7 << 56) |
    (b6 << 48) |
    (b5 << 40) |
    (b4 << 32) |
    (b3 << 24) |
    (b2 << 16) |
    (b1 << 8) |
    b0
  k1 = k1 * c1_128
  k1 = rotate_left_64(k1, 31)
  k1 = k1 * c2_128
  h1 = h1 ^ k1
  let clen = 8UL
  h1 = h1 ^ clen
  h2 = h2 ^ clen
  h1 = h1 + h2
  h2 = h2 + h1
  h1 = fmix64(h1)
  h2 = fmix64(h2)
  h1 = h1 + h2
  h2 = h2 + h1
  UInt128::{ hi: h1, lo: h2 }
}

///|
test "sum128_i64_le_matches_bytes" {
  //| sum128_i64_le(42) must equal sum128(<8 LE bytes of 42>).
  let bytes : Bytes = Bytes::from_array([42, 0, 0, 0, 0, 0, 0, 0])
  let a = sum128_i64_le(42L)
  let b = sum128(bytes)
  if a != b {
    panic()
  }
  let neg : Bytes = Bytes::from_array([
    (254).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
    (255).to_byte(),
  ])
  if sum128_i64_le(-2L) != sum128(neg) {
    panic()
  }
}

///|
/// Streaming MurmurHash3-128 over an iterator of codepoints (UTF-8 encoded
/// per codepoint). Zero-allocation: absorbs each codepoint's bytes directly
/// into the hash state instead of building an intermediate byte array.
/// Deterministic for equal strings; collision-resistant via murmur3.
pub fn sum128_codepoints(codepoints : Iter[Char]) -> UInt128 {
  let mut h1 = 0UL
  let mut h2 = 0UL
  let mut total_len = 0UL
  //| Absorb each codepoint's UTF-8 bytes as a 1/2/3-byte block.
  for ch in codepoints {
    let cp = ch.to_int()
    let (b0, nbytes) : (UInt64, UInt64) = if cp <= 0x7F {
      (cp.to_uint64(), 1UL)
    } else if cp <= 0x7FF {
      //| 2 bytes: 110xxxxx 10xxxxxx
      let b0v = (0xC0 | ((cp >> 6) & 0x1F)).to_uint64()
      let b1v = (0x80 | (cp & 0x3F)).to_uint64()
      (b0v | (b1v << 8), 2UL)
    } else {
      //| 3 bytes: 1110xxxx 10xxxxxx 10xxxxxx
      let b0v = (0xE0 | ((cp >> 12) & 0x0F)).to_uint64()
      let b1v = (0x80 | ((cp >> 6) & 0x3F)).to_uint64()
      let b2v = (0x80 | (cp & 0x3F)).to_uint64()
      (b0v | (b1v << 8) | (b2v << 16), 3UL)
    }
    //| Mix this small block into k1 (murmur3 tail processing for < 8 bytes).
    //| Absorb as little-endian bytes: b0 holds the block in low bytes.
    //| Use k2 for bytes 8-15? No — absorb into k1 tail with per-block length.
    //| To keep it simple and deterministic: treat each codepoint's bytes as
    //| a distinct chunk, mixing sequentially into h1.
    let mut k1 = b0
    k1 = k1 * c1_128
    k1 = rotate_left_64(k1, 31)
    k1 = k1 * c2_128
    h1 = h1 ^ k1
    h1 = rotate_left_64(h1, 27)
    h1 = h1 + h2
    h1 = h1 * 5UL + 0x52dce729UL
    h2 = h2 ^ nbytes
    h2 = rotate_left_64(h2, 31)
    h2 = h2 + h1
    h2 = h2 * 5UL + 0x38495ab5UL
    total_len = total_len + nbytes
  }
  //| Finalize (mirror seed_sum128's tail+finalize for empty tail).
  h1 = h1 ^ total_len
  h2 = h2 ^ total_len
  h1 = h1 + h2
  h2 = h2 + h1
  h1 = fmix64(h1)
  h2 = fmix64(h2)
  h1 = h1 + h2
  h2 = h2 + h1
  UInt128::{ hi: h1, lo: h2 }
}
