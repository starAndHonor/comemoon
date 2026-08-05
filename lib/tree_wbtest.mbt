///| Whitebox tests for CallTree, mirroring the semantics of the Rust tests

///| in `refs/comemo/src/tree.rs` (`test_call_tree`, `test_call_tree_quickcheck`).

///|
/// An operation on the tree, mirroring Rust's `Op<C, T>`.
enum Op {
  Insert(Int, Array[(Int, Int)], String)
  Retain(String)
  Manual(Int)
}

///| Runs a script of operations against a fresh tree, checking consistency

///|
/// and that every kept value remains retrievable. Mirrors `test_ops`.
fn test_ops(ops : Array[Op]) -> Unit {
  let tree = CallTree::new()
  //| Model of the kept entries: (key, call->ret map, value)
  let kept : Array[(UInt64, @hashmap.HashMap[IntCall, UInt64], String)] = []

  for op in ops {
    match op {
      Insert(key, seq, value) => {
        let key128 : UInt64 = key.to_uint64()
        let cs = CallSequence::new()
        seq.each(pair => {
          let (c, r) = pair
          ignore(cs.insert(IntCall::I(c), r.to_uint64()))
        })
        match tree.insert(key128, cs, value) {
          Ok(_) => {
            let m : @hashmap.HashMap[IntCall, UInt64] = @hashmap.HashMap([])
            seq.each(pair => {
              let (c, r) = pair
              m[IntCall::I(c)] = r.to_uint64()
            })
            kept.push((key128, m, value))
          }
          Err(_) => ()
        }
      }
      Retain(value) => {
        tree.retain(fn(v) { v == value })
        let mut i = 0
        while i < kept.length() {
          let (key, m, v) = kept[i]
          if v != value {
            if tree.get(key, fn(c) { m[c] }) != None {
              panic()
            }
            ignore(kept.remove(i))
          } else {
            i = i + 1
          }
        }
      }
      Manual(n) =>
        if n == 1 {
          if tree.inner.len() != 5 ||
            tree.leaves.len() != 3 ||
            tree.edges.length() != 7 ||
            tree.start.length() != 1 {
            panic()
          }
        } else if n == 2 {
          if tree.inner.len() != 3 ||
            tree.leaves.len() != 1 ||
            tree.edges.length() != 3 ||
            tree.start.length() != 1 {
            panic()
          }
        }
    }
    tree.assert_consistency()
    //| All kept values must still be retrievable.
    kept.each(entry => {
      let (key, m, value) = entry
      if tree.get(key, fn(c) { m[c] }) != Some(value) {
        panic()
      }
    })
  }
}

///|
test "call_tree_basic" {
  test_ops([
    Insert(0, [(97, 10), (98, 15)], "first"),
    Insert(0, [(97, 10), (98, 20)], "second"),
    Insert(0, [(97, 15), (99, 15)], "third"),
  ])
}

///|
test "call_tree_structural" {
  test_ops([
    Insert(0, [(97, 10), (98, 15)], "first"),
    Insert(0, [(97, 10), (99, 15), (98, 20)], "second"),
    Insert(0, [(97, 15), (98, 30), (99, 15)], "third"),
    Manual(1),
    Retain("second"),
    Manual(2),
  ])
}

///| Deterministic pseudo-random ops generator, mirroring the spirit of

///| `ArbitraryOp` in the Rust quickcheck test: random inserts and retains.

///|
/// Uses a fixed seed so the test is reproducible.
test "call_tree_quickcheck" {
  //| Seeded LCG (same sequence every run).
  fn rand(seed_ref : Ref[Int]) -> Int {
    seed_ref.val = (seed_ref.val * 1103515245 + 12345) & 0x7FFFFFFF
    seed_ref.val
  }
  let seed : Ref[Int] = { val: 42 }

  let tree = CallTree::new()
  let kept : Array[(UInt64, @hashmap.HashMap[IntCall, UInt64], Int)] = []

  let mut step = 0
  while step < 500 {
    let r = rand(seed)
    if r % 3 != 2 {
      //| Insert: random key, random call sequence, random output.
      let key : UInt64 = rand(seed).to_uint64()
      let n_calls = r % 4
      let cs = CallSequence::new()
      let m : @hashmap.HashMap[IntCall, UInt64] = @hashmap.HashMap([])
      let mut j = 0
      let mut call_counter = seed.val
      while j < n_calls {
        call_counter = call_counter + 1
        let ret : UInt64 = rand(seed).to_uint64()
        ignore(cs.insert(IntCall::I(call_counter), ret))
        m[IntCall::I(call_counter)] = ret
        j = j + 1
      }
      let output = rand(seed) % 100
      //| Ignore insert errors (AlreadyExists/MissingCall) like the Rust test.
      match tree.insert(key, cs, output) {
        Ok(_) => kept.push((key, m, output))
        Err(_) => ()
      }
    } else {
      //| Retain: keep outputs above a random threshold.
      let mid = rand(seed) % 100
      tree.retain(fn(v) { v > mid })
      let mut i = 0
      while i < kept.length() {
        let (key, m, v) = kept[i]
        if v <= mid {
          if tree.get(key, fn(c) { m[c] }) != None {
            println(
              "FAIL: retained value still found after retain: step=" +
              step.to_string() +
              " mid=" +
              mid.to_string() +
              " v=" +
              v.to_string(),
            )
            panic()
          }
          ignore(kept.remove(i))
        } else {
          i = i + 1
        }
      }
    }
    tree.assert_consistency()
    kept.each(entry => {
      let (key, m, value) = entry
      let got = tree.get(key, fn(c) { m[c] })
      if got != Some(value) {
        println(
          "FAIL: kept value not retrievable: step=" +
          step.to_string() +
          " key=" +
          key.to_string() +
          "-" +
          "" +
          " value=" +
          value.to_string() +
          " got_some=" +
          (got is Some(_)).to_string(),
        )
        panic()
      }
    })
    step = step + 1
  }
}
