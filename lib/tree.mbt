///| A tree data structure that associates a value with a key hash and a

///| sequence of (call, return hash) pairs.
///

///| Allows to efficiently query for a value for which every call in the

///| sequence yielded the same return hash as a given oracle function will

///|
/// yield for that call. Mirrors `comemo::tree::CallTree` (Rust).
pub struct CallTree[C, T] {
  /// Inner nodes, storing calls.
  inner : Slab[InnerNode[C]]
  /// Leaf nodes, directly storing outputs.
  leaves : Slab[LeafNode[T]]
  /// The initial node for the given key hash.
  mut start : @hashmap.HashMap[UInt128, Int]
  /// Maps from parent nodes to child nodes. The key is a pair of an inner
  ///| node ID and a return hash for that call. The value is the node to
  ///| transition to.
  mut edges : @hashmap.HashMap[(Int, UInt128), Int]
}

///|
/// An inner node in the call tree.
struct InnerNode[C] {
  /// The call at this node.
  call : C
  /// How many children the node has. If this reaches zero, the node is
  ///| deleted.
  mut children : Int
  /// The node's parent.
  parent : Int?
}

///|
/// A leaf node in the call tree.
struct LeafNode[T] {
  /// The value.
  value : T
  /// The node's parent.
  parent : Int?
}

///| An error that can occur during insertion of a call sequence into the

///|
/// call tree.
pub enum InsertError {
  /// A call sequence that is a prefix of the used one was already inserted.
  AlreadyExists
  /// The calls from the sequence gave results matching the first N ones
  ///| from an existing sequence S in the tree, but the N+1th call from S
  ///| does not exist in the given `sequence`. This points towards
  ///| non-determinism in the memoized function the `sequence` belongs to.
  MissingCall
} derive(Eq, Debug)

///|
/// Creates an empty call tree.
pub fn[C, T] CallTree::new() -> CallTree[C, T] {
  {
    inner: Slab::new(),
    leaves: Slab::new(),
    start: @hashmap.HashMap([]),
    edges: @hashmap.HashMap([]),
  }
}

///|
/// Retrieves the output value for the given key and oracle.
pub fn[C, T] CallTree::get(
  self : CallTree[C, T],
  key : UInt128,
  oracle : (C) -> UInt128,
) -> T? {
  let mut cursor : Int? = self.start.get(key)
  while cursor is Some(_) {
    let nid = cursor.unwrap()
    if nid >= 0 {
      //| Inner node: replay the recorded call, follow the edge labeled
      //| with the oracle's return hash.
      let id = nid
      let call_opt : C? = match self.inner.data[id] {
        Some(node) => Some(node.call)
        None => None
      }
      match call_opt {
        None => return None
        Some(call) => {
          let ret = oracle(call)
          cursor = self.edges.get((id, ret))
        }
      }
    } else {
      //| Leaf node: the output.
      let id = -nid - 1
      return match self.leaves.data[id] {
        Some(node) => Some(node.value)
        None => None
      }
    }
  }
  None
}

///|
/// Inserts a key and a call sequence and its associated value into the tree.
pub fn[C : RustHashable, T] CallTree::insert(
  self : CallTree[C, T],
  key : UInt128,
  sequence : CallSequence[C],
  value : T,
) -> Result[Unit, InsertError] {
  let mut cursor : Int? = self.start.get(key)
  let mut predecessor : (Int, UInt128)? = None
  let seq = sequence

  while true {
    match predecessor {
      None =>
        match cursor {
          Some(pos) => {
            if pos < 0 {
              return Err(AlreadyExists)
            }
            let id = pos
            let call_opt : C? = match self.inner.data[id] {
              Some(node) => Some(node.call)
              None => None
            }
            match call_opt {
              None => return Err(MissingCall)
              Some(call) =>
                match seq.extract(call) {
                  None => return Err(MissingCall)
                  Some(ret) => {
                    let pair = (id, ret)
                    match self.edges.get(pair) {
                      Some(next) => cursor = Some(next)
                      None => predecessor = Some(pair)
                    }
                  }
                }
            }
          }
          None =>
            //| We are adding a new node to the tree for the next call in the
            //| sequence.
            match seq.next() {
              None => break
              Some((call, ret)) => {
                let new_inner_id = self.inner.insert({
                  call,
                  children: 0,
                  parent: predecessor.map(fn(p) { p.0 }),
                })
                let new_id = node_inner(new_inner_id)
                self.link(cursor is None, key, predecessor, new_id)
                predecessor = Some((new_inner_id, ret))
                cursor = Some(new_id)
              }
            }
        }
      Some(_) =>
        //| We are already building a new path; append remaining calls.
        match seq.next() {
          None => break
          Some((call, ret)) => {
            let new_inner_id = self.inner.insert({
              call,
              children: 0,
              parent: predecessor.map(fn(p) { p.0 }),
            })
            let new_id = node_inner(new_inner_id)
            self.link(cursor is None, key, predecessor, new_id)
            predecessor = Some((new_inner_id, ret))
            cursor = Some(new_id)
          }
        }
    }
  }

  if predecessor is None && cursor is Some(_) {
    return Err(AlreadyExists)
  }

  let target = node_leaf(
    self.leaves.insert({ value, parent: predecessor.map(fn(p) { p.0 }) }),
  )
  self.link(cursor is None, key, predecessor, target)
  Ok(())
}

///|
/// Creates a new link between two nodes.
fn[C, T] CallTree::link(
  self : CallTree[C, T],
  at_start : Bool,
  key : UInt128,
  from : (Int, UInt128)?,
  to : Int,
) -> Unit {
  if at_start {
    self.start[key] = to
  }
  match from {
    Some(pair) => {
      let node = self.inner.data[pair.0].unwrap()
      node.children = node.children + 1
      self.edges[pair] = to
    }
    None => ()
  }
}

///| Removes all call sequences from the tree for whose values the predicate

///|
/// returns `false`.
pub fn[C, T] CallTree::retain(self : CallTree[C, T], f : (T) -> Bool) -> Unit {
  //| Prune from the leaves upwards, starting with the outputs.
  let mut i = 0
  while i < self.leaves.data.length() {
    let should_delete : Bool = match self.leaves.data[i] {
      Some(node) => !f(node.value)
      None => false
    }
    if should_delete {
      //| Delete parents iteratively while we are the only child.
      let mut parent : Int? = match self.leaves.data[i] {
        Some(node) => node.parent
        None => None
      }
      while true {
        match parent {
          None => break
          Some(inner_id) => {
            let node = self.inner.data[inner_id].unwrap()
            if node.children > 1 {
              node.children = node.children - 1
              break
            } else {
              parent = node.parent
              self.inner.remove(inner_id)
            }
          }
        }
      }
      self.leaves.remove(i)
    }
    i = i + 1
  }

  //| Prune edges that point to removed nodes.
  let new_edges : @hashmap.HashMap[(Int, UInt128), Int] = @hashmap.HashMap([])
  self.edges.each((pair, node) => {
    if self.exists_node(node) {
      new_edges[pair] = node
    }
  })
  self.edges = new_edges

  //| Prune start entries that point to removed nodes.
  let new_start : @hashmap.HashMap[UInt128, Int] = @hashmap.HashMap([])
  self.start.each((key, node) => {
    if self.exists_node(node) {
      new_start[key] = node
    }
  })
  self.start = new_start
}

///|
/// Checks whether the given node survived the pruning.
fn[C, T] CallTree::exists_node(self : CallTree[C, T], node : Int) -> Bool {
  if node >= 0 {
    self.inner.contains(node)
  } else {
    self.leaves.contains(-node - 1)
  }
}

///|
/// Checks a few invariants of the data structure. Whitebox test helper.
fn[C, T] CallTree::assert_consistency(self : CallTree[C, T]) -> Unit {
  self.start.each((_key, node) => if !self.exists_node(node) { panic() })
  self.edges.each((pair, node) => {
    let (inner_id, _ret) = pair
    if !self.exists_node(node) || !self.inner.contains(inner_id) {
      panic()
    }
  })
}

///| Identifies a node in the call tree: non-negative = inner node index,

///|
/// negative = leaf node (`-(index) - 1`).
fn node_inner(i : Int) -> Int {
  i
}

///|
fn node_leaf(i : Int) -> Int {
  -i - 1
}

///| A slab allocator backed by a dense array plus a free list, mirroring

///| Rust's `slab::Slab`: `insert` returns an index, `remove` frees it for

///|
/// reuse.
struct Slab[T] {
  data : Array[T?]
  free : Array[Int]
}

///|
fn[T] Slab::new() -> Slab[T] {
  { data: Array::new(), free: Array::new() }
}

///|
fn[T] Slab::insert(self : Slab[T], value : T) -> Int {
  match self.free.pop() {
    Some(id) => {
      self.data[id] = Some(value)
      id
    }
    None => {
      self.data.push(Some(value))
      self.data.length() - 1
    }
  }
}

///|
fn[T] Slab::remove(self : Slab[T], id : Int) -> Unit {
  self.data[id] = None
  self.free.push(id)
}

///|
fn[T] Slab::contains(self : Slab[T], id : Int) -> Bool {
  id >= 0 && id < self.data.length() && self.data[id] is Some(_)
}

///|
/// The number of live slots (excluding freed ones).
fn[T] Slab::len(self : Slab[T]) -> Int {
  self.data.length() - self.free.length()
}
