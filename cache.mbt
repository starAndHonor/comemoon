///|
/// The global list of eviction functions.
let evictors : Ref[Array[(Int) -> Unit]] = { val: Array::new() }

///|
/// Register an eviction function in the global list.
pub fn register_evictor(evict : (Int) -> Unit) -> Unit {
  evictors.val.push(evict)
}

///| Evict the global cache: removes all memoized results whose age is larger

///| than or equal to `max_age`. The age of a result grows by one during each

///| eviction and is reset to zero on a cache hit. `max_age = 0` clears the

///|
/// whole cache.
pub fn evict(max_age : Int) -> Unit {
  for evictor in evictors.val {
    evictor(max_age)
  }
}

///|
/// A cache for a single memoized function.
pub struct Cache[C, O] {
  tree : CallTree[C, CacheEntry[C, O]]
}

///|
/// A memoized result.
struct CacheEntry[C, O] {
  /// The memoized function's output.
  output : O
  /// Mutable tracked calls that must be replayed on hit.
  mutable : Array[C]
  /// How many evictions have passed since the entry was last used.
  age : Ref[Int]
}

///|
/// Creates an empty cache and registers its evictor.
pub fn[C, O] Cache::new() -> Cache[C, O] {
  let cache : Cache[C, O] = { tree: CallTree::new() }
  register_evictor(fn(max_age : Int) { cache.evict(max_age) })
  cache
}

///|
/// Evict all entries whose age is larger than or equal to `max_age`.
pub fn[C, O] Cache::evict(self : Cache[C, O], max_age : Int) -> Unit {
  self.tree.retain(fn(entry : CacheEntry[C, O]) -> Bool {
    entry.age.val = entry.age.val + 1
    entry.age.val <= max_age
  })
}

///|
/// Looks for a matching entry, resetting its age on hit.
fn[C, O] Cache::lookup(
  self : Cache[C, O],
  key : UInt64,
  oracle : (C) -> UInt64,
) -> CacheEntry[C, O]? {
  match self.tree.get(key, oracle) {
    Some(entry) => {
      entry.age.val = 0
      Some(entry)
    }
    None => None
  }
}

///|
/// Inserts an entry into the cache.
fn[C : RustHashable, O] Cache::insert(
  self : Cache[C, O],
  key : UInt64,
  constraint : Constraint[C],
  output : O,
) -> Result[Unit, InsertError] {
  let (immutable, mutable) = constraint.take()
  self.tree.insert(key, immutable, { output, mutable, age: { val: 0 } })
}
