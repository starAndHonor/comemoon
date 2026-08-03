///| Hashing for comemo: SipHash-1-3 128-bit, byte-identical to Rust comemo.
///

///| Rust hashes via `siphasher::sip128::SipHasher13` (keys 0,0) fed through

///| the std `Hash` trait. MoonBit's builtin `Hasher` differs in both

///| algorithm and encoding, so we reimplement SipHash13 (siphash.mbt) and

///| the std `Hash` encodings for the types comemo uses (below).
///

///| MoonBit forbids implementing user traits for core types (String, Int...),

///| so core types are hashed via concrete functions (`hash_int`,

///| `hash_string`, ...) and user types (Call enums) via the `RustHashable`

///| trait. Generated code calls the right one.

///|
/// 64-bit hash (low half of the 128-bit SipHash13).
pub fn[T : RustHashable] hash(value : T) -> UInt64 {
  let (h1, _h2) = value.rust_hash()
  h1
}

///|
/// Full 128-bit SipHash13 as (low, high) u64s.
pub fn[T : RustHashable] hash128(value : T) -> (UInt64, UInt64) {
  value.rust_hash()
}

///| User types (Call enums) implement this: stream their Rust std `Hash`

///|
/// encoding into `bytes`.
pub trait RustHashable {
  fn write_rust(Self, Array[Byte]) -> Unit
  fn rust_hash(Self) -> (UInt64, UInt64) = _
}

///|
/// Default: hash = SipHash13 over the streamed Rust encoding.
impl RustHashable with fn rust_hash(self) -> (UInt64, UInt64) {
  let bytes : Array[Byte] = []
  self.write_rust(bytes)
  sip13_128(bytes, (0, 0))
}

///|
/// Concrete hashes for core types (cannot impl RustHashable).
pub fn hash_int(v : Int) -> UInt64 {
  let (h1, _) = sip13_128_u64(v.to_int64().reinterpret_as_uint64(), (0, 0))
  h1
}

///|
pub fn hash_string(s : String) -> UInt64 {
  let st = SipState::new()
  //| Rust str: write(utf8 bytes) + write_u8(0xff)
  let mut i = 0
  for ch in s.iter() {
    let cp = ch.to_int()
    if cp <= 0x7F {
      st.write_byte(cp.to_byte())
    } else if cp <= 0x7FF {
      st.write_byte((0xC0 | ((cp >> 6) & 0x1F)).to_byte())
      st.write_byte((0x80 | (cp & 0x3F)).to_byte())
    } else {
      st.write_byte((0xE0 | ((cp >> 12) & 0x0F)).to_byte())
      st.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      st.write_byte((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  st.write_byte((255).to_byte())
  let (h1, _) = st.finish()
  h1
}

///|
pub fn hash_unit() -> UInt64 {
  let bytes : Array[Byte] = [(255).to_byte()]
  let (h1, _) = sip13_128(bytes, (0, 0))
  h1
}

///|
/// For use as a ret-hash function on `Unit` values (call_mut).
pub fn hash_unit_value(_v : Unit) -> UInt64 {
  hash_unit()
}

///|
pub fn hash_bool(v : Bool) -> UInt64 {
  let bytes : Array[Byte] = [(if v { 1 } else { 0 }).to_byte()]
  let (h1, _) = sip13_128(bytes, (0, 0))
  h1
}

///|
pub fn hash_char(c : Char) -> UInt64 {
  let bytes : Array[Byte] = []
  write_rust_char(bytes, c)
  let (h1, _) = sip13_128(bytes, (0, 0))
  h1
}

///|
/// Rust `Hash for str` = write(utf8 bytes) + write_u8(0xff).
pub fn write_rust_string(bytes : Array[Byte], s : String) -> Unit {
  let utf8 = bytes_of_string_without_term(s)
  for b in utf8 {
    bytes.push(b)
  }
  bytes.push((255).to_byte())
}

///|
/// Rust `Hash for i64` = write_i64 (8 LE bytes).
pub fn write_rust_i64(bytes : Array[Byte], v : Int64) -> Unit {
  append_i64_le(bytes, v)
}

///|
/// Rust `Hash for bool` = write_u8 (1 byte).
pub fn write_rust_bool(bytes : Array[Byte], v : Bool) -> Unit {
  bytes.push((if v { 1 } else { 0 }).to_byte())
}

///|
/// Rust `Hash for char` = write_u32 (4 LE bytes).
pub fn write_rust_char(bytes : Array[Byte], c : Char) -> Unit {
  append_u32_le(bytes, c.to_int())
}

///|
/// Little-endian byte helpers.
fn append_u64_le(bytes : Array[Byte], v : UInt64) -> Unit {
  let mut i = 0
  while i < 8 {
    bytes.push(((v >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
}

///|
fn append_i64_le(bytes : Array[Byte], v : Int64) -> Unit {
  let mut i = 0
  while i < 8 {
    bytes.push(((v.to_uint64() >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
}

///|
fn append_u32_le(bytes : Array[Byte], v : Int) -> Unit {
  let mut i = 0
  while i < 4 {
    bytes.push(((v.to_uint64() >> (i * 8)) & 0xFF).to_byte())
    i = i + 1
  }
}

///|
/// UTF-8 encoding of a string (MoonBit's to_bytes() is UTF-16).
fn bytes_of_string_without_term(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut i = 0
  for ch in s.iter() {
    let cp = ch.to_int()
    if cp <= 0x7F {
      out.push(cp.to_byte())
    } else if cp <= 0x7FF {
      out.push((0xC0 | ((cp >> 6) & 0x1F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      out.push((0xE0 | ((cp >> 12) & 0x0F)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    }
    i = i + 1
  }
  out
}

///| Simple deterministic hash for test-only values of arbitrary types.

///| Not Rust-compatible — used only in hand-written tests where behavior

///| (not hash values) is under test. Generated code uses the Rust-compatible

///|
/// path instead.
pub fn test_hash_int(v : Int) -> UInt64 {
  v.to_uint64()
}

///|
pub fn test_hash_int64(v : Int64) -> UInt64 {
  v.to_uint64()
}

///|
pub fn test_hash_bool(v : Bool) -> UInt64 {
  if v {
    1
  } else {
    0
  }
}

///|
pub fn test_hash_str(v : String) -> UInt64 {
  hash_string(v)
}

///|
pub fn test_hash_unit(v : Unit) -> UInt64 {
  hash_unit()
}

///|
/// Hash an Option by its tag + inner (deterministic, test-only).
pub fn[T] test_hash_opt(v : T?, inner : (T) -> UInt64) -> UInt64 {
  match v {
    None => 0
    Some(x) => (inner(x) << 1) | 1
  }
}

///|
/// Hash an array by folding (deterministic, test-only).
pub fn[T] test_hash_array(v : Array[T], inner : (T) -> UInt64) -> UInt64 {
  let mut acc : UInt64 = 0
  for x in v {
    acc = acc * 31 + inner(x)
  }
  acc
}

///| A placeholder Call type for pure-argument functions (no tracked params).

///| Rust's `Multi<()>` has Call = (); MoonBit can't impl Unit, so tests use

///| this. Hash of the empty stream (like Rust's `()` call, which writes

///|
/// nothing for the call itself).
pub enum NoCall {} derive(Eq, Hash)

///|
impl RustHashable for NoCall with fn write_rust(self, bytes) {
  //| Unit's Hash encoding in Rust is write_u8(0xff); a () call hashes as ()
  append_u64_le(bytes, 0)
}

///| A placeholder Call type for pure-argument functions (no tracked params).

///|
/// MoonBit can't impl user traits for Unit, so this is used instead.
pub(all) enum UnitCall {
  Empty
} derive(Eq, Hash)

///|
pub impl RustHashable for UnitCall with fn write_rust(self, bytes) {
  match self {
    Empty => append_u64_le(bytes, 0)
  }
}
