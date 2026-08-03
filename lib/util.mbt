///|
/// Parse an integer, defaulting to 0 on error (avoids raise in closures).
pub fn parse_ok(s : String) -> Int {
  let v = s[:]
  if v.is_empty() {
    0
  } else {
    let mut acc = 0
    let mut neg = false
    let mut j = 0
    let chars = v.to_array()
    while j < chars.length() {
      let ch = chars[j]
      if ch == '-' {
        neg = true
      } else {
        acc = acc * 10 + ch.to_int() - 48
      }
      j = j + 1
    }
    if neg {
      -acc
    } else {
      acc
    }
  }
}
