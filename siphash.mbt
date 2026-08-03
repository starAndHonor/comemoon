///| SipHash-1-3 with 128-bit output — a faithful port of the `siphasher`

///| crate's `SipHasher13` (Rust), which comemo uses for all its hashing.
///

///| Output is two `UInt64`s (`h1`, `h2`) matching Rust's `Hash128`; combine

///| as `h1 | (h2 << 64)` for the `u128` view. Keys are `(0, 0)` like

///| `SipHasher13::new()`.
///

///| This replaces the builtin `Hasher` so hash values are byte-identical to

///| Rust comemo — enabling golden-value cross-checks against the reference.

///|
/// Rotate-left for UInt64 (MoonBit has no builtin).
fn rotl(x : UInt64, n : Int) -> UInt64 {
  (x << n) | (x >> (64 - n))
}

///|
/// Compression round (mirrors `compress!` in siphasher/src/common.rs).
fn compress(
  v0 : UInt64,
  v1 : UInt64,
  v2 : UInt64,
  v3 : UInt64,
) -> (UInt64, UInt64, UInt64, UInt64) {
  let mut v0 = v0
  let mut v1 = v1
  let mut v2 = v2
  let mut v3 = v3
  v0 = v0 + v1
  v1 = rotl(v1, 13)
  v1 = v1 ^ v0
  v0 = rotl(v0, 32)
  v2 = v2 + v3
  v3 = rotl(v3, 16)
  v3 = v3 ^ v2
  v0 = v0 + v3
  v3 = rotl(v3, 21)
  v3 = v3 ^ v0
  v2 = v2 + v1
  v1 = rotl(v1, 17)
  v1 = v1 ^ v2
  v2 = rotl(v2, 32)
  (v0, v1, v2, v3)
}

///| SipHash-1-3 over a byte stream, 128-bit output.

///|
/// `keys` are (k0, k1); comemo uses (0, 0).
fn sip13_128(bytes : Array[Byte], keys : (UInt64, UInt64)) -> (UInt64, UInt64) {
  let (k0, k1) = keys
  let mut v0 = k0 ^ 0x736F6D6570736575
  let mut v1 = k1 ^ 0x646F72616E646F83
  let mut v2 = k0 ^ 0x6C7967656E657261
  let mut v3 = k1 ^ 0x7465646279746573

  let length = bytes.length()
  let mut i = 0
  //| Process full 8-byte blocks.
  while i + 8 <= length {
    let mut mi : UInt64 = 0
    let mut j = 0
    while j < 8 {
      mi = mi | (bytes[i + j].to_uint64() << (j * 8))
      j = j + 1
    }
    v3 = v3 ^ mi
    let (nv0, nv1, nv2, nv3) = compress(v0, v1, v2, v3)
    v0 = nv0
    v1 = nv1
    v2 = nv2
    v3 = nv3
    v0 = v0 ^ mi
    i = i + 8
  }

  //| Remaining tail bytes (0-7), little-endian.
  let mut tail : UInt64 = 0
  let mut t = 0
  while i + t < length {
    tail = tail | (bytes[i + t].to_uint64() << (t * 8))
    t = t + 1
  }

  //| Finalize (mirrors finish128_with_state).
  let b : UInt64 = ((length.to_uint64() & 0xFF) << 56) | tail
  v3 = v3 ^ b
  let (r0, r1, r2, r3) = compress(v0, v1, v2, v3)
  v0 = r0
  v1 = r1
  v2 = r2
  v3 = r3
  v0 = v0 ^ b

  v2 = v2 ^ 0xEE
  //| d_rounds: 3 rounds (SipHash13)
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
    let (d0, d1, d2, d3) = compress(v0, v1, v2, v3)

    v0 = d0

    v1 = d1

    v2 = d2

    v3 = d3
    d = d + 1
  }
  let h2 = v0 ^ v1 ^ v2 ^ v3

  (h1, h2)
}

///| Golden-value tests: byte-identical to Rust's SipHasher13 output.

///| Reference values generated from refs/comemo + siphasher 1.0.3 (keys 0,0).

///| Rust `Hash for str` = write(utf8_bytes) + write_u8(0xff).

///| MoonBit's `to_bytes()` is UTF-16, so encode UTF-8 manually from the

///|
/// Unicode code points.
fn bytes_of_string(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let cp = chars[i].to_int()
    if cp <= 0x7F {
      out.push(cp.to_byte())
    } else if cp <= 0x7FF {
      out.push(0xC0 | ((cp >> 6).to_byte() & 0x1F))
      out.push(0x80 | (cp & 0x3F).to_byte())
    } else {
      out.push(0xE0 | ((cp >> 12).to_byte() & 0x0F))
      out.push(0x80 | ((cp >> 6).to_byte() & 0x3F))
      out.push(0x80 | (cp & 0x3F).to_byte())
    }
    i = i + 1
  }
  out.push((0xFF).to_byte())
  out
}

///|
fn u64_bytes(v : UInt64) -> Array[Byte] {
  //| Little-endian 8 bytes.
  let out : Array[Byte] = []
  let mut i = 0
  while i < 8 {
    out.push(((v >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
  out
}

///|
fn u32_bytes(v : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  while i < 4 {
    out.push(((v >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
  out
}

///|
test "siphash13_string_hello" {
  let (h1, h2) = sip13_128(bytes_of_string("hello"), (0, 0))
  if h1 != 0x63E88709613557CD || h2 != 0x6A4E45BF82C2C7D6 {
    panic()
  }
}

///|
test "siphash13_u64_42" {
  //| Rust: h(&42u64) = d3e300802a0c3baf38a9b9d2840b2cbd
  let (h1, h2) = sip13_128(u64_bytes(42), (0, 0))
  if h1 != 0x38A9B9D2840B2CBD || h2 != 0xD3E300802A0C3BAF {
    panic()
  }
}

///|
test "siphash13_u32_42" {
  //| Rust: h(&42u32) = 6b21e8998b704f39d887ef37178c26c8
  let (h1, h2) = sip13_128(u32_bytes(42), (0, 0))
  if h1 != 0xD887EF37178C26C8 || h2 != 0x6B21E8998B704F39 {
    panic()
  }
}

///|
test "siphash13_empty_string" {
  //| Rust: h(&"") = e63a4553e58c6a667aecca6462f4d8ed
  let (h1, h2) = sip13_128(bytes_of_string(""), (0, 0))
  if h1 != 0x7AECCA6462F4D8ED || h2 != 0xE63A4553E58C6A66 {
    panic()
  }
}

///| Fast path: SipHash13 of a single u64 (8 bytes LE, no array allocation).

///|
/// Equivalent to sip13_128 over the 8 LE bytes of `v`.
pub fn sip13_128_u64(v : UInt64, keys : (UInt64, UInt64)) -> (UInt64, UInt64) {
  let (k0, k1) = keys
  let mut v0 = k0 ^ 0x736F6D6570736575
  let mut v1 = k1 ^ 0x646F72616E646F83
  let mut v2 = k0 ^ 0x6C7967656E657261
  let mut v3 = k1 ^ 0x7465646279746573

  //| One full 8-byte block.
  v3 = v3 ^ v
  let (a0, a1, a2, a3) = compress(v0, v1, v2, v3)
  v0 = a0
  v1 = a1
  v2 = a2
  v3 = a3
  v0 = v0 ^ v

  //| tail = 0 (8 bytes processed, no remainder), length = 8.
  let b : UInt64 = (UInt64(8) & 0xFF) << 56
  v3 = v3 ^ b
  let (b0, b1, b2, b3) = compress(v0, v1, v2, v3)
  v0 = b0
  v1 = b1
  v2 = b2
  v3 = b3
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
