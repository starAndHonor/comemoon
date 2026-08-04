// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "username/comemoon"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ "incremental", "memoization", "tracking", "cache" ]

preferred_target = "wasm"

description = "Incremental computation through constrained memoization (MoonBit port of comemo)."

rule(name: "comemo-gen", command: "python3 gen/gen.py $input $output")
rule(name: "comemo-gen-lib", command: "python3 gen/gen.py $input $output @lib.")

options(
  exclude: [
    "refs",
    "NovaForge-Output-comemo",
    "_build",
    "lib/*_test.mbt",
    "lib/*_wbtest.mbt",
    "lib/test_types.mbt",
    "lib/bench_shared.mbt",
    "MIGRATION-*.md",
    "PORTING-PLAN.md",
    "GAP-PLAN.md",
  ],
)
