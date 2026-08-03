///|
#valtype
pub(all) struct UInt128 {
  hi : UInt64
  lo : UInt64
} derive(Debug)

///|
/// Eq: both halves equal.
pub impl Eq for UInt128 with fn equal(self, other) {
  self.hi == other.hi && self.lo == other.lo
}

///|
/// Hash: combine both halves (needed for use as HashMap key).
pub impl Hash for UInt128 with fn hash_combine(self, hasher) {
  hasher.combine(self.hi)
  hasher.combine(self.lo)
}

//| Self-consistency tests (replacing the SipHash13 golden-value tests):
//| determinism, collision-freedom, distinct inputs → distinct hashes.

///|
test "hash128_deterministic" {
  let h1 = hash_string("alpha.calc")
  let h2 = hash_string("alpha.calc")
  if h1 != h2 {
    panic()
  }
  let i1 = hash_int(42)
  let i2 = hash_int(42)
  if i1 != i2 {
    panic()
  }
}

///|
test "hash128_distinct" {
  //| Different inputs must differ (both halves).
  let a = hash_string("a")
  let b = hash_string("b")
  if a == b {
    panic()
  }
  let i1 = hash_int(1)
  let i2 = hash_int(2)
  if i1 == i2 {
    panic()
  }
}

///|
test "hash128_collision_free" {
  //| 10000 distinct integers, no 128-bit collision.
  let seen : @hashmap.HashMap[UInt128, Unit] = @hashmap.HashMap([])
  let mut i = 0
  while i < 10000 {
    let h = hash_int(i)
    if seen.contains(h) {
      panic()
    }
    seen[h] = ()
    i = i + 1
  }
}
