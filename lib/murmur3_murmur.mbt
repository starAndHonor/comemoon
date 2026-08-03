///| Core MurmurHash3 implementation - Base digest structure and interfaces
/// Port of github.com/twmb/murmur3 package to MoonBit
/// 
/// This is a native MoonBit implementation of Austin Appleby's third MurmurHash revision (aka MurmurHash3).
/// 
/// Unlike the canonical source, this library always reads bytes as little
/// endian numbers. This makes the hashes portable across architectures.
/// 
/// The reference algorithm has been adapted to support streaming mode.

///|
/// Block mixer interface - defines the core mixing behavior for different hash sizes
priv trait BMixer {
  /// Mix a block of bytes and return any remaining tail bytes
  fn bmix(Self, Bytes) -> Bytes

  /// Get the size of the hash output in bytes 
  fn size(Self) -> Int

  /// Reset the internal state
  fn reset(Self) -> Unit
}

///|
/// Base digest structure for streaming hash computation
/// Contains common state shared by all MurmurHash3 variants
priv struct Digest {
  /// Cumulative length of all digested input
  mut clen : Int
  /// Pending tail bytes (0 to size()-1 bytes)  
  mut tail : Bytes
  /// Internal buffer for tail bytes (expected to be size() large)
  buf : FixedArray[Byte]
}

///|
/// Create a new digest with the specified buffer size
fn Digest::new(buf_size : Int) -> Digest {
  { clen: 0, tail: Bytes::new(0), buf: FixedArray::make(buf_size, 0) }
}

///|
/// Write data to the digest
/// Returns the number of bytes written (always equals input length)
fn[T : BMixer] Digest::write(self : Digest, bmixer : T, data : Bytes) -> Unit {
  let n = data.length()
  self.clen += n
  let mut p = data
  if self.tail.length() > 0 {
    // Stick back pending bytes
    let nfree = bmixer.size() - self.tail.length() // nfree ∈ [1, size()-1]
    if nfree < p.length() {
      // One full block can be formed
      let block_array = Array::new()
      for i = 0; i < self.tail.length(); i = i + 1 {
        block_array.push(self.tail[i])
      }
      for i = 0; i < nfree; i = i + 1 {
        block_array.push(p[i])
      }
      let block = Bytes::from_array(block_array)
      p = p[nfree:].to_owned()
      bmixer.bmix(block) |> ignore // No tail returned
    } else {
      // Tail's buf is large enough to prevent reallocs
      let new_tail_array = Array::new()
      for i = 0; i < self.tail.length(); i = i + 1 {
        new_tail_array.push(self.tail[i])
      }
      for i = 0; i < p.length(); i = i + 1 {
        new_tail_array.push(p[i])
      }
      p = Bytes::from_array(new_tail_array)
    }
  }
  self.tail = bmixer.bmix(p)

  // Keep own copy of the 0 to size()-1 pending bytes
  let tail_len = self.tail.length().min(self.buf.length())
  for i = 0; i < tail_len; i = i + 1 {
    self.buf[i] = self.tail[i]
  }
  let tail_array = Array::new()
  for i = 0; i < tail_len; i = i + 1 {
    tail_array.push(self.buf[i])
  }
  self.tail = Bytes::from_array(tail_array)
}

///|
/// Reset the digest to initial state
fn[T : BMixer] Digest::reset(self : Digest, bmixer : T) -> Unit {
  self.clen = 0
  self.tail = Bytes::new(0)
  bmixer.reset()
}
