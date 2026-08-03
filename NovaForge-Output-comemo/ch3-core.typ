// 第三章：约束记录与缓存内核
#import "preamble.typ": *

= 三、约束记录与缓存内核

#knowtitle[定位：comemo 的心脏——约束如何被记录、缓存命中如何被验证]

宏生成的代码只是脚手架，真正把 constrained memoization 落到运行时的就是这三个文件：#src[src/constraint.rs] 在一次函数执行期间*记录*所有 tracked 调用及其返回值哈希，形成约束（Constraint）；#src[src/memoize.rs] 是主调度器——查缓存、挂约束、执行、写回，并管理每个被记忆函数专属的 `Cache` 与全局逐出注册表；#src[src/tree.rs] 提供核心数据结构 `CallTree`，把"同一输入哈希 + 一串 (调用, 返回哈希) 前缀链"组织成一棵前缀树（trie），使命中与否取决于 tracked 依赖的返回值是否不变。

#figure(
  block(width: 100%, inset: 4pt)[
    #align(center)[
      #box(fill: sectionbg, inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em)[用户调用 memoized 函数]]
      #h(0.3em)#sym.arrow.r#h(0.3em)
      #box(fill: sectionbg, inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em)[key = hash(非 tracked 参数)]]
      #h(0.3em)#sym.arrow.r#h(0.3em)
      #box(fill: rgb("#e8f6ef"), inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em)[CallTree lookup（oracle 重放）]]
    ]
    #v(0.35em)
    #align(center)[#sym.arrow.b + #text(size: 0.8em)[命中] #h(6em) #sym.arrow.b + #text(size: 0.8em)[未命中]]
    #v(0.35em)
    #align(center)[
      #box(fill: rgb("#e8f6ef"), inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em)[重放 mutable 调用 → 返回缓存输出]]
      #h(1.5em)
      #box(fill: rgb("#fdeaea"), inset: (x: 8pt, y: 6pt), radius: 3pt)[#text(size: 0.82em)[attach Constraint → 执行 → 记录调用 → insert 进树]]
    ]
  ],
  caption: [memoize() 主流程：命中与未命中两条路径],
)

== `Constraint<C>` 的双通道结构

#src[src/constraint.rs:21-27]：

```
ConstraintRepr<C> {
    immutable: CallSequence<C>,   // 只读调用：要去重、要插树
    mutable:   Vec<C>,            // 可变调用：只按序收集，不进树
}
```

- 分离点在 `Sink::emit`（#src[src/constraint.rs:69-76]）：`call.is_mutable()` 为真 → 压入 `mutable` 并返回 `true`；否则交给 `immutable.insert(call, ret)`。
- *为什么可变调用单独收集*：可变调用没有返回值可哈希，无法参与"返回哈希是否一致"的校验，但它们有副作用。#key[命中时函数体根本不执行，副作用必须重放]——所以 `mutable` 随 `CacheEntry` 一起存进树（#src[src/memoize.rs:137-144]），命中时逐条 `input.call_mut(call)` 重放（#src[src/memoize.rs:56-59]）。
- `Constraint::take()`（#src[src/constraint.rs:48-51]）在插入缓存前用 `mem::take` 整体取出两个通道，保证 `Constraint` 是"一次性"的。
- 对外还暴露 `validate()`（#src[src/constraint.rs:34-46]）：对任意 `Track` 值重放 immutable 调用、逐个比对返回哈希。

== `CallSequence<C>`：为插树优化的去重序列

字段（#src[src/constraint.rs:82-89]）：`vec: Vec<Option<(C, u128)>>`（按首次出现顺序，`Option` 支持就地取走）、`map: FxHashMap<u128, usize>`（调用哈希 → 下标）、`cursor: usize`（`next` 游标）。

- *去重插入*（#src[src/constraint.rs:96-119]）：以 `hash::hash(&call)` 为键查 `map`：`Vacant` → 追加；`Occupied` → 去重，且 *debug 构建下*额外检查同一下标处 `ret != ret2` → `panic!("comemo: found differing return values. is there an impure tracked function?")`（:111-117）。#key[这是第一道纯性防线：同一调用参数在同一轮执行里给出不同返回值。]
- *`next` 游标语义*（:122-130）：顺序消费，插入新树节点时使用。
- *`extract` 抢读语义*（:132-139）：按调用哈希取走返回哈希（该槽位之后 `next` 不再产出）。沿已有树路径走时使用。
- 于是 CallTree 的 `insert` 可以交错调用 `extract`（对齐已有路径）与 `next`（消费剩余、开新路径）——这正是前缀树插入算法对序列容器的要求。

== `memoize()` 主流程逐段剖析

#src[src/memoize.rs:17-93]。签名要点：`cache` 是宏为每个函数生成的 `static`；`(storage, constraint)` 必须从调用点外部传入（注释 :21-24：只有这样才有足够长的生命周期把约束 attach 进 `input`）。

+ *enabled 旁路*（:37-44）：`!enabled` 时直接执行返回，不查不写缓存。
+ *128 位 key 哈希*（:47-51）：`SipHasher13` 对 `input.key()` 做 `finish128()`。#key[tracked 部分不进 key]——它由树里的约束链校验。
+ *查缓存*（:54-65）：读锁 `lookup(key, &input)`；命中则：重放 mutable 调用（:56-59）→（lookup 内）age 归零 → 返回 `entry.output.clone()`。#key[函数体零执行]。
+ *未命中：挂约束*（:67-71）：`input.attach(storage, constraint)`——此后所有 tracked 调用同时 `sink.emit(call, ret)` 记入 Constraint。
+ *执行*：`func(input)` 产生 `output`（此阶段不持锁）。
+ *写回*（:74-87）：写锁 `insert(key, constraint, output.clone())`：`Ok`；`AlreadyExists`（并发同参数抢先插入，静默忽略）；`MissingCall`（函数非 reorderably deterministic，*debug 下 panic* `"comemo: memoized function is non-deterministic"`，release 下仅不缓存）。
+ miss 路径无论插入成败都返回真实计算结果。

并发结构：`Cache` 内是 `LazyLock<RwLock<CacheData>>`（#src[src/memoize.rs:114]）；lookup 走读锁、insert 走写锁。递归 memoize（calc 例子里 evaluate 调 evaluate）之所以安全，是因为 execute 阶段不持锁，写锁仅在 insert 的短暂窗口内获取。

== `CallTree`：四张表 + NodeId 编码

#src[src/tree.rs:15-26]：

```
CallTree<C, T> {
    inner:  Slab<InnerNode<C>>,                  // 内部节点：存调用
    leaves: Slab<LeafNode<T>>,                   // 叶子：直接存输出值
    start:  FxHashMap<u128, NodeId>,             // key 哈希 → 起始节点
    edges:  FxHashMap<(InnerId, u128), NodeId>,  // (父节点, 该调用返回哈希) → 子节点
}
```

- `InnerNode { call, children, parent }`（:29-36）：`children` 归零即删除；`parent` 供自底向上剪枝。
- *`NodeId(isize)` 编码*（:234-254）：非负值 = `inner` slab 下标；负值 = `-(i) - 1`（即 `~i`），解出 leaf 下标。两个 Slab 共用一个 id 空间而零开销。（为什么不是 `-i`：否则 leaf 0 和 inner 0 撞号。）
- *语义*：一条从 `start[key]` 到叶子的路径 = "key 相同、且依次做过调用 $c_1 dots c_n$、返回哈希为 $r_1 dots r_n$" 的一次历史执行；`edges[(id_i, r_i)]` 是"在第 i 个调用处，若 oracle 给出的返回哈希是 $r_i$，就往哪走"。#key[同一 key 下，多个调用序列共享公共前缀，返回哈希不同则分叉。]

#figure(
  block(width: 100%, inset: 4pt)[
    #align(center)[
      #box(fill: sectionbg, inset: (x: 7pt, y: 5pt), radius: 3pt)[#text(size: 0.8em)[start\[key\]]]
      #h(0.2em)#sym.arrow.r#h(0.2em)
      #box(fill: sectionbg, inset: (x: 7pt, y: 5pt), radius: 3pt)[#text(size: 0.8em)[n₁: read(α)]]
      #h(0.2em)#sym.arrow.r#super[$r_alpha$]#h(0.2em)
      #box(fill: sectionbg, inset: (x: 7pt, y: 5pt), radius: 3pt)[#text(size: 0.8em)[n₂: read(β)]]
      #align(center)[
        #text(size: 0.8em)[#sym.arrow.b #super[$r_beta$]（旧）#h(0.5em) #h(3em) #sym.arrow.b #super[$r_beta prime$]（新）]
      ]
      #align(center)[
        #box(fill: rgb("#e8f6ef"), inset: (x: 7pt, y: 5pt), radius: 3pt)[#text(size: 0.8em)[leaf: 输出 7]]
        #h(2.8em)
        #box(fill: rgb("#e8f6ef"), inset: (x: 7pt, y: 5pt), radius: 3pt)[#text(size: 0.8em)[leaf: 输出 48]]
      ]
    ]
  ],
  caption: [CallTree 示意：beta.calc 修改前后两条执行路径共享前缀、按返回哈希分叉],
)

== `get`：用 oracle 重放校验

#src[src/tree.rs:57-72]：

```
cursor = start.get(key)?               // 无起始节点即 miss
loop {
    Leaf(id)  => return &leaves[id].value;       // 走到叶子 = 命中
    Inner(id) => ret = oracle(&inner[id].call);  // 对当前 tracked 实例重放该调用
                 cursor = edges.get(&(id, ret))?; // 返回哈希决定走哪条边；缺边即 miss
}
```

oracle 就是 memoize.rs 传入的 `|c| input.call(c)`（#src[src/memoize.rs:156-158]）——在*当前* tracked 输入上重放历史调用。#key[完整值从未被比较，只有 128 位返回哈希参与决策。]

== `insert`：前缀对齐 + 开新路径

#src[src/tree.rs:80-137]。状态机：`cursor`（当前树节点）与 `predecessor: Option<(InnerId, u128)>`（一旦进入"建新路径"模式，记录上一条待连的边）。

- `predecessor.is_none() && cursor 存在`（:90-111）：还在沿已有路径走。若当前节点是叶子 → `AlreadyExists`；否则 `sequence.extract(call)` 取本次执行对同一调用的返回哈希：
  - *`extract` 返回 `None` → `InsertError::MissingCall`*（:99-101）：树路径上的第 N+1 个调用，本次执行没做过——指向 memoized 函数的非确定性（违反 reorderably deterministic，变体文档 :271-275）；
  - 有边 → 继续沿路径走；无边 → 转入建新模式。
- 否则（:113-127）：`sequence.next()` 取下一个新调用，插 `InnerNode`，`link` 挂边（:139-154：起始节点写 `start`，否则写 `edges` 并 `children += 1`）。
- 收尾（:130-137）：整个序列都是已有路径的前缀 → `AlreadyExists`（并发重复插入）；否则插 `LeafNode` 并 `link`。

== `retain`：自叶向根剪枝

#src[src/tree.rs:158-190]：

- 第一阶段 `leaves.retain`（:163-178）：对每个叶子问谓词；删叶子时沿 `parent` 链向上：父节点 `children > 1` 则 `children -= 1` 并停止；否则递归删父、继续向上。
- 第二阶段（:180-190）：用 `exists` 闭包清掉 `edges`/`start` 中指向已删节点的悬挂条目。
- 不变量由 `#[cfg(test)] assert_consistency`（:193-209）在测试里逐步校验。

== `Cache` / `CacheEntry` 与 age 逐出

- `CacheEntry { output, mutable: Vec<C>, age: AtomicUsize }`（#src[src/memoize.rs:137-144]）：`age` 用 `AtomicUsize` 是因为命中路径只持读锁却要把 age 归零（:159）。
- `CacheData::evict`（:149-154）：每条 entry `age += 1`，保留 `age <= max_age` 的。#key[age = 距上次命中经历了多少次逐出，命中即归零]。`max_age = 0` 等价于清空。
- *EVICTORS 全局注册表*（#src[src/memoize.rs:13-14]）：宏为每个 `Cache` 生成初始化代码时调 `register_evictor`（:109-111）挂入该缓存的 evict 函数指针。用户调 `comemo::evict(max_age)`（:101-106）遍历所有注册项逐个逐出，*并联动 `accelerate::evict()`*。Typst 每排版一遍文档就调一次 `evict(30)`，实现"30 轮没用的结果被淘汰"。

== calc 例子完整走一遍

以 `evaluate("eval alpha.calc", files.track())` 为例（#src[examples/calc.rs]）：

+ *首次（miss）*：key = hash("eval alpha.calc")；`start` 无此 key → miss → attach Constraint → 执行：`files.read("alpha.calc")` emit `(read α, h_α)`，递归 evaluate 读取 beta → emit `(read β, h_β)` → insert 建树：`start[key] → n₁(read α) —h_α→ n₂(read β) —h_β→ leaf(7)`。
+ *第二次（未改文件，hit）*：key 相同 → oracle 重放 `read(α)` 得 $h_alpha$ → 边存在 → 重放 `read(β)` 得 $h_beta$ → 叶子 → 命中返回 7，`read` 函数体没执行。
+ *改了 `gamma.calc` 后（仍 hit）*：alpha 的执行链没读过 gamma，重放哈希照旧 → 命中（#src[examples/calc.rs:26-29]）。#key[无关文件的改变不会引起重算]。
+ *改了 `beta.calc` 后（miss）*：oracle 重放 `read(β)` 得新哈希 $h_beta prime ≠ h_beta$ → `edges` 查不到 → miss → 重新执行，新序列以 `(read α, h_α)` 与前缀对齐、从 `read β` 处开新路径插入（#src[examples/calc.rs:31-35]）。

#key[缓存失效的粒度是"实际读到的 tracked 数据"，不是"整个输入"——这正是 constrained memoization 的本质。]

== 本章源码精读路线

建议顺序：*memoize.rs → constraint.rs → tree.rs*（先主流程建立问题感，再看记录器，最后啃数据结构）。

+ #src[src/memoize.rs:17-93]：参数为何从外部传入；命中路径三件事的顺序；`AlreadyExists` 静默吞掉、`MissingCall` debug 下 panic。
+ #src[src/memoize.rs:96-111]：全局逐出如何发现每一个 Cache；`accelerate::evict()` 联动。
+ #src[src/memoize.rs:137-180]：`age` 为何原子；oracle 闭包与 tree.rs `get` 的衔接。
+ #src[src/constraint.rs:67-77]：双通道分流的一行判断。
+ #src[src/constraint.rs:96-139]：`insert`/`next`/`extract` 分别服务谁；debug-only 纯度检查。
+ #src[src/tree.rs:15-26] + :234-254：四张表与 `NodeId` 负值编码。
+ #src[src/tree.rs:57-72]（get）：`?` 运算符天然把"无起始节点/缺边"映射为 miss。
+ #src[src/tree.rs:80-137]（insert）：最难一段。`cursor`/`predecessor` 双状态；两个 `AlreadyExists` 触发点（:93、:130）；`MissingCall` 唯一触发点（:99）。配合 `InsertError` 文档（:264-275）读。
+ #src[src/tree.rs:158-190]（retain）：`children > 1` 停止条件；`inner` 为什么不能直接 `Slab::retain`。
+ #src[src/tree.rs:278-418]（单元测试）：`test_call_tree` 手工构造共享前缀 + 分叉并断言四张表的精确大小，是理解结构的最好样例；`test_ops` 维护影子模型做全量比对，是 quickcheck 范式。

== 易错点与设计权衡

- *`MissingCall` 的行为分裂*（#src[src/memoize.rs:80-85]）：debug panic / release 静默不缓存但结果正确。它几乎总是用户函数在不同轮次对相同 tracked 状态做了不同调用序列，不是 comemo 自身的 bug。
- *两道纯度防线的分工*：`CallSequence::insert` 的 panic 抓"同一轮内同一调用返回值不同"；`MissingCall` 抓"跨轮调用序列结构不同"。前者靠去重顺带检测，后者要靠树的形状才能发现。
- *同 key 多路径并存不是缺陷*：同一 key 下可同时缓存"读过 beta v1"和"读过 beta v2"的执行，两条路径都可能在后续命中。
- *为什么校验用 128 位返回哈希而非完整值*：（a）tracked 返回值可能很大或不可克隆；（b）oracle 重放只需返回 `u128`，加速器还能让重放近乎 O(1)；（c）128 位冲突概率可忽略。代价：理论上哈希碰撞会导致错误命中，comemo 接受这个概率。[推断：权衡理由基于代码与文档语义推断，源码未明文写出。]
- *可变调用不参与校验、只参与重放*：初学者易以为 mutable 调用也会让缓存失效——不会。它不进树、不进 key。若可变方法实际影响了后续只读调用的结果，约束系统无法察觉——这是用户契约。
- *写锁粒度*：insert 持整个 `CacheData` 的写锁，同一函数的并发 miss 串行化；lookup 走读锁可并行。读多写少的负载下这个取舍是对的。
