///| Demo-side tracked type definition. The generator parses this file and

///| emits `comemo_gen.mbt` with the Call enum and surface wrapper methods.

///|

///| `#comemo.track` marks a tracked type. This mirrors what a downstream

///| user writes in their own package: mark a type, run the generator, and

///|
/// get a tracked surface with zero boilerplate.
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
