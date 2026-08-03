///| Global accelerators: per-`Tracked`-instance caches from call hashes to

///| return hashes.
///

///| Mirrors `comemo::accelerate` (Rust). During constraint validation

///| (`CallTree::get` with the oracle), re-executing a tracked method is

///| expensive; the accelerator memoizes `hash(call) -> hash(ret)` so the

///| first validation of a call on a given `Tracked` instance pays the cost

///| and subsequent ones are O(1). Single-threaded: Rust's RwLock/Mutex

///| become a plain `Ref` list.

///| The global list of currently alive accelerators: each is a map from

///|
/// call hashes to return hashes.
let accelerators : Ref[Array[@hashmap.HashMap[UInt128, UInt128]]] = {
  val: Array::new(),
}

///|
/// The current ID of the accelerator.
let next_id : Ref[Int] = { val: 0 }

///|
/// Generate a new accelerator ID for a fresh `Tracked` instance.
pub fn accelerator_id() -> Int {
  let id = next_id.val
  next_id.val = next_id.val + 1
  accelerators.val.push(@hashmap.HashMap([]))
  id
}

///| Evict the accelerators: clear all maps (keeping allocations), and

///|
/// re-base future IDs so stale entries are unreachable.
pub fn evict_accelerators() -> Unit {
  for acc in accelerators.val {
    acc.clear()
  }
}

///| Returns the cached return hash for a call hash on the given accelerator,

///|
/// if present.
pub fn accelerator_get(id : Int, call_hash : UInt128) -> UInt128? {
  if id >= 0 && id < accelerators.val.length() {
    accelerators.val[id].get(call_hash)
  } else {
    None
  }
}

///|
/// Stores the return hash for a call hash on the given accelerator.
pub fn accelerator_insert(
  id : Int,
  call_hash : UInt128,
  ret_hash : UInt128,
) -> Unit {
  while accelerators.val.length() <= id {
    accelerators.val.push(@hashmap.HashMap([]))
  }
  accelerators.val[id][call_hash] = ret_hash
}
