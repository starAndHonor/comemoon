///| Incremental SipHash-1-3 128-bit (mirrors Rust's `SipHasher13` Hasher):

///| write bytes in chunks, finalize once. Avoids the Array[Byte] allocation

///|
/// of the one-shot `sip13_128`.
pub struct SipState {
  mut v0 : UInt64
  mut v1 : UInt64
  mut v2 : UInt64
  mut v3 : UInt64
  mut tail : UInt64
  mut ntail : Int
  mut length : Int
}

///|
/// Creates a new hasher with keys (0, 0) — same as SipHasher13::new().
pub fn SipState::new() -> SipState {
  let k0 : UInt64 = 0
  let k1 : UInt64 = 0
  {
    v0: k0 ^ 0x736F6D6570736575,
    v1: k1 ^ 0x646F72616E646F83,
    v2: k0 ^ 0x6C7967656E657261,
    v3: k1 ^ 0x7465646279746573,
    tail: 0,
    ntail: 0,
    length: 0,
  }
}

///|
/// Writes a single byte.
pub fn SipState::write_byte(self : SipState, b : Byte) -> Unit {
  self.length = self.length + 1
  self.tail = self.tail | (b.to_uint64() << (self.ntail * 8))
  self.ntail = self.ntail + 1
  if self.ntail == 8 {
    //| Process the full block.
    let mi = self.tail
    self.v3 = self.v3 ^ mi
    let (a0, a1, a2, a3) = compress(self.v0, self.v1, self.v2, self.v3)
    self.v0 = a0
    self.v1 = a1
    self.v2 = a2
    self.v3 = a3
    self.v0 = self.v0 ^ mi
    self.tail = 0
    self.ntail = 0
  }
}

///|
/// Writes a u64 as 8 little-endian bytes.
pub fn SipState::write_u64_le(self : SipState, v : UInt64) -> Unit {
  let mut i = 0
  while i < 8 {
    self.write_byte(((v >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
}

///| Writes a chunk of bytes directly (buffers into the tail, processing

///|
/// full 8-byte blocks).
pub fn SipState::write_bytes(self : SipState, bytes : Array[Byte]) -> Unit {
  let mut i = 0
  while i < bytes.length() {
    self.write_byte(bytes[i])
    i = i + 1
  }
}

///|
/// Finalizes, returning the 128-bit hash as (low, high).
pub fn SipState::finish(self : SipState) -> (UInt64, UInt64) {
  let mut v0 = self.v0
  let mut v1 = self.v1
  let mut v2 = self.v2
  let mut v3 = self.v3
  let tail = self.tail
  let length = self.length

  let b : UInt64 = ((length.to_uint64() & 0xFF) << 56) | tail
  v3 = v3 ^ b
  let (a0, a1, a2, a3) = compress(v0, v1, v2, v3)
  v0 = a0
  v1 = a1
  v2 = a2
  v3 = a3
  v0 = v0 ^ b

  v2 = v2 ^ 0xEE
  let mut d = 0
  while d < 3 {
    let (c0, c1, c2, c3) = compress(v0, v1, v2, v3)
    v0 = c0
    v1 = c1
    v2 = c2
    v3 = c3
    d = d + 1
  }
  let h1 = v0 ^ v1 ^ v2 ^ v3

  v1 = v1 ^ 0xDD
  d = 0
  while d < 3 {
    let (e0, e1, e2, e3) = compress(v0, v1, v2, v3)
    v0 = e0
    v1 = e1
    v2 = e2
    v3 = e3
    d = d + 1
  }
  let h2 = v0 ^ v1 ^ v2 ^ v3

  (h1, h2)
}
