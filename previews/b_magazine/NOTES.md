# Direction B — Dark Magazine · 暗夜杂志

静态 HTML 预览，单文件自包含，用于 Flutter Todo 改版方向评审。

## 文件

- `index.html` — 全部视图、样式、交互（2364 行，76 KB）
- 外部依赖（CDN）：Google Fonts（Noto Serif SC / Noto Sans SC / Playfair Display）+ Material Symbols + picsum.photos 图片
- 运行：在浏览器直接打开 `index.html`；推荐桌面 1440+ 宽度欣赏 Wishes 版面

## 五个视图（顶部页签切换）

1. 要做的 · Tasks — MD3 暗色手机框 + 右侧说明。7 条真实任务，涵盖今日/逾期/本周/重复/已完成五种状态；右侧有数据卡 + 过渡到 Wishes 的入口。
2. 想做的 · Wishes（主角） — 全屏 hero（巨型衬线标题 + 呼吸辉光）+ 三个章节拉页式分节（想学/想去/想做）+ 17 件愿望，刻意混合三种密度：
   - 1 件 full-bleed hero（冰岛极光 720px 高 + 72px 大标）
   - 4 件半宽图文 feature（古琴 / 小津 / 胶片相机 / 李白长文）
   - 6 件半宽 medium 纯文字（京都 / 茶马古道 / 可颂 / 红烧肉 / 阳台茶室 / LLM 输入法长文）
   - 6 件小号装饰纯文字（咖啡 / 人类简史 / 毛笔字 / 新疆 / 青藏铁路 / 安昌古镇 等）
3. 添加 · New — 顶部两个路径卡片（MD3 / Magazine 双语言视觉对比），下方对应的两个表单；心愿表单做成"皮革日记本"风格，只有大字衬线输入和四个小标签。
4. 做过了 · Collection — 年度总结式合集，顶部数据条（19 件 · 7 次旅行 · 4 本书 · 8 个技能），2025（11 条）+ 2024（8 条）罗马数字镂空大年份 + 时间线条目，每条有反思文字。
5. 流转 · Flow — 双向流转演示。上半 wish→task（前后态 + 升级 sheet），下半 task→wish（前后态 + 非羞辱的 demote 卡片）。

## 美学核心决策

- 调色板：ink #0a0a0a · warm paper #F4EEE0 · amber #C8A05A / #E4B261 · burgundy #6B2B2B（非常克制）
- 字体角色：Noto Serif SC 挑大梁（所有心愿标题）· Playfair Display 斜体用于副题 / 属性 / 英文分节 · Noto Sans SC 只用于任务侧 MD3 和 small-caps 标签
- 字号：hero 最大 180px（clamp），feature 44px，mid 52px，text 30px，small 24px — 刻意制造编辑差异
- picsum 种子图：aurora-iceland / guqin-strings / ozu-tatami / film-camera-desk —— 按主题选种子，preserve ratio 用 object-fit:cover 但给暗化滤镜 brightness(0.55~0.75) 保持阅读
- 动效：reveal on scroll（IntersectionObserver）+ hero 背景扫描线 12s 呼吸 + scroll cue 2.4s 摆动 + hover 上 amber 辉光 + image 1.4s slow zoom
- 任务侧与心愿侧的视觉隔离做到极致：MD3 purple primary + 胶囊 chip ↔ amber 实线下划线 + 斜体 action link，两个视觉语言同页并存。

## 交互

- 顶部页签切换（JS 切 .active）
- 任务勾选可点击 toggle
- ADD 视图两个路径卡片切换对应表单
- MD3 chip 组内单选
- 心愿分类 chip 单选
- 所有带 `data-goto` 的链接都能跳到对应视图（Tasks → Wishes、Wishes → Collection 等）
- reveal 滚动动画 + 视图切换时重新触发首屏 reveal

## 与产品决策的对应

- 任务 / 心愿分页 → 顶部主导航一级分区
- 心愿无时间 → Wishes 列表无日期 chip、无铃铛；只有"加入 X 天"斜体小字
- 双向流转 → View 5 两个 block 都做了 before/after
- 逾期任务降级非羞辱 → demote-card 文案："没关系。它不是失败，只是此刻不是它的时间。"
- 完成的心愿 = 合集，不是坟场 → Collection 顶部"过去一年做了 19 件自己想做的事"，罗马数字年份有仪式感

## 文件大小

- index.html：76 707 B（76 KB，2364 行）
- NOTES.md：本文件

## 可能的下一步

- 移动端 Wishes 视图的垂直节奏还可以再打磨（现在直接 1 列堆叠，可以给 hero-card 做 portrait 版本）
- feature 卡的图片 lazy-load 在慢网下会有短暂空白，picsum 本身无法控制
- 如要做成 Flutter 实现：磁力吸附滚动 + parallax hero 需要自定义 ScrollView，字体包要内置避免首次加载闪烁
