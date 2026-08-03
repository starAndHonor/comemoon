//! Benchmark suite comparing comemo behavior across scenarios.
//! Run: cargo run --release --example bench
//!
//! Output format (matched by the MoonBit bench):
//!   <scenario>: <n> iters in <total> (<ns>/iter)

use comemo::{memoize, track, Track, Tracked, TrackedMut};
use std::collections::HashMap;
use std::time::Instant;

#[memoize]
fn evaluate(script: &str, files: Tracked<Files>) -> i32 {
    script.split('+').map(str::trim).map(|part| {
        match part.strip_prefix("eval ") {
            Some(path) => evaluate(&files.read(path), files),
            None => part.parse::<i32>().unwrap(),
        }
    }).sum()
}

struct Files(HashMap<String, String>);

#[track]
impl Files {
    fn read(&self, path: &str) -> String {
        self.0.get(path).cloned().unwrap_or_default()
    }
}

/// Run a scenario, printing in a standard format.
fn run<S: FnMut() -> i32>(name: &str, n: usize, mut f: S) {
    let start = Instant::now();
    let mut total = 0;
    for _ in 0..n {
        total += f();
    }
    let elapsed = start.elapsed();
    let per = elapsed.as_nanos() as f64 / n as f64;
    println!("{name}: {n} iters in {elapsed:?} ({per:.2} ns/iter) [total={total}]");
}

#[memoize]
fn double(x: u32) -> u32 {
    2 * x
}

#[memoize]
fn poly(x: u64) -> u64 {
    x * x + 3 * x + 7
}

fn main() {
    // Scenario 1: cold-ish cache (new arg each call, small arg space so some
    // hits occur) — measures lookup+insert.
    run("s1_cold_single", 100_000, || {
        double(0xDEAD + (rand() % 1000)) as i32
    });

    // Scenario 2: warm hits on a small memoized fn (same args repeatedly).
    run("s2_warm_hits", 1_000_000, || double(42) as i32);

    // Scenario 3: calc dependency graph, unrelated edits (cache stays hot).
    let mut files = Files(HashMap::new());
    files.0.insert("a.calc".into(), "1 + eval b.calc".into());
    files.0.insert("b.calc".into(), "2 + 3".into());
    files.0.insert("c.calc".into(), "8 + 3".into());
    let mut i = 0;
    run("s3_calc_unrelated_edit", 100_000, || {
        files.0.insert("c.calc".into(), format!("{} + 3", i % 100));
        i += 1;
        evaluate("eval a.calc", files.track())
    });

    // Scenario 4: 1000 same-key contexts, each validated twice (accelerator).
    let contexts: Vec<Files> = (0..1000)
        .map(|i| {
            let mut f = Files(HashMap::new());
            f.0.insert("x.calc".into(), format!("{i}"));
            f
        })
        .collect();
    let start = Instant::now();
    for f in &contexts {
        evaluate("eval x.calc", f.track());
    }
    for f in &contexts {
        evaluate("eval x.calc", f.track());
    }
    let elapsed = start.elapsed();
    println!("s4_same_key_1000x2: 2000 iters in {elapsed:?} ({:.2} ns/iter)",
        elapsed.as_nanos() as f64 / 2000.0);

    // Scenario 5: eviction pressure — insert many keys, evict, re-access.
    run("s5_evict_cycle", 1_000, || {
        let mut acc = 0;
        for k in 0..100 {
            acc += poly(k);
        }
        comemo::evict(10);
        acc as i32
    });

    // Scenario 6: TrackedMut — mutable calls replayed on hit.
    let mut counter = Counter(0);
    let mut i = 0;
    run("s6_trackedmut_mutable", 100_000, || {
        counter.0 = i;
        i += 1;
        mutable_eval(1, counter.track_mut())
    });

    // Scenario 7: 5 tracked params (bundle_impl pattern).
    let world = SmallWorld { tag: 1 };
    let intro = SmallIntro { tag: 2 };
    let traced = Traced(3);
    let route = Route(4);
    let mut sink = Sink(0);
    let mut i = 0;
    run("s7_multi5_bundle", 100_000, || {
        i += 1;
        five(
            world.track(),
            intro.track(),
            traced.track(),
            route.track(),
            sink.track_mut(),
            i,
        )
    });
}

/// Simple deterministic pseudo-random (xorshift), avoids std::rand dep.
fn rand() -> u32 {    use std::sync::atomic::{AtomicU32, Ordering};
    static S: AtomicU32 = AtomicU32::new(0x12345678);
    let mut x = S.load(Ordering::SeqCst);
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    S.store(x, Ordering::SeqCst);
    x
}

// --- Scenario 6: TrackedMut ---------------------------------------------

struct Counter(i32);

#[track]
impl Counter {
    fn add(&mut self, n: i32) {
        self.0 += n;
    }
}

#[memoize]
fn mutable_eval(n: i32, mut counter: TrackedMut<Counter>) -> i32 {
    counter.add(n);
    n
}

// --- Scenario 7: 5 tracked params ----------------------------------------

struct SmallWorld {
    tag: u32,
}

#[track]
impl SmallWorld {
    fn query(&self, k: u32) -> u32 {
        self.tag + k
    }
}

struct SmallIntro {
    tag: u32,
}

#[track]
impl SmallIntro {
    fn query(&self, k: u32) -> u32 {
        self.tag + k
    }
}

struct Traced(u32);

#[track]
impl Traced {
    fn push(&self, k: u32) -> u32 {
        self.0 + k
    }
}

struct Route(u32);

#[track]
impl Route {
    fn resolve(&self, k: u32) -> u32 {
        self.0 + k
    }
}

#[derive(Clone, Hash)]
struct Sink(i32);

#[track]
impl Sink {
    fn push(&mut self, k: i32) {
        self.0 += k;
    }
}


#[memoize]
fn five(
    world: Tracked<SmallWorld>,
    intro: Tracked<SmallIntro>,
    traced: Tracked<Traced>,
    route: Tracked<Route>,
    mut sink: TrackedMut<Sink>,
    k: u32,
) -> i32 {
    sink.push(k as i32);
    (world.query(k) + intro.query(k) + traced.push(k) + route.resolve(k)) as i32
}

