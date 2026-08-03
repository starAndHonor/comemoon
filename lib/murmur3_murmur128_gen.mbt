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
