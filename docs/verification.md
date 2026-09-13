# 验证记录

2026-09-07，macOS 26.6.2 / Xcode 26.6 / Apple Silicon。

## 自动验证

27 项 XCTest 全部通过：
- Codex 额度池选择、动态窗口及重置时间；拒绝空数据；零用量及超额边界。
- Cursor 旧页面区段解析、缺失区段拒绝；用量汇总的两类百分比映射、低于 1% 的单位处理、账期日期解析、错误/缺失数据拒绝。
- 缓存序列化和过期规则。
- 关注启动即刷新、每 10 秒刷新、默认 10 分钟及配置时长截止恢复普通间隔、手动停止/重新开启、两家独立、慢请求跳过、睡眠后不补发积压请求。
- 小屏幕下过大窗口、位于负坐标的副屏、正常窗口不移动。
- 额度变化首次采样/未变/不可见小数保持安静；5 和 20 个百分点强度边界；额度恢复；过期数据重建基线；窗口身份变化；多窗口合并去重及两家独立基线。

Release 编译、App Bundle 生成、临时代码签名验证及 Info.plist 校验通过。

## 实际运行检查

- 独立 Codex JSONL 及交付 App 的读取检查成功，不创建模型任务。
- 新版 App 的悬浮窗实际显示关注开关与倒计时，长内容可滚动至底部。
- Codex 和 Cursor 可同时关注；手动停止 Codex 后，Cursor 仍保持关注。
- 第一次关注测试中，两家都在截止后自动恢复关闭状态。
- Cursor 登录后的实际网页显示有效额度。原页面读取在隐藏窗口时失败，切换为同一 WebKit 登录环境内的 `/api/usage-summary` 请求后，登录窗口保持关闭仍成功获取两类额度和账期结束时间。
- Cursor 首次后台成功时间 08:01:39；关注期间继续刷新到 08:02:36、08:03:18 等新时间，状态正常，无需重新登录。
- 手动重新打开 App 可恢复已隐藏的悬浮窗。修正了退出时将可见偏好误存为隐藏的问题。
- 已安装并启动变化反馈版本；悬浮窗实际预览 +20 点的绿色粒子与扩散圈，以及 −5 点的琥珀色反馈。预览期间真实额度不变，效果结束后恢复正常状态。
- 更多操作菜单实际包含音效开关和三档预览。音效文件存在，播放代码编译通过；工具未提供听觉验证，实际听感仍需用户通过预览确认。

## 验证边界

- 解锁后已于当日 17:42 左右退出旧进程并重启最终版本，悬浮窗恢复且两家成功刷新。再次核对 Codex 主额度接口：仅有 10080 分钟周窗口，未返回主额度 5 小时窗口；菜单栏对应缺失项显示“—”，不借用 Spark 独立额度。
- 菜单栏弹窗的尺寸限制、滚动视口及当前屏幕定位已实现，窗口边界算法已有小屏/多屏回归测试；尚未通过工具直接取得用户点开的菜单栏弹窗截图。
- 系统级断网/联网、睡眠/唤醒、多显示器热插拔尚未进行真实设备场景实测；超时、失败保留旧数据、定时重试及唤醒刷新机制保留，调度/缓存边界已有测试。
- Cursor 网页用量接口并非官方公开承诺的个人 API，未来接口变化仍可能需要适配。

## 变更范围与文件

没有修改 pushup 项目。修改范围包括窗口布局、刷新调度、菜单栏四项额度、Cursor 后台数据读取及相关产品/设计说明。

新增额度变化反馈：`QuotaChange.swift` 与测试隔离变化检测规则，`QuotaFeedback.swift` 集中合并和播放声音，`QuotaChangeEffect.swift` 提供强度分级和减少动态效果支持。既有数据读取、登录、刷新节奏与窗口布局保持不变。变化反馈实现无额外范围扩展。

新增 `RefreshSchedule.swift`、`WindowBounds.swift` 和对应测试，将定时及屏幕边界逻辑独立验证；新增 `DashboardContainer.swift`，让菜单栏和悬浮窗共享受屏幕尺寸限制的滚动视口。

经运行证据调整 Cursor 接入实现：从页面文字读取改为同一已登录 WebKit 环境的同源用量请求。保留既有登录数据，不读取密码，不导入其他应用的凭据。

## 菜单与关注时长更新验证

24 项测试通过，Release 构建和安装后的签名验证通过。实际从更多菜单直接点击 +20 点预览，截图确认动画触发。实际启动 Codex 显示 10:00，改选 5 分钟后 Codex 原倒计时继续，随后启动 Cursor 显示 5:00；两家均可手动停止。最终菜单恢复并选中 10 分钟。配置时长自动到期通过模拟时间测试验证，未等待完整十分钟实测。无新文件，无数据源或认证修改。

## 原创音效更新验证

25 项测试通过；六种波形检查非零内容、方向差异、柔和首尾、无削波及强度递增。六种 WAV 均由 NSSound 成功解码，时长分别为约 1.01、1.19、1.75 秒。Release 构建通过并已安装启动，菜单预览入口可触发。工具无法评价实际听感，用户可从菜单试听。新增 QuotaChime.swift 隔离本地合成和 WAV 编码，QuotaChimeTests.swift 保护音频边界；保持既有合并、静音和额度读取行为。

## 2026-09-08 双音色与三点门槛

27 项测试通过，覆盖正负 2/3/19/20 点边界、恢复庆祝音只匹配正向 20 点、三个资源的系统音频解码。安装包签名验证通过，内置 WAV 的 SHA-256 与批准第三版试听文件逐一一致。实际菜单显示两套音色，可切换到经典钟琴再回到 Handpan 合奏，明显减少预览为 −3 点。新增 QuotaSoundTheme.swift、三份批准的 WAV 资源和对应测试，以保留原音色并稳定打包新音色；未改变数据读取和轮询。

## 2026-09-10 Claude 与三家独立折叠

31 项 XCTest 通过，新增 Claude 主窗口及专项额度解析、缺失窗口不补值、异常数据拒绝与第三家独立调度检查。同源请求脚本的单工作区、多工作区、明确选择及 401/403/429 分支通过模拟请求检查。Release 编译成功。

初次安装已实测三张卡片独立折叠，显示真实 Codex/Cursor 摘要并保留 Claude 错误提示。实测发现折叠后窗口空白，已将窗口尺寸改为实际内容高度；已实测折叠后窗口收缩；重启保留三张卡片的折叠偏好，折叠时关注继续运行且可直接停止。Claude 官方登录页已打开，真实账号数据读取等待登录完成。

新增 ClaudeClient.swift、ClaudeQuota.swift、ClaudeQuotaTests.swift；已有 Codex/Cursor 客户端未修改。缓存、音效、关注调度增加第三份状态。窗口测量修正属于折叠功能实测发现的问题，未改变原有屏幕边界规则。

## Claude Google 登录回调修复（2026-09-10）

旧版白屏确认为 Google gsi/transform 页面。修正 WKWebView 弹窗创建与关闭后，实测 Google 独立账号选择窗口正常显示，随后成功回到官方用量页。关闭登录窗口后，小组件成功显示实际额度，与官方页一致；再次手动刷新也成功。验证文档不记录本次账号的订阅等级或用量数值。31 项测试、Release 编译和安装签名验证通过。仅修改 ClaudeClient 的弹窗生命周期和重新连接行为，未导入其他浏览器凭据。

## 自适应高度与卡片排序（2026-09-10）

33 项 XCTest 通过，Release 构建和安装签名验证通过。实际悬浮窗验证了全部展开、逐张折叠、全部折叠与重新展开，窗口随内容增减且底部无多余留白。实际通过更多菜单进入排序模式，将 Claude 上移再下移，卡片顺序立即更新、折叠状态保留；完成排序后控件收起且窗口同步缩小。测试后恢复原始顺序和全部展开。菜单栏弹窗共享同一布局实现，但本次未直接取得其截图。

新增 ProviderOrder.swift 及对应测试，用于持久化顺序规范化、去重补全和相邻移动；未修改三家认证、用量数据源、关注时长或音效。

## Gemini、24 小时历史与周期预测（2026-09-11）

49 项 XCTest 通过，Release 构建及签名验证通过。新增 Gemini 网页响应解析和 JavaScriptCore 观察器测试，确认比例单位、精确重置、错误/无关流量过滤以及原请求仍执行。新增历史与预测测试覆盖跨重置、恢复修正、离线、冷启动、24h边界插值、持久化、旧快照兼容、周期平均速度及色彩阈值连续性。另验证超过24小时的旧记录从显示范围退出。

实测新版在 App 内复用已有 Google 登录状态，成功获取 Gemini 当前及每周额度，与 App 内打开的官方用量页一致。关闭该页后继续刷新，密切关注期间连续取得多个约10秒间隔的新响应，手动停止正常。未执行完全登出后重新输入凭据的登录流程，不将真实账号用量或凭据写入仓库。

四家历史序列均成功持久化；重启前记录的全部样本在重启后仍存在，且所有序列继续追加新样本。Cursor 实际响应具备周期起点，两个指标可分别计算预测并呈现不同紧急程度。Claude 当前无重置时间的5小时窗口明确不预测，其余具有周期元数据的窗口正常计算。实际验证全部展开时限制屏幕内并可滚动、部分折叠及四家全部折叠时窗口贴合内容。最后恢复原有三家展开状态、用户排序、置顶和关注时长；Gemini 保持展开，关注均已停止。

新增 GeminiClient.swift、GeminiQuota.swift、GeminiWebCapture.swift 隔离第四家接入；QuotaHistory.swift 提供持久化样本、24h统计、预测和紧急度；MetricView.swift 集中指标布局与曲线；新增三组对应测试。现有 Codex/Cursor/Claude 认证客户端未修改，保留原音效和窗口尺寸逻辑。实测期间发现无障碍百分比截断与视觉四舍五入不一致，已统一；历史统计每分钟重算，确保即使刷新失败，24h窗口也继续移动。

完整24小时曲线、跨实际周期重置和长时间系统睡眠尚未等待实测；对应数据与时间边界已通过模拟测试。菜单栏弹窗共享布局，但本轮未直接取得其截图。本次代码与应用包已更新到本机，尚未创建 Git 提交。


## 紧凑面板与风险分段（2026-09-11）

- 自动测试：完整53项XCTest，包含周期历史超过48h后保留/序列化、跨周期24h统计和当前周期分段分离、近24h均速回退/恢复周期均速、同步关注截止与忙请求保护；Release构建及签名检查。
- 本机观察：新版已启动；四家卡片全部展开、七项实际返回指标，在约416×768pt窗口内完整显示。剩余段风险色、低亮度已用段、余量下方24h小字可见。点击Codex周进度条成功展开历史/预测并自动增高。
- 发现并修正：图表横轴起点标签改为与实际周期绘图区间一致；增加“现在”与“预计耗尽”标记，修正后重新构建。
- 未完成实机确认：尝试收起图表/启动全局关注时电脑操作工具超时，重试仍超时，无法确认这次点击是否完成；全局关注、变化预览和最后图表标签修正尚未完成最终实机验收。进程采样显示主线程主要等待系统事件，未观察到App死锁，不能据此断定全部交互正常。
- 最后构建已替换磁盘App；当前运行实例未能通过界面重启来载入最后的标签修正。用户重新打开App后生效。未提交或推送GitHub；未将真实账号数据写入新增测试或文档。

## 稳定通知与开关机械音（2026-09-11）

- 完整55项XCTest通过，新增机械音测试覆盖时长、幅度边界、三次分离滴答和有效WAV头；Release构建通过。
- 静态布局检查：顶部通知已移除，变化文本复用余量下方112×13pt区域，最近变化按钮固定18×18pt，记录使用独立300×240pt浮层。背景高亮不参与布局。条段顺序为剩余、近24h已用、更早已用。
- 新增FocusSound.swift负责独立关注开关声；FocusSoundTests.swift提供波形回归。未修改数据源、预测、额度音色资源和窗口测量。
- 电脑操作工具本轮再次超时，未完成通知前后原生窗口尺寸对比、开关试听或浮层点击的实机验收。新版写入原App路径且签名校验通过；需要用户退出再打开载入。代码未提交/推送，保留此前Gemini与紧凑面板未提交变更。


## 确认音效与刷新闪灰修复

- 56项XCTest通过，Release构建和安装后签名验证通过。音效回归验证48kHz PCM、低幅度、开启三下逐样本相同及150ms间隔；新增预测时间边界回归，保留未来/失败样本拒绝。
- 音效资源直接复制用户批准的开启v6与关闭v5原WAV，播放器不再额外降低/归一化文件振幅。
- 本机已退出旧进程并启动最终构建。实际点击开启关注、提前关闭、手动刷新成功；“正在同步”期间截图仍保留有效条段颜色和预测，没有整体清空。Claude无有效周期的指标仍保持中性色，符合约束。截图不能证明每一帧，根因消除由时间边界回归及四家发布顺序代码检查支持。
- 测试结束关注关闭；既有账号、置顶、排序和30分钟时长偏好保留。未提交/推送GitHub。

## 开启音效v8与白色未知风险（2026-09-12）

56项测试通过，Release构建及安装签名检查通过。开启资源替换为用户确认v8，文件长度0.8秒，三次相同滴答间隔150ms，低幅度检查通过；关闭资源未改。新版已重启，实际截图确认无法预测/过期时剩余段为白色，有效预测保留原风险色。启动时Claude页面出现连接超时，旧快照保留并显示明确错误；不将白色当成数据已验证或余量充足。此更改未提交/推送。


## v9低音量开启声（2026-09-12）

采用批准v9并将PCM振幅乘0.7，关闭音效未变。56项测试通过，Release构建及安装签名验证通过；已退出旧进程并重新启动最终App。此更改未提交/推送。

### Reset-marker regression

58 tests passed, including synthetic repeated unused-deadline shifts and deadline corrections followed by an actual reset. Release build and ad-hoc signing succeeded.

### Glass, hit target, and long-cycle warmup

59 tests passed, including the long-cycle 24h boundary and unchanged five-hour forecast behavior. The outer glass UI was installed and visually inspected, with opaque provider cards. The hide button now declares a 32pt rectangular target. Clicking it set the persisted showFloating flag to false; UI inspection reopens the panel. Final Release build passed.

The subsequent translucent-card refinement also passed the Release build and signature verification. The installed app was restarted and visually inspected with translucent dark cards, subtle borders, and unchanged layout.

### 密切关注烟灰玻璃

最终版本 Release 构建、签名验证及差异格式检查通过；已安装并检查真实界面的关注状态、按钮名称与卡片层次。本次仅修改视觉背景和文案，未修改核心额度逻辑，未重复运行核心测试。

### Chinese / English support

62 tests passed, including saved-language resolution, canonical title/history preservation, dynamic window names, and app-error translation. Release build and signature check passed. Actual English dashboard, menus and expanded trend were inspected; switching to Chinese preserved the open chart, and restarting retained the saved Chinese preference. Official sign-in webpages and system-generated errors retain their own language settings. Full VoiceOver and clean-machine onboarding remain untested. Open-source readiness findings are recorded separately in open-source-readiness.md.
