///| Test-only tracked types (enums + their RustHashable impls).

///| Defined in the main package because MoonBit test files (separate

///|
/// compilation units) cannot impl custom traits.
pub(all) enum CtxCall {
  Location
  Styles
} derive(Hash, Eq)

///|
pub impl RustHashable for CtxCall with fn write_rust(self, bytes) {
  match self {
    Location => append_u64_le(bytes, 0)
    Styles => append_u64_le(bytes, 1)
  }
}

///|
pub(all) enum OOCall {
  OOLocation
  OOStyles
} derive(Hash, Eq)

///|
pub impl RustHashable for OOCall with fn write_rust(self, bytes) {
  match self {
    OOLocation => append_u64_le(bytes, 0)
    OOStyles => append_u64_le(bytes, 1)
  }
}

///|
pub(all) enum TesterCall {
  SelfRef
  ByValue(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for TesterCall with fn write_rust(self, bytes) {
  match self {
    SelfRef => append_u64_le(bytes, 0)
    ByValue(h) => {
      append_u64_le(bytes, 1)
      write_rust_string(bytes, h)
    }
  }
}

///|
pub(all) enum EmitterCall {
  Emit(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for EmitterCall with fn write_rust(self, bytes) {
  match self {
    Emit(m) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, m)
    }
  }
}

///|
pub(all) enum CounterCall {
  Add(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for CounterCall with fn write_rust(self, bytes) {
  match self {
    Add(n) => {
      append_u64_le(bytes, 0)
      append_i64_le(bytes, n.to_int64())
    }
  }
}

///|
pub(all) enum ChainCall {
  Contains(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for ChainCall with fn write_rust(self, bytes) {
  match self {
    Contains(v) => {
      append_u64_le(bytes, 0)
      append_i64_le(bytes, v.to_int64())
    }
  }
}

///|
pub(all) enum LoaderCall {
  Load(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for LoaderCall with fn write_rust(self, bytes) {
  match self {
    Load(p) => {
      append_u64_le(bytes, 0)
      write_rust_string(bytes, p)
    }
  }
}

///|
/// Call type wrapping an Int (for CallSequence unit tests).
pub(all) enum IntCall {
  I(Int)
} derive(Hash, Eq)

///|
pub impl RustHashable for IntCall with fn write_rust(self, bytes) {
  match self {
    I(v) => append_i64_le(bytes, v.to_int64())
  }
}

///|
/// Call type wrapping a String (for CallTree unit tests).
pub(all) enum StrCall {
  S(String)
} derive(Hash, Eq)

///|
pub impl RustHashable for StrCall with fn write_rust(self, bytes) {
  match self {
    S(v) => write_rust_string(bytes, v)
  }
}
