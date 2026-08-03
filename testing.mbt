///| Global hit/miss oracle for tests, mirroring `comemo::testing` (Rust).

///| Rust's version is a thread-local; MoonBit tests run in one thread per

///| package, and tests must reset the flag before each assertion (Rust uses

///|
/// `#[serial]`; we reset explicitly instead).
let last_was_hit_flag : Ref[Bool] = { val: false }

///|
/// Whether the last memoized call was a cache hit.
pub fn last_was_hit() -> Bool {
  last_was_hit_flag.val
}

///|
/// Resets the oracle (call before a fresh assertion).
pub fn reset_oracle() -> Unit {
  last_was_hit_flag.val = false
}

///|
/// Records a cache hit.
pub fn register_hit() -> Unit {
  last_was_hit_flag.val = true
}

///|
/// Records a cache miss.
pub fn register_miss() -> Unit {
  last_was_hit_flag.val = false
}
