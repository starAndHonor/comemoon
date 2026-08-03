///| 128-bit MurmurHash3 Implementation
/// Constants and core algorithm for 128-bit MurmurHash3

///|
/// Constants for 128-bit MurmurHash3
let c1_128 : UInt64 = 0x87c37b91114253d5UL

///|
let c2_128 : UInt64 = 0x4cf5ad432745937fUL

///|
/// Left rotate a 64-bit unsigned integer
fn rotate_left_64(x : UInt64, k : Int) -> UInt64 {
  (x << k) | (x >> (64 - k))
}

///|
/// Final mix function for 128-bit hash
fn fmix64(k : UInt64) -> UInt64 {
  let mut result = k
  result = result ^ (result >> 33)
  result = result * 0xff51afd7ed558ccdUL
  result = result ^ (result >> 33)
  result = result * 0xc4ceb9fe1a85ec53UL
  result = result ^ (result >> 33)
  result
}

///|
/// 128-bit digest structure for MurmurHash3
/// Implements the BMixer trait for 128-bit hash computation
struct Digest128 {
  /// Base digest for common streaming functionality
  digest : Digest
  /// Seed values for hash initialization
  seed : UInt128
  /// Unfinalized running hash state
  mut hash : UInt128
}

///|
/// Create a new 128-bit hasher with the given seeds
pub fn Digest128::new_with_seed(seed1 : UInt64, seed2 : UInt64) -> Digest128 {
  let seed = UInt128::{ hi: seed1, lo: seed2 }
  { digest: Digest::new(16), seed, hash: seed }
}

///|
/// Create a new 128-bit hasher with seeds 0
pub fn Digest128::new() -> Digest128 {
  Digest128::new_with_seed(0UL, 0UL)
}

///|
/// Implement BMixer trait for Digest128
impl BMixer for Digest128 with fn bmix(self, p) {
  let mut data = p
  let mut h1 = self.hash.hi
  let mut h2 = self.hash.lo

  // Process 16-byte chunks
  while data.length() >= 16 {
    let k1 = data[0].to_uint64() |
      (data[1].to_uint64() << 8) |
      (data[2].to_uint64() << 16) |
      (data[3].to_uint64() << 24) |
      (data[4].to_uint64() << 32) |
      (data[5].to_uint64() << 40) |
      (data[6].to_uint64() << 48) |
      (data[7].to_uint64() << 56)
    let k2 = data[8].to_uint64() |
      (data[9].to_uint64() << 8) |
      (data[10].to_uint64() << 16) |
      (data[11].to_uint64() << 24) |
      (data[12].to_uint64() << 32) |
      (data[13].to_uint64() << 40) |
      (data[14].to_uint64() << 48) |
      (data[15].to_uint64() << 56)
    data = data[16:].to_owned()
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
  self.hash = UInt128::{ hi: h1, lo: h2 }
  data
}

///|
impl BMixer for Digest128 with fn size(_self) {
  16
}

///|
impl BMixer for Digest128 with fn reset(self) {
  self.hash = self.seed
}

///|
/// Get the size in bytes (16 for 128-bit hash)
pub fn Digest128::size(_self : Digest128) -> Int {
  16
}

///|
/// Write data to the 128-bit hasher
pub fn Digest128::write(self : Digest128, data : Bytes) -> Unit {
  self.digest.write(self, data)
}

///|
/// Finalize and return the 128-bit hash as UInt128
pub fn Digest128::sum128(self : Digest128) -> UInt128 {
  let mut h1 = self.hash.hi
  let mut h2 = self.hash.lo
  let mut k1 = 0UL
  let mut k2 = 0UL

  // Handle remaining bytes
  let tail = self.digest.tail
  let tail_len = tail.length()

  // Process remaining bytes for k2 (bytes 8-15)
  if tail_len >= 15 {
    k2 = k2 ^ (tail[14].to_uint64() << 48)
  }
  if tail_len >= 14 {
    k2 = k2 ^ (tail[13].to_uint64() << 40)
  }
  if tail_len >= 13 {
    k2 = k2 ^ (tail[12].to_uint64() << 32)
  }
  if tail_len >= 12 {
    k2 = k2 ^ (tail[11].to_uint64() << 24)
  }
  if tail_len >= 11 {
    k2 = k2 ^ (tail[10].to_uint64() << 16)
  }
  if tail_len >= 10 {
    k2 = k2 ^ (tail[9].to_uint64() << 8)
  }
  if tail_len >= 9 {
    k2 = k2 ^ tail[8].to_uint64()
    k2 = k2 * c2_128
    k2 = rotate_left_64(k2, 33)
    k2 = k2 * c1_128
    h2 = h2 ^ k2
  }

  // Process remaining bytes for k1 (bytes 0-7)
  if tail_len >= 8 {
    k1 = k1 ^ (tail[7].to_uint64() << 56)
  }
  if tail_len >= 7 {
    k1 = k1 ^ (tail[6].to_uint64() << 48)
  }
  if tail_len >= 6 {
    k1 = k1 ^ (tail[5].to_uint64() << 40)
  }
  if tail_len >= 5 {
    k1 = k1 ^ (tail[4].to_uint64() << 32)
  }
  if tail_len >= 4 {
    k1 = k1 ^ (tail[3].to_uint64() << 24)
  }
  if tail_len >= 3 {
    k1 = k1 ^ (tail[2].to_uint64() << 16)
  }
  if tail_len >= 2 {
    k1 = k1 ^ (tail[1].to_uint64() << 8)
  }
  if tail_len >= 1 {
    k1 = k1 ^ tail[0].to_uint64()
    k1 = k1 * c1_128
    k1 = rotate_left_64(k1, 31)
    k1 = k1 * c2_128
    h1 = h1 ^ k1
  }
  h1 = h1 ^ self.digest.clen.to_uint64()
  h2 = h2 ^ self.digest.clen.to_uint64()
  h1 = h1 + h2
  h2 = h2 + h1
  h1 = fmix64(h1)
  h2 = fmix64(h2)
  h1 = h1 + h2
  h2 = h2 + h1
  UInt128::{ hi: h1, lo: h2 }
}

///|
/// Get the hash as a byte array (big-endian)
pub fn Digest128::sum(self : Digest128) -> Bytes {
  let hash128 = self.sum128()
  let h1 = hash128.hi
  let h2 = hash128.lo
  let array = [
    ((h1 >> 56) & 0xFFUL).to_byte(),
    ((h1 >> 48) & 0xFFUL).to_byte(),
    ((h1 >> 40) & 0xFFUL).to_byte(),
    ((h1 >> 32) & 0xFFUL).to_byte(),
    ((h1 >> 24) & 0xFFUL).to_byte(),
    ((h1 >> 16) & 0xFFUL).to_byte(),
    ((h1 >> 8) & 0xFFUL).to_byte(),
    (h1 & 0xFFUL).to_byte(),
    ((h2 >> 56) & 0xFFUL).to_byte(),
    ((h2 >> 48) & 0xFFUL).to_byte(),
    ((h2 >> 40) & 0xFFUL).to_byte(),
    ((h2 >> 32) & 0xFFUL).to_byte(),
    ((h2 >> 24) & 0xFFUL).to_byte(),
    ((h2 >> 16) & 0xFFUL).to_byte(),
    ((h2 >> 8) & 0xFFUL).to_byte(),
    (h2 & 0xFFUL).to_byte(),
  ]
  Bytes::from_array(array)
}

///|
/// Reset the 128-bit hasher to initial state
pub fn Digest128::reset(self : Digest128) -> Unit {
  self.digest.reset(self)
}
