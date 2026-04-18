# Direction C — Cabinet of Curiosities · 收藏匣风

一个给 Flutter todo app 的重设计预览，核心提案：把「想做的」从任务系统里分离出来，成为一个**个人博物馆**——保存未来之我的标本（specimens）。

## 核心隐喻

> 一个收藏匣（Cabinet of Curiosities），装着「我想成为的那些自己」的标本。
> 要做的 = 日历上的骨架（冷静、有截止）。
> 想做的 = 展柜里的标本（无时间压力、可反复翻阅）。
> 已完成的 = 藏品档案（不是墓园，是成就）。

## 5 个视图

1. **要做的 (Tasks)** — MD3 风格，克制。手机+桌面并列。顶部有一个通往展柜的"门"——温暖的入口卡片：「想做的 · 32 件藏品 · 上次翻阅于三周前」。
2. **想做的 (Wishes) · STAR** — `column-count` masonry 墙，20 个尺寸各异的 specimen：9 小卡（纯标签）、5 中卡（带手绘 svg sketch）、2 大字陈列牌（plaque）、4 feature 卡（带整张图片 + 引文）。每张卡带 provenance line（「想法诞生于 2024.11.03 · 来自一张朋友发来的照片」）。悬停露出两个动作：升级成任务 / 已完成 · 加入收藏。
3. **记下新的 (Add)** — 前置选择「要做的 / 想做的」。任务表单 MD3 标准。愿望表单做成**博物馆标签**视觉：虚线下划线的标题输入、金色角装饰、居中 serif、无时间字段。
4. **已完成的收藏 (Collection)** — 按年度画廊（2024 / 2025 / 2026）。每个条目有日期、标题、SPECIMEN 编号、可选的一句反思、右上角罗马数字"完成戳"。顶部统计：总数 41、按类别分布。
5. **双向流动 (Flow)** — 三个 before/after：wish→task（升级）、task→wish（放回收藏匣，有「用词测试」面板显示 4 个候选文案、钦定的是「暂时不想做？放回收藏匣」）、wish→completed（直接完成）。

## 关键设计细节

- **Provenance line**（出处行）：每一张展柜卡片都有一行斜体 Cormorant Garamond 小字，前缀 `※`。例如「想法诞生于 2025.07.18 · 某个失眠的凌晨三点」「收入展柜 2024.12.31 · 除夕夜在外婆家」。这是把愿望**物化**为标本的关键细节。
- **SPECIMEN No.**：每张卡右上角有编号（No. 003、No. 017 等），从 1 编到 042，总数与统计数字一致。
- **Small caps + 罗马数字 + 西文斜体**：MMXXIV / MMXXV / MMXXVI 做完成戳，PART ONE..FIVE 作 eyebrow，`Thing · with a deadline` 对 `Specimen · kept in the cabinet` 做副标题对比。
- **手绘 SVG 装饰**：5 处 ornament divider（粗细不一的波浪线 + 圆点），以及 4 张 medium 卡片的 sketch（古琴 / 可颂 / 红烧肉锅 / 阳台平面图 / 硬笔字），全部内联 SVG，纯色，不依赖外部资源。
- **Feature 图**：4 张整屏 feature 图也是纯内联 SVG（冰岛极光、小津榻榻米、胶片草稿、父母肖像剪影），保留 `aspect-ratio`，暗色+金色色调。
- **Light / Dark toggle**：顶部圆形按钮。亮 = 暖奶油 `#FAF7F2`（美术馆日间白墙）；暗 = 深画廊 `#1C1A17`（夜间展柜）。金色 accent 在两种模式都保留。偏好通过 localStorage 记忆。
- **非羞耻的降级**：flow 2 里有一个「用词测试」面板，把"稍后再做 / 删除任务 / 取消截止时间"都列出来并指出问题，最后选中「暂时不想做？放回收藏匣」——把 UX 决策的理由显性化。

## 字体层级

- **Noto Serif SC** — 中文主体 + 展柜标题（300/400/500）
- **Cormorant Garamond italic** — 拉丁文副标题、provenance line、完成戳、罗马数字
- **Noto Sans SC** — MD3 区域的功能文字（按钮、标签、表单）
- **Material Symbols Outlined** — 所有图标（weight 300，不填充）

## 技术实现

- 单一 `index.html`，无外部依赖（字体除外）
- Vanilla JS：tab 切换、主题切换、filter chip、任务勾选动画
- Masonry 用 `column-count: 4 / 3 / 2 / 1`（响应式）+ `break-inside: avoid`
- 无构建步骤，浏览器打开即看

## 文件

```
c_collection/
├── index.html     97 KB · 2637 行
└── NOTES.md       本文件
```

## 打开方式

```
firefox /home/mingh/todolist/previews/c_collection/index.html
```

桌面全屏（≥1400px）时 masonry 为 4 栏，视觉最接近一面真正的美术馆墙。
