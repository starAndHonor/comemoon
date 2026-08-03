///| Phase 4 verification: the generated `FilesTracked` API (from

///| `user_tracked.mbt` + `comemo_gen.mbt`) makes calc-style tracked usage

///|
/// boilerplate-free — no manual Call enum, no manual surface methods.
let gen_eval_cache : Cache[FilesCall, Int] = Cache::new()

//| The oracle: replay a call on the tracked value. This is the one piece
//| that still needs the user's read semantics (the generator cannot know
//| what `Files::read` returns); the Phase 4 generator emits this wiring.

///|
fn gen_oracle(t : Tracked[Files, FilesCall], c : FilesCall) -> UInt128 {
  match c {
    Read(path) =>
      t.validate(
        FilesCall::Read(path),
        fn(f : Files) -> String { f.read(path) },
        test_hash_str,
      )
    Write(_, _) => hash_zero()
  }
}

///|
fn gen_evaluate(script : String, files : FilesTracked) -> Int {
  let tracked = files.t
  memoize(
    gen_eval_cache,
    Input::new(
      fn() { hash_string(script) },
      fn(rec : Recorder[FilesCall]) -> Recorder[FilesCall]? {
        tracked.attach(rec)
      },
      fn(c : FilesCall) -> UInt128 { gen_oracle(tracked, c) },
      fn(_c : FilesCall) -> Unit { () },
      fn(prev : Recorder[FilesCall]?) -> Unit { tracked.detach(prev) },
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
          total = total + gen_evaluate(files.read(path), files)
        } else {
          total = total + parse_ok(p)
        }
        i = i + 1
      }
      total
    },
  )
}

///|
test "generated_calc" {
  let files : Files = { map: @hashmap.HashMap([]) }
  files.write("alpha.calc", "2 + eval beta.calc")
  files.write("beta.calc", "2 + 3")

  //| Construct the surface wrapper — same as Rust's `files.track()`.
  let ft : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft) != 7 || last_was_hit() {
    panic()
  }
  reset_oracle()
  if gen_evaluate("eval beta.calc", ft) != 5 || last_was_hit() {
    panic()
  }

  //| Unreferenced file change → hit. Re-wrap like Rust's `files.track()`.
  ft.t.value.val.write("gamma.calc", "42")
  let ft3 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft3) != 7 || !last_was_hit() {
    panic()
  }

  //| Referenced file change → miss.
  ft.t.value.val.write("beta.calc", "4 + eval gamma.calc")
  let ft4 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval beta.calc", ft4) != 46 || last_was_hit() {
    panic()
  }
  let ft5 : FilesTracked = FilesTracked::new(files)
  reset_oracle()
  if gen_evaluate("eval alpha.calc", ft5) != 48 || last_was_hit() {
    panic()
  }
}
