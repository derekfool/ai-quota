# 系统设计

## 组件

- `QuotaCore`：纯 Foundation 数据模型和解析器，可独立测试。Codex 优先选择名为 `codex` 的额度池，使用服务器返回的窗口长度和重置时间。Cursor 解析 `individualUsage.plan.autoPercentUsed` 和 `apiPercentUsed`，失败时不猜测。保留页面文字解析器作为早期格式的回归保护。
- `CodexClient`：本机子进程的 JSONL 请求/响应；初始化后只调用额度读取。20 秒超时，连接断开后下一次刷新重建。退出时结束自有子进程，不影响已运行的 Codex App。
- `CursorClient`：使用默认持久化 WKWebView 数据存储登录 Cursor；保持 `https://cursor.com` 页面上下文，通过同源 `fetch` GET `/api/usage-summary`，`credentials: same-origin`、禁用响应缓存、禁止重定向、8 秒网络超时。HTTP-only Cookie 不离开 WebKit。页面连接阶段最多等待 20 秒，真实认证跳转或 401 才报告登录失效；403、429 和数据缺失分别处理。
- `QuotaStore`：单一状态源，平台独立刷新、避免重叠请求；缓存成功快照。`RefreshSchedule` 为每个平台单独记录下次刷新和关注截止时间，普通间隔 60 秒，关注间隔 10 秒。关注不持久化，截止时恢复普通间隔；慢请求跳过该次时隙，唤醒不补发积压请求。超过 150 秒、Codex 重置时间已到或请求失败均标记过期。
- `AppDelegate` / `DashboardView`：NSStatusItem + NSPopover，NSPanel + SwiftUI；共享 Store。位置和显示/置顶偏好保存在 UserDefaults。`DashboardContainer` 以可用屏幕为上限提供滚动视口，菜单弹窗使用状态项所在屏幕而非主屏，`WindowBounds` 限制窗口实际边界。正常退出不会把可见状态误记成隐藏；手动重新打开可恢复窗口。

## 不变量

- 剩余 = clamp(100 − 已用, 0…100)。缺失或异常数据不能被当成完整额度。
- 失败不清空最近成功数据，也不更新成功时间；缓存不能冒充最新请求结果。
- Codex 与 Cursor 的独立读取失败不会阻止另一方刷新。
- Cursor 重置时间来自响应中的 ISO 8601 账期结束时间，缺失或无效时不猜测。
- 不使用 API Key 余额替代 ChatGPT 订阅额度，不触发模型推理。
- 不导出、复制或记录浏览器凭据；只解析登录后的可见额度文本。

## 已批准实现计划

1. 创建独立 SwiftUI/AppKit 项目及额度数据模型。
2. 接入 Codex 官方 App Server 与 Cursor 官方页面读取。
3. 实现菜单栏、悬浮窗及共享刷新状态。
4. 验证百分比计算、解析失败、缓存过期、连接失败恢复与窗口行为，生成可运行 `.app`。

## 外部依据

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)：本地 JSONL 协议、初始化、额度读取与字段。
- [Cursor 用量说明](https://prod.cursor.com/help/models-and-usage/usage-limits)：独立额度池及 Spending 页面。
- 页面适配依据为 Cursor Models / Other Models 两个区段及重置日期字段；回归样例使用合成数值，不记录个人用量或账期。

限制：Cursor 网页用量汇总接口属于兼容性适配，并非官方公开承诺的个人 API。本应用不导入其他浏览器或 Cursor 编辑器的凭据，也不捆绑分发 Codex CLI。

## 2026-09-07 增量更新

按用户请求修复弹窗越界，加入独立一分钟密切关注，菜单栏展示四项额度，并修复 Cursor 误报登录问题。

观察到：登录窗口打开时能显示真实额度，隐藏后重载整页会间歇缺少额度内容；旧代码将其误报为“请登录”。改为读取 DOM 文本节点仍未解决后台页面初始化问题。最终改用同一 WebKit 登录环境的同源用量汇总请求，避免依赖 React 页面渲染，也不需要复制 Cookie。

接口和字段的兼容性依据：[CodexBar Cursor 适配说明](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md)、[CursorStatusProbe 实现](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift)。这是第三方开源实现提供的兼容性线索，不能视为 Cursor 官方 API 承诺；本地真实账号验证见 verification.md。

新文件 `RefreshSchedule.swift` 与 `WindowBounds.swift` 将有明确时间/几何边界的逻辑独立出来供回归测试；`DashboardContainer.swift` 负责两个窗口共享的滚动和高度限制。

## Quota change feedback (2026-09-07)

`QuotaChangeTracker` compares consecutive successful snapshots per provider by window ID and title. It compares the displayed rounded remaining percentages, preserving direction. New/missing/replaced windows establish baselines. The first successful live fetch and successful fetches after more than 150 seconds are silent; cached startup data is never fed into the tracker. Multiple changed windows in a response form one event, with the largest absolute delta determining intensity (negative wins an equal-magnitude tie).

Each event has a unique ID and short expiry (1.8/2.8/4 seconds). `QuotaStore` publishes it once to both dashboards and a menu-bar event stream; successful fetch/error/cache behavior and polling schedules remain unchanged. View-local timeline rendering provides a fading outline, signed delta badge, ripple and particles at the higher levels. It never resizes the window or changes quota data. Reduce Motion removes spatial motion and numeric/progress animation.

`QuotaFeedback` is the single sound owner. It coalesces completions within 250 ms to the strongest cue; both dashboard views cannot double-play audio. It uses six original, locally synthesized major-pentatonic chimes (two directions × three intensity levels), and stops a previous sound before playing another. The mute preference is persisted in UserDefaults; muting cancels pending and current audio. Preview events are labelled and do not touch snapshots, polling cadence, cache, or change baselines.

New files separate pure change detection (`QuotaChange.swift`, with regression tests), audio ownership (`QuotaFeedback.swift`), and visual effects (`QuotaChangeEffect.swift`). No data-source, authentication, or window-geometry changes are needed for this feature.

## 菜单可用性与关注时长

三档效果预览直接放在更多菜单第一层，消除二级菜单横向移动的选择问题。关注时长同样使用第一层选项，支持 1、5、10、30 分钟，UserDefaults 记住选择，无有效偏好时默认 10 分钟。每次启动将所选分钟数传入 RefreshSchedule 并固定本次截止时间；修改偏好不影响已经运行的关注。两个平台仍独立启动/停止，每 10 秒刷新，截止后恢复每分钟刷新。卡片显示配置时长，运行时显示分秒倒计时。

## 原创提示旋律

QuotaChime 合成 44.1 kHz、16 位单声道 WAV：小变化两音、中变化三音、大变化五音，增加上行、减少下行。采用 C 大调五声音阶、柔和起音、快速衰减泛音及淡出；随强度增加旋律长度和峰值，全部低于削波电平。QuotaFeedback 启动时缓存六个 NSSound，复用时从头播放，保留合并、打断、静音逻辑。不增加网络或外部音频依赖。

## 可选音色与三点门槛

变化强度使用绝对百分点：1–2 为 small，3–19 为 large，20+ 为 major，动画与音效共用。保留六种经典钟琴合成，新增第三版已确认的三个 WAV 作为 SwiftPM QuotaCore 资源；build.sh 将资源包复制到 App 的 Contents/Resources。QuotaSoundTheme 优先读取安装资源包，开发/测试使用 Bundle.module。菜单直接选择两套音色并保存 UserDefaults，未选择时默认 Handpan 合奏，切换时取消待播放及当前声音。新版大幅恢复音频仅用于正向至少 20 点，负向大变化使用中档音频；视觉强度仍为 major。其他轮询、认证与静音规则保持不变。

## 2026-09-10 Claude 与折叠卡片

增量计划：新增 ClaudeClient/ClaudeQuota 解析及回归测试，将第三份状态接入已有独立调度、缓存和变化检测；ProviderCard 标题作为可访问的展开按钮，折叠状态由 Store 持久化。保留已有 Codex/Cursor 客户端实现，不重构它们的认证路径。

ClaudeClient 使用独立 WKWebView 实例和 App 的持久化 WebKit 存储，在 claude.ai/settings/usage 登录；同源读取 /api/organizations，然后 /api/organizations/{uuid}/usage，12 秒请求超时，不读取或导出 Cookie。组织列表只保留可聊天工作区的名称/ID；唯一工作区自动选择，多个需明确选择。切换工作区清空 Claude 缓存与变化基线，不影响其他提供商。401 提示登录，403 提示验证或拒绝，429 提示限流，失败保留旧额度。

接口兼容性依据：[CodexBar Claude provider](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)。该项目是其自身接口适配实现的主要来源，不代表 Anthropic 保证稳定。订阅额度范围依据：[Claude usage limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)。

折叠只影响详细视图，摘要/错误和正在关注的停止按钮保留；三个独立偏好共享给两个窗口。Store 的每秒更新继续触发现有尺寸测量与屏幕边界限制。

窗口测量修正：折叠实测发现 NSHostingView.fittingSize 在收缩时保留旧高度。现由 DashboardViewport 发布实际内容高度，AppKit 使用受屏幕限制的 preferredSize；内容测量变化触发两个窗口重新适配，避免折叠留下空白。

## Claude Google 登录白屏修复

实测白屏 URL 为 accounts.google.com/gsi/transform。旧 createWebViewWith 把新窗口请求加载到主视图并返回 nil，丢失 OAuth 所需的弹窗/opener 通信。改为用 WebKit 传入的配置创建独立 WKWebView 并返回，保留 JavaScript 弹窗及 postMessage 上下文；webViewDidClose 仅关闭对应弹窗。弹窗存在时暂停用量请求，手动关闭或登录完成后正常恢复；重新连接会重载 Claude 用量页以离开旧回跳白屏。不导入 Chrome 凭据，不关闭 WebKit 安全检查。

平台依据：[WKUIDelegate createWebViewWith](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:))、[webViewDidClose](https://developer.apple.com/documentation/webkit/wkuidelegate/webviewdidclose(_:))。

## 精确高度与排序

高度偏好键默认值改为零，避免默认测量值干扰收缩；文档视图按固定宽度测量自然高度，根视图忽略隐藏标题栏安全区。fullSizeContentView 的窗口按内容高度直接设置 frame，避免 setContentSize 再加一次隐藏标题栏高度。屏幕边界与超高滚动限制保留。

ProviderOrder 规范化持久化顺序并提供相邻移动，忽略未知 ID、去重并补回缺失提供商；卡片以 provider ID 作为稳定身份。临时排序模式提供上移/下移及完成按钮，菜单栏摘要也按相同顺序生成。各家的状态仍独立保存，排序不重置状态。

## Gemini 与历史预测增量（2026-09-11）

### 实施范围与保留行为

用户确认 Gemini 网页/App 的个人 Google AI 订阅，并要求每项额度有 24 小时趋势线。实施范围为新增 Gemini 只读适配与解析；向 QuotaWindow 追加可选 cycleStartedAt；新增独立本地历史文件、纯统计与预测；以 MetricView 展示每个指标。保留现有三个客户端的认证、请求路径、每分钟/关注调度、错误缓存、音效与窗口几何。旧 JSON 缺少新增可选字段时仍正常解码。界面预览以演示数据展示紧凑布局。

### Gemini 来源与约束

Google 官方[个人订阅额度说明](https://support.google.com/gemini/answer/16275805?hl=en)描述 5 小时和每周额度。实际观察官方 /usage 页，并核对其公开前端 GetUsageInfo 解析：只读 RPC jSf9Qc 的数组第二项为额度池；池第二字段为已用比例（乘 100），第三字段 1/2 分别对应当前/每周；第四字段内包含 Unix 秒与纳秒重置时间。第一字段不是周期长度，不据此推算。忽略无法表示为百分比的其他额度类型；未知结构、重复池、非法数值失败，不补满额。

GeminiClient 在主框架 documentStart 安装响应观察器，仅匹配 gemini.google.com 的 /_/BardChatUi/data/batchexecute 且 rpcids 包含 jSf9Qc；只提取对应 wrb.fr 的响应数据与接收时间。不读取 Cookie、请求体、聊天响应或认证 token。官方网页自行执行认证和请求。普通刷新重新载入官方用量页，要求本次请求之后的新响应；可见登录窗口不被自动重载，弹窗保留 WebKit 配置与 opener。失败保留旧快照且不增加历史。该网页协议属于兼容性适配，不是公开承诺稳定的 API。

### 周期与统计

Codex 使用返回的窗口分钟数与 reset；Claude/Gemini 当前周期为 5 小时、周周期为 7 天。Cursor 只使用响应 billingCycleStart，缺失时不猜测月份长度。未来周期起点、未开始/到期周期都拒绝预测。计算使用快照时间而非不断增长的本地当前时间作为已用值的采样基准，避免失败期间预测自行改善。

QuotaHistory 按提供商、指标 ID 和标题隔离。只记录成功的新样本；相同/倒退时间不重复记录，首次快照仅建立基线。保留最近 48 小时，每序列上限 18000 样本；quota-history.json 与原 quota-cache.json 分离，原子写入，内容不含凭据。未知版本或损坏文件原样保留并停写，内存历史仍可工作，界面提示。Claude 显式切换工作区时清除其历史，避免混算。其他提供商没有统一账号标识协议，当前版本的历史针对持续连接的单个账号；使用窗口身份变化切断跨池趋势。

连续相同周期累计正向已用差值；恢复/修正不当作负消耗。跨已知重置计入新周期已用，缺失旧周期尾部标为部分观测；离线同周期差值可统计但图表断线。24h 边界只对不超过150秒且相同周期的相邻点线性估计。曲线不补画离线、重置或修正段。所有统计统一使用百分点。

预测为累计已用/周期已过秒数，再按剩余推算耗尽日期。紧急度为预计剩余可用时长/样本距离重置时长，绿/黄/浅红/深红锚点依次为1.25/1/.75/.35，色值连续插值。过期数据中止预测并使用中性色，初期历史不足不阻止具有完整周期信息的预测。

### 验证计划

解析验证比例单位、周期类型、精确重置、缺失/异常字段；历史验证冷启动、24h边界、重置、修正、离线、重复样本、存储与账号清理；预测验证均速、零消耗、未知周期、陈旧数据及颜色边界连续性。运行完整 XCTest、Release 构建及签名检查，再对真实 Gemini 登录/隐藏刷新与展开折叠窗口进行手动验收。

## 紧凑面板批准实施（2026-09-11）

本节更新之前的独立关注、固定360pt、常驻24h图表和48h历史限制。范围为QuotaStore、MetricView、DashboardView、窗口宽度、QuotaHistory和QuotaChange展示寿命；不改各提供商认证/解析、声音资源、缓存格式。

实施计划已由用户确认的mock和颜色/预测规则授权：先扩展纯历史/预测与回归测试，再接入全局关注及紧凑指标，最后构建并检查本机窗口和操作。四份RefreshSchedule仍保护各自慢请求，但由同一个toggleWatching使用同一时间启动/停止。刷新、失败和唤醒不改变全局截止时间。

QuotaHistory保持版本1可读格式，保留当前周期或48h二者较长范围；48h外按15分钟选点，序列硬上限40000。UsageHistorySummary分别提供24h统计、当前周期近24h分段和周期趋势样本。预测增加usesRecentHistory说明来源；周期前300秒/无起点时，可用至少60秒历史的消耗/记录跨度估算，否则沿用有效周期均速。reset始终必需；过期停止预测。统计缺口和不完整覆盖通过星号、帮助及展开说明明确显示。

QuotaChange的短动画时长保持原三档，标识寿命改为30秒。Store列出所有提供商当前事件内的指标变化，避免同时变化仅看到音效最强的一项。行内显示变化标签和背景/边条，卡片保持短脉冲。音效仍只由Store播放一次。

验证：核心测试覆盖跨重置消耗与分段、超过48h周期保存及序列化、历史回退与恢复周期均速；现有解析/调度/颜色/缓存测试继续运行。真实UI验证默认高度、图表伸缩、关注与预览，不能用合成测试替代账号或长期运行证据。


## 通知不改变窗口高度（2026-09-11）

本次范围：移除DashboardView顶部通知；MetricView的事件文本固定宽高并替换24h文本，不新增行，增强行背景及色条；进度条调换为剩余在左。QuotaStore在事件发生时冻结提供商/指标/变化前后值，保存本次运行最近30条，避免读取后续快照重算旧通知；底部固定图标打开独立popover，不参与Dashboard高度测量。折叠、排序、数据读取、预测与窗口测量机制不变。

新增FocusSound.swift独立合成两种短机械音，单声道44.1kHz/16位PCM，峰值0.65；开启3次间隔85ms滴答，关闭双段落锁声。QuotaFeedback独立持有focusSound，不取消额度提示的排队/播放；全局静音停止两路。仅toggleWatching手动操作触发，自动到期不触发。FocusSoundTests验证PCM边界、短时长和三次可区分脉冲；人工听感仍需实际试听。


## 确认音效与刷新颜色闪烁修复

FocusSound改为加载两个批准的WAV资源（开启v6、关闭v5），不重新合成或归一化；NSSound音量1保持文件内已降低的振幅。新增资源focus-on.wav与focus-off.wav，跟随现有SwiftPM资源包分发；缺资源保持静音，不退回未批准音效。

问题根因：Store.now每秒更新，新快照updatedAt在异步完成时通常更晚，QuotaForecast的sampledAt<=now约束在下一次tick前拒绝样本，使风险色短暂变灰。四家成功路径在发布snapshot之前设置now=Date()；客户端updatedAt为本机时间，因此保持时间顺序。保留模型对未来时间、过期和真实失败的拒绝，不掩盖错误。


## 白色未知风险与低音调开启声（2026-09-12）

按用户确认，开启资源替换为v8试听原文件，保持150ms间隔与低音量，关闭声不变。无法生成有效预测时剩余段使用白色，包括周期信息缺失和数据过期；保留错误/预测不可用文字，不把白色解读为充足。已用段颜色与有效预测的风险渐变不变。


## 开启声定稿v9（2026-09-12）

采用用户选定v9，PCM振幅乘0.7（约−3.1dB），不改变音高和150ms间隔；关闭音效和音效开关不变。

### Reset-marker deduplication

Trend reset markers require an observed cycle boundary with prior consumption. Rolling reset deadlines on unused quotas do not create reset markers; metadata corrections alone are insufficient. Marker detection is separate from historical segment continuity. Persisted samples, schema, and consumption calculations remain unchanged.

### Outer glass and hide-button target

The dashboard uses an active behind-window HUD material with a transparent floating panel. Provider cards retain their previous composited dark color as an opaque fill, so only the outer layer shows glass. The hide button has a 32pt square rectangular hit target, including empty space around its minus glyph.

Long-cycle forecasts use the existing cross-cycle rolling 24h consumption summary during their first 24h, then return to the cycle mean. Cycles of five hours or less retain the five-minute warmup. Partial history and missing reset handling remain unchanged.

### Unified glass cards

Provider cards now use a 62% dark translucent fill, a subtle top-to-bottom white border, and a soft shadow. An 18% neutral dark veil over the outer material softens desktop colors. Layout, spacing, risk colors, and hit targets remain unchanged. This supersedes the opaque card fill above.

### 密切关注玻璃背景

按钮及辅助功能名称统一为“密切关注”。普通模式保留完整 HUD 毛玻璃与 18% 深色遮罩；关注时在其上叠加 94% 不透明的冷烟灰渐变及轻微反光边缘，使外层与深色卡片区分，同时抑制桌面细节干扰。

背景由共享 Store 的关注状态驱动：开启用 0.8 秒渐变，手动关闭或到期用 1.6 秒恢复。Reduce Motion 下取消动画。卡片保持 62% 深色填充；额度颜色、布局、刷新调度与音效不变。

## Chinese and English UI

AppLanguage resolves a saved appLanguage preference before system language. Dashboard language changes invalidate SwiftUI presentation and refresh native status/login labels. Explicit bilingual UI strings handle interpolation; a display-only catalog translates canonical stored pool names and app-generated errors. Persisted window titles, IDs, history schema, and parser behavior do not change. Recent-change entries retain both languages in memory so switching also updates old entries. Locale-aware dates use the selected language. No credentials or provider requests are changed by language selection.

Language choices are direct items in More, beneath a disabled language heading. No hover submenu is used, avoiding menu dismissal while moving the pointer. Preference persistence and immediate switching are unchanged.

### Pinning and Spaces

Pinning updates panel floating status, window level, and Space membership together. Pinned panels use floating level and all-Spaces/full-screen auxiliary behavior. Unpinned panels use normal level and managed Space behavior, so they move with their desktop during Mission Control transitions instead of remaining over the animation. Explicit show/reopen can still bring the window forward; background quota updates do not reorder it.

Deferring screen updates until flush did not resolve the user-observed black flash during pinned Space transitions and was removed. Live behind-window material transitions remain unresolved; do not claim the issue fixed from build checks.

### Close Watch mascot

Each new Close Watch session chooses uniformly among sad, blank, lying, and angry cat poses. The shared store holds that choice for both dashboard surfaces; refreshes do not reselect it. The mascot is decorative, hidden from accessibility, ignores pointer input, and never contributes to layout measurement.

The first provider card publishes its actual bounds. A Canvas overlay clips to the dashboard rounded outline and subtracts the first card for occlusion. Standing poses cover AI QUOTA and occupy the left gutter, using the approved nose-to-belly axis rotated by -0.32 radians for a 0.30-second entry and 0.22-second exit. Both resting poses overlap the card top by 8 points; on stop or expiry, it switches behind the card, waits 0.06 seconds, then retracts over 0.22 seconds. Eye-only blink frames preserve body registration. The lying cat also bends its outer right ear twice after settling, then rests between flicks (8.7-second cadence). A localized strip deformation leaves the cheek and paws fixed; both eye frames share it. The angry pose uses a 92-point width so its upright head fits the header. Its upper 40% bends both ears inward with up to 18% of the image width in tip displacement, tapering to zero above the eyes. It shares the resting entry/occlusion and ear timing, while the original lying animation is unchanged. Exit suppresses ear motion. Reduce Motion shows a static pose and hides without translation, blinking, or ear motion. A cancelled exit task cannot hide a restarted session. Reordering temporarily hides the decoration to preserve the reorder controls; the chosen pose remains unchanged.

No polling, sound, credential, persistence, or quota calculation behavior changes. Artwork is bundled locally without new network or package dependencies.
