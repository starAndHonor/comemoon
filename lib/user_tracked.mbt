///| User-side tracked type definition. The generator parses this file and

///| emits `comemo_gen.mbt` with the Call enum and surface wrapper methods.
///

///| `#comemo.track` marks a tracked type. The struct + methods are written

///| normally (like Rust's `#[track] impl`). Generator rules:

///| - struct fields are the data (accessed via the tracked value)

///| - each `fn Type::method(self, ...)` becomes a Call enum variant + a

///|   surface wrapper that records the call

///|
/// - `&mut self`-style mutation is not supported yet (immutable only)
#comemo.track
pub(all) struct Files {
  map : @hashmap.HashMap[String, String]
}

///|
pub fn Files::write(self : Files, path : String, text : String) -> Unit {
  self.map[path] = text
}

///|
pub fn Files::read(self : Files, path : String) -> String {
  self.map.get(path).unwrap_or("")
}

///|
#comemo.track
pub trait DataSource {
  fn fetch(Self, key : String) -> Int
  fn size(Self) -> Int
}
