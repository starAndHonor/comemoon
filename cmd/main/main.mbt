///|
/// Demo: calc dependency graph with fine-grained invalidation.
let eval_cache : @lib.Cache[@lib.FilesCall, Int] = @lib.Cache::new()

///|
fn eval(script : String, files : @lib.FilesTracked) -> Int {
  let tracked = files.t
  @lib.memoize(
    eval_cache,
    @lib.Input::new(
      fn() { @lib.hash_string(script) },
      fn(
        rec : @lib.Recorder[@lib.FilesCall],
      ) -> @lib.Recorder[@lib.FilesCall]? {
        tracked.attach(rec)
      },
      fn(c : @lib.FilesCall) -> UInt64 {
        match c {
          Read(path) =>
            tracked.validate(
              @lib.FilesCall::Read(path),
              fn(f : @lib.Files) -> String { f.read(path) },
              @lib.test_hash_str,
            )
          Write(_, _) => 0
        }
      },
      fn(_c : @lib.FilesCall) -> Unit { () },
      fn(prev : @lib.Recorder[@lib.FilesCall]?) -> Unit { tracked.detach(prev) },
    ),
    true,
    fn() {
      let mut total = 0
      let parts = script.split("+").to_array()
      let mut i = 0
      while i < parts.length() {
        let p = parts[i].trim().to_owned()
        if p.has_prefix("eval ") {
          let path = p[5:].to_owned()
          total = total + eval(files.read(path), files)
        } else {
          total = total + @lib.parse_ok(p)
        }
        i = i + 1
      }
      total
    },
  )
}

///|
fn main {
  let files : @lib.Files = { map: @hashmap.HashMap([]) }
  files.write("alpha.calc", "2 + eval beta.calc")
  files.write("beta.calc", "2 + 3")

  let ft : @lib.FilesTracked = @lib.FilesTracked::new(files)
  let r1 = eval("eval alpha.calc", ft)
  println("eval alpha.calc = " + r1.to_string())

  //| Edit an unreferenced file: cache stays hot.
  ft.t.value.val.write("gamma.calc", "42")
  let r2 = eval("eval alpha.calc", ft)
  println(
    "after unrelated edit = " +
    r2.to_string() +
    " (unchanged = " +
    (r1 == r2).to_string() +
    ")",
  )
}
