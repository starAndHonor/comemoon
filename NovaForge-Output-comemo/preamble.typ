// NovaForge comemo 笔记 — 共享样式与自定义函数
// 颜色系统：深蓝主标题、墨绿节标题、橙红强调、紫红真题/源码、蓝色提示、绿色练习、浅蓝灰标题背景

#let titlecolor = rgb("#1a3d6e")
#let sectioncolor = rgb("#1e5b4a")
#let emphcolor = rgb("#c0392b")
#let supercolor = rgb("#8e2d8e")
#let infocolor = rgb("#2471a3")
#let practicecolor = rgb("#1e8449")
#let examplecolor = rgb("#7d6608")
#let sectionbg = rgb("#e8eef5")
#let codebg = rgb("#f6f8fa")
#let faintgray = rgb("#666666")

// 强调：橙红粗体
#let key(it) = text(fill: emphcolor, weight: "bold")[#it]

// 源码引用：紫红
#let super(it) = text(fill: supercolor, weight: "bold")[#it]

// 文件:行号 引用
#let src(it) = text(fill: supercolor, size: 0.85em, font: "DejaVu Sans Mono")[#it]

// 带框公式/核心结论
#let formula(it) = block(
  stroke: (left: 2.5pt + titlecolor),
  inset: (left: 8pt, top: 5pt, bottom: 5pt),
  width: 100%,
)[#text(fill: titlecolor, size: 0.95em)[#it]]

// 蓝灰背景标题栏
#let knowtitle(it) = block(
  fill: sectionbg,
  inset: (x: 6pt, y: 4pt),
  radius: 2pt,
  width: 100%,
  above: 0.9em,
  below: 0.5em,
)[#text(fill: titlecolor, weight: "bold", size: 0.95em)[#it]]

// 提示框
#let infobox(it) = block(
  fill: rgb("#eaf2f8"),
  stroke: (left: 2.5pt + infocolor),
  inset: (left: 8pt, top: 5pt, bottom: 5pt, right: 6pt),
  radius: 2pt,
  width: 100%,
  above: 0.7em,
  below: 0.7em,
)[#text(size: 0.9em)[#text(fill: infocolor, weight: "bold")[提示：]#it]]

// 易错/警告框
#let warning(it) = block(
  fill: rgb("#fdf2e9"),
  stroke: (left: 2.5pt + emphcolor),
  inset: (left: 8pt, top: 5pt, bottom: 5pt, right: 6pt),
  radius: 2pt,
  width: 100%,
  above: 0.7em,
  below: 0.7em,
)[#text(size: 0.9em)[#text(fill: emphcolor, weight: "bold")[易错点：]#it]]

// 代码块（统一风格）
#let codeblock(it) = block(
  fill: codebg,
  inset: (x: 8pt, y: 6pt),
  radius: 2pt,
  width: 100%,
  above: 0.6em,
  below: 0.6em,
)[#text(size: 0.82em, font: "DejaVu Sans Mono")[#it]]

// 年份/来源标签（沿用期末模式惯例，此处用于版本/来源标注）
#let srclabel(it) = text(fill: supercolor, size: 0.85em)[\[#it\]]

// 页面与全局样式
#let novaforge-style(doc) = {
  set page(
    paper: "a4",
    margin: (top: 1.6cm, bottom: 1.6cm, left: 1.8cm, right: 1.8cm),
    header: align(right)[#text(size: 0.75em, fill: faintgray)[comemo 原理深度介绍与源码阅读指南]],
    numbering: "1",
  )
  set text(size: 10pt, lang: "zh")
  set par(justify: true, leading: 0.62em)
  set heading(numbering: none)
  show heading.where(level: 1): it => block(above: 1.4em, below: 0.7em)[
    #text(fill: titlecolor, size: 1.45em, weight: "bold")[#it.body]
    #v(-0.35em)#line(length: 100%, stroke: 0.8pt + titlecolor)
  ]
  show heading.where(level: 2): it => block(above: 1.1em, below: 0.5em)[
    #text(fill: sectioncolor, size: 1.15em, weight: "bold")[#it.body]
  ]
  show heading.where(level: 3): it => block(above: 0.9em, below: 0.4em)[
    #text(fill: sectioncolor, size: 1em, weight: "bold")[#it.body]
  ]
  show raw.where(block: true): it => codeblock(it)
  show raw.where(block: false): it => box(
    fill: codebg,
    inset: (x: 3pt, y: 1.5pt),
    radius: 2pt,
  )[#text(size: 0.85em, font: "DejaVu Sans Mono")[#it]]
  set table(stroke: 0.5pt + rgb("#b9c4d0"), inset: 5pt)
  doc
}
