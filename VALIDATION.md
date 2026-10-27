# 0.8.160 (179) — 清理桌面 — 2026-10-24

- 立品需求：一个内置快捷操作，把桌面上所有窗口最小化。新增 `FloatingAction.showDesktop`「清理桌面」（悬停提示「最小化所有窗口」，命名由立品定）（menubar.dock.rectangle），默认动作里排在「最小化」后；老用户用 `seededShowDesktopAction` 迁移一次，关掉后不再加回。
- 实现：所有 regular 应用（不含 Better Remote）经 AX 取 kAXWindows，只处理 AXStandardWindow、未最小化、非全屏的窗口，设 kAXMinimized 或按最小化按钮，单次 AX 超时 0.3s，在 WindowAXWorker 里跑；Better Remote 自己的设置等真窗口用 miniaturize，工具条与面板不动。没有可收起的窗口时提示。日志 `show-desktop minimized= failed=`。
- Cindy 适配（原 0.8.156–0.8.159，未发布）按立品要求全部移除，代码回到 0.8.155 的远程识别。
- Core 测试通过（新增 ShowDesktopActionTests 2 项）。

# 0.8.148 (166) — 应用快捷操作与应用面板修复 — 2026-10-21

- 来源：立品让 Codex 修复的若干问题（工作区未提交改动），立品已在本机测试验收并要求发布。安装的 0.8.147/165 本地版（07:48 签名）由这批改动构建（release 构建 07:47:51 晚于最后一次源码修改 07:46:27）。
- 应用面板（AppLauncher）：尺寸不再按应用数量、分区和错误状态计算，改为沿工具条停靠边与工具条等长、向桌面展开 80%（不超过可用区域），分区变化时大小稳定；去掉 scrollingColumns 等相关常量。
- 应用快捷操作浮出面板：最多 3 列（原 4 列）；点一个快捷操作后面板不再关闭，可连续点，点外面关闭。
- 设置 › 应用快捷操作：整颗按钮可拖动排序（同一应用内），点击仍打开编辑；无障碍「前移/后移」。新增 `ApplicationShortcuts.moveShortcut` 与 `OperationDragSurface`。
- 编辑快捷操作弹窗：去掉用当前 key window 高度当上限的 panelHeight（会让弹窗越开越矮），改为只受 DialogLimit 限制；新增 ShortcutEditorLayoutTests（桌面与小屏下展开/收起图标选择三次，高度恢复）。
- `swift test -Xswiftc -warnings-as-errors`：Core 357 项全部通过（应用面板旧尺寸测试换成新规则测试），App 68 项 0 失败、8 项门控跳过；WorkspaceLayoutControllerTests 一次通过。
- 正式发布（提交 718e5be）：首次构建苹果时间戳服务不可用；临时把 timestamp.apple.com 加入 Wi-Fi 代理绕过后构建成功（App、Sparkle 各组件、DMG 均含安全时间戳），绕过列表已恢复为原 18 项并 diff 一致。公证 `442ec9d2-4c3e-434f-aec5-a390b235c3ad` Accepted（issues=null），DMG 与 App 已装订，spctl 均为 Notarized Developer ID。DMG SHA-256 `33dc459b40b9f13aada16b8df5287c0b9390f3797243dee2b3ef01e8f7f2a0bb`，7484543 字节。
- Release v0.8.148 两个资产（版本名与固定名）下载后 SHA-256 一致；appcast 166 / 0.8.148 已提交下载仓库（bd38236），raw 地址内容与本地一致，EdDSA 签名校验通过；官网 /download 首次 302 到 GitHub、第二次直接返回 Better-Remote-0.8.148.dmg，SHA-256 一致。发布说明一条通用说明（README 同步）。
- 旧 0.8.147/165 本地版备份到 `~/br-tmp/old-app-br-0.8.147-165-local/`，正常退出后覆盖安装 0.8.148 / 166，安装与构建的二进制一致，`open -g` 启动后进程在运行。

# 0.8.147 (165) — 窄屏设置窗口 — 2026-10-20

- 用户反馈：电脑切到竖屏手机分辨率后，设置窗口（固定 900×720，SwiftUI 最小宽 640）比屏幕还宽，右侧内容被裁掉，只能切回电脑分辨率改设置。
- 根因：AppController 把设置窗口内容尺寸硬性锁死为 900×720（contentMin/Max 同值，不可调整），SettingsView 另有 minWidth 640 / minHeight 500，侧栏固定 160；打开时和分辨率变化时都不参考屏幕可见区域。
- 修复：新增 RemoteFitCore `SettingsWindowLayout`。桌面仍为 900×720 且位置不变；可见区域不够时缩到「可见区域减两侧各 12」，最小 360×360（屏幕更小则用整块可见区域），并整体移回屏内。打开设置时和 `didChangeScreenParametersNotification`（立即 + 0.5 秒后再一次）都重新适配；NSHostingController `sizingOptions = []`，尺寸只由窗口逻辑决定。
- 窄布局（窗口内容宽 < 560）：侧栏只显示图标、宽 56（悬停提示与无障碍标签保留页面名，授权提醒变为图标，版本号缩放）；主题、停靠位置分段控件与「连接时的程序坞」下拉移到标题下方单独一行；页面标题右侧按钮（设备模板/新增规格、常用快捷操作/添加操作）换到标题下一行；全局操作卡片改为单列；页面边距 24→16。各页内容原本就可纵向滚动。≥ 560 布局不变。只改布局，无功能改动。
- 离屏渲染（BR_SETTINGS_SHOTS，新增门控测试 NarrowSettingsShotsTests）：900×720 的常规/连接自动化/快捷操作/分辨率四页与 0.8.146 源码渲染逐像素一致（差异 0）；406×720 四页已查看，无裁切。
- `swift test -Xswiftc -warnings-as-errors`：Core 358 项全部通过（新增 SettingsWindowLayoutTests 7 项），App 64 项 0 失败、7 项门控跳过。首轮 WorkspaceLayoutControllerTests 已知偶发失败 1 次，单独重跑两次通过，第二轮全量一次通过。
- 追加（同版本，第二个提交）：设置里的弹窗也适配小屏。编辑快捷操作（460）、更换图标（460）、规格编辑（420）、常用快捷操作（440×480）、设备模板（580×510）、添加应用（440×480）统一用 `dialogFrame`：宽 = min(原宽, 屏幕可见宽 − 两侧各 16)，高同样不超过可见高 − 32；按内容定高的弹窗超出时改为纵向滚动，编辑快捷操作沿用自带的中段滚动。设备模板在变窄时把品牌菜单移到类型分段下方。更换图标 sheet 抽成 `BuiltinIconSheet`（内容不变）。
- 360 宽核对：主题（约 227pt）与停靠位置（约 199pt）分段控件在 360 窗口的行内可用约 243pt，完整显示、无裁切。
- 离屏渲染：桌面尺寸下 5 个设置页 + 5 个弹窗与上一提交逐像素一致（差异 0）；360/406 宽设置页、352/398 宽弹窗以及 248 高的短屏弹窗都已查看。设备模板的类型分段在离屏渲染里被压窄（上一提交同样如此，属于离屏加载时序，不是这次的改动）。
- `swift test -Xswiftc -warnings-as-errors`：Core 359 项全部通过，App 65 项 0 失败、8 项门控跳过。
- 实机测试（立品同意在本机操作）：用应用自己的分辨率面板切到「手机竖屏（保留操作栏）603×1156」，工具条在右侧展开。修复前设置窗口宽 579（≥560 走宽版），右边被工具条盖住，开关看不到。修复：设置窗口和弹窗的可用区域改用「铺满」同一个函数 `WindowControlPerformer.layoutArea`（工具条停靠且展开时才扣除），工具条一侧再留 8pt；工具条展开/收起/换边、分辨率变化（立即、0.5 秒、1.5 秒）都会重新适配。修复后 603 宽：窗口 499×720（可用区 523），窄版图标侧栏，不压工具条；折叠屏（内）1252×1156：900×720，右边距工具条 8pt；设置开着时用菜单「还原本机分辨率」，窗口恢复 900×720 居中。显示模式已恢复并与测试前记录一致。新增单元测试覆盖工具条扣除与间隙。Core 361 项、App 65 项（8 跳过）0 失败。
- 构建：苹果时间戳服务仍不可用（直连 17.157.80.35:80 被拒、经本机代理 502；临时加 Wi-Fi 代理绕过也无效，绕过列表已恢复为原 18 项并 diff 一致）。按立品选择，用 build.sh 的临时副本（仅 `--timestamp` → `--timestamp=none`，并去掉 DMG 步骤）做了**本地测试构建**：Universal（x86_64 + arm64），原 Developer ID + hardened runtime，严格签名验证通过，只有 Signed Time、没有安全时间戳。没有生成 DMG。
- 已备份到 `Backups/0.8.146-before-0.8.147-local-20261020-180000/`（偏好、各 json、local.RemoteFit.plist、旧版 0.8.146 App），正常退出旧版后覆盖安装 0.8.147 / 165，安装与构建的二进制一致，`open -g` 启动后进程在运行，preferences.json 哈希不变。**这是本地测试版，未公证、未发布；正式发布前必须重新带时间戳构建。**
- 立品同意后正式发布（提交 0a68dd9，无代码改动）：临时把 timestamp.apple.com 加入 Wi-Fi 代理绕过后构建成功（App、Sparkle 各组件、DMG 均含安全时间戳），绕过列表已恢复为原 18 项并 diff 一致。公证 `4f9c19ee-149c-42d4-a8cb-fd0586948b7c` Accepted（issues=null），DMG 与 App 已装订，spctl 均为 Notarized Developer ID。DMG SHA-256 `973a2bf9fa6df4ce4fb065613619bb08121d9e7bcbac0dbfc0763d9f4d29bf8f`，7447486 字节。
- Release v0.8.147 两个资产（版本名与固定名）下载后 SHA-256 一致；appcast 165 / 0.8.147 已提交下载仓库（da7680f）；官网 /download 返回 Better-Remote-0.8.147.dmg，SHA-256 一致。发布说明改为三条通用说明（README 同步）。

# 0.8.146 (164) — 连接时的程序坞 — 2026-10-20

- 原「连接时显示」每次连接按一次切换程序坞快捷键（⌥⌘D），对已设为常驻显示的程序坞会反而把它隐藏。改为三选一「连接时的程序坞」：保持现状（默认）/ 始终显示 / 自动隐藏；旧设置开启者迁移为始终显示，关闭或缺失为保持现状。
- 实现：通过“系统事件”读写程序坞自动隐藏（串行队列，不占主线程），仅在与目标不同时写入；写入前把用户原值存入 UserDefaults（崩溃后下次启动恢复）。断开连接、切回保持现状、正常退出时恢复原值。权限被拒（-1743）只记日志并提示一次，不再回退到快捷键。
- 程序坞写入完成并等待可见区域更新（≤1 秒）后，把原本铺满旧区域的窗口调整到新区域（始终显示时缩到程序坞上方，自动隐藏时长回全高）；用户自行排列的窗口不动。连接时自动铺满等程序坞处理完成后才运行。
- 签名：新增 `com.apple.security.automation.apple-events` 授权（scripts/BetterRemote.entitlements）和 NSAppleEventsUsageDescription。
- `swift test -Xswiftc -warnings-as-errors`：414 项（App 63 项含 6 项环境变量门控跳过、Core 351 项）全部通过，WorkspaceLayoutControllerTests 一次通过。新增 ConnectionDockTests、DockRefitTests。
- 已备份并覆盖安装 0.8.146 / 164（本地 Developer ID 无时间戳签名：当时时间戳服务直连被拒、经代理 502）。未公证、未发布、未更新 appcast，等待本机测试。
- 立品本机测试通过后正式发布（同一提交 3c9675e，无代码改动）：临时把 timestamp.apple.com 加入 Wi-Fi 代理绕过后构建成功（App/Sparkle/DMG 均含安全时间戳），绕过列表已恢复为原 18 项并 diff 一致。公证 `9bb0cd3f-7f9e-4a8c-89f7-06f15f301838` Accepted（issues=null），DMG 与 App 已装订。DMG SHA-256 `0edc3fe3a7e72179394e31dd5781868fd593c361150a93058993421b8740ccbb`，7377836 字节。
- Release v0.8.146 两个资产（版本名与固定名）下载后 SHA-256 一致；appcast 164 / 0.8.146 已提交下载仓库（9de93f2），raw 地址内容与本地一致，EdDSA 签名校验通过；spctl 对 DMG 与挂载内 App 均为 Notarized Developer ID。
- 实机日志：13:38 连接后 `connection_dock mode=alwaysShow autohide true->false`，退出时 `connection_dock_quit restored autohide=true`，重启后重新应用。两次 `connection_dock_refit visible_frame_unchanged`：1 秒内可见区域未变化，窗口未重排，待查。

# 0.8.145 (163) — AnyDesk 后台恢复识别 — 2026-10-20

- 实机发现：AnyDesk 后端在 11:24:38 重启，原服务会话保留，后端从 PID 21026 换成 24949；恢复时只有 `Backend respawn succeeded.`，不再次输出 `5: Entering processing loop.`。0.8.144 因旧成功时间早于新进程启动时间而误判断开。
- 修复：识别恢复成功事件；已建立会话发生 IPC 异常、后台退出或 backend PID 变化时返回 unknown，成功恢复后更新成功时间。保留仍打开的会话，避免新 PID 日志早于新防休眠断言出现时丢失上下文。
- AnyDesk 定向 15 项测试通过，包含两次对当前实际密码/令牌会话的只读检测；新增后台替换、旧断言到新断言的交接、恢复成功和最终关闭回归。
- 已构建并覆盖安装 0.8.145 / 163，Universal、原 Developer ID 本地无时间戳签名、严格签名验证、安装二进制一致、重启前配置字节未变。未公证或公开发布。
- 正式应用实测：11:27:45 `remote_signal connected providers=anyDesk`；11:27:47 `automatic_apply_result success`，切换至 1252×1156。此结果验证了应用重启后能从日志重建已经恢复的真实会话。未主动杀死 AnyDesk 再制造一次崩溃；正常用户断开后的还原仍待验收。
- 证据：`~/Library/Application Support/RemoteFit/RemoteFit.log`、`/tmp/remotefit-anydesk-respawn-final-tests.log`、`/tmp/remotefit-build-local-anydesk-respawn.log`。

---

# 0.8.144 (162) — AnyDesk 连接自动化 — 2026-10-20

- AnyDesk 9.8.1 实机信号：手动接受、无人值守密码连接都在认证成功后进入服务会话 `5: Entering processing loop.`，同时记录后端 `Session started (ok).`。取消未接受的请求不会进入该阶段。防休眠断言和 backend 进程在等待授权时已存在，不能单独触发自动化。
- 新增 AnyDesk provider：按服务 PID / fiber 跟踪入站桌面会话，以 backend PID 与实时防休眠断言关联，并校验进程启动时间。沿用 2 秒连接确认、4 秒断开确认；与 UU / ToDesk 共存时不因单方断开而还原。
- 只在 AnyDesk 有请求断言时增量读取标准 trace，等待认证期间每秒复查；无请求时不读取日志、不枚举 AnyDesk 进程。兼容官方文档列出的用户日志与系统服务日志位置（https://support.anydesk.com/what-are-trace-files）。日志缺失、读取失败或无法重建的历史保持 unknown；处理半行、文件轮换、截断、同 inode 重写和旧 PID 重用。
- 全量 `swift test -Xswiftc -warnings-as-errors`：396 项，388 通过、8 跳过、0 失败。跳过项含需要现场会话的测试、渲染开关测试和 Event Tap 权限测试。后续补充状态清理后，AnyDesk 定向 14 项通过（含现场未连接检测）。
- Universal Release 构建、严格签名验证通过，已覆盖安装 `/Applications/Better Remote.app`，版本 0.8.144 / 162。安装与构建二进制相同、偏好字节不变；使用原 Developer ID 身份的无时间戳本地签名，未公证或公开发布。
- 后续正式应用在 11:22:48 识别 AnyDesk 并成功切屏；11:24:38 后端重启后暴露恢复路径漏判，已在 0.8.145 修复（见上）。正常断开还原仍待最终实测；多设备并发、断网恢复或系统服务安装模式未做实机验收。
- 本地证据：`.build/anydesk-probe/`；构建与测试记录：`/tmp/remotefit-build-local-anydesk.log`、`/tmp/remotefit-anydesk-full-tests.log`、`/tmp/remotefit-anydesk-final-tests.log`。一次要求 connected 的现场测试因用户在测试启动前约 1 秒断开而失败；随后 disconnected 现场检测通过，不将前次算作成功连接验收。

---

# 0.8.120 (138) — 连接顺序与工具条动效 — 2026-10-13

- 连接确认时先排队工具条展开，分辨率操作完成或已在默认规格时才执行；没有开启自动分辨率时直接展开。断开连接或关闭自动展开会取消待执行动作，切屏失败结束后仍保留工具条入口供继续操作。
- 沿用玻璃方向与按钮按下反馈，面板 340 ms 轻弹展开、按钮从停靠边依次浮现并小幅弹入，收起 180 ms。单一可取消过渡任务处理快速反向和停用，异步内容更新在结束后统一重建，重新停靠可直接中断。减少动态效果时直接到位。
- 时序与原生动效检查连续三轮通过，每轮 13 项、0 失败，日志为 `.build/toolbar-transition-20261013/check-1.log` 至 `check-3.log`。全量 290 项中 288 通过、2 跳过、0 失败，warnings-as-errors。
- 原生窗口验证实际存在中间尺寸、快速反向最终收起、停用后无旧动画残留及减少动态效果分支。真实安装版的展开/收起截图位于 `.build/toolbar-transition-20261013/actual/`，已查看；AppKit 缓存截图只能用于几何检查，不能代表玻璃与图标的实际画面。本次未进行独立视觉评审，手机远程帧率与连接现场仍待实测。
- Universal Release、严格签名、公证 `517720ae-79b9-457f-9aa0-cc5e1dbb745c`（Accepted，issues=null）及票据检查通过，已备份并安装 0.8.120。测试时临时开启的工具条总开关已恢复原来的关闭状态，自动展开选项保留；没有更新公开 appcast。

---

# 0.8.119 (137) — 分屏结果判断 — 2026-10-13

- 用户操作日志确认选窗正常：前台 Orca 进入左槽，Chrome 进入右槽。两次 AX 写入均成功，但严格尺寸校验报错；Chrome 的目标宽度为 590，实际宽度为 626，随后工具条避让将其向左移动 36。
- 分屏单独识别尺寸受限的放置结果，并将右侧/底部边缘重新对齐到可用区域；不放宽其他窗口操作的严格校验。仍占满分屏轴、位置无关或超出整个可用区域的窗口不会被当作已分屏。尺寸受限提示为“窗口尺寸受限”，真正失败保留成功窗口数量。
- 已隔离旧会话的结束回调，未找到窗口会计入失败，取消或过期任务不再污染结果。
- 284 项自动测试中 282 项通过、2 项跳过，0 失败，warnings-as-errors。新增 590→626 几何回归、左右/上下边缘对齐、无实际分屏拒绝，以及两个尺寸受限窗口、成功/失败混合和旧回调隔离的原生窗口测试。
- 0.8.119 Universal Release、严格签名、苹果公证 `efe42c90-441d-4f61-b3e7-39c78aa92f04`（Accepted，issues=null）及票据检查通过，已备份并更新本机。证据位于 `.build/window-placement-20261013/`；实际 Orca/Chrome 手机操作仍待复测。

---

# 0.8.118 (136) — 减少显示切换的中间状态 — 2026-10-13

- 切换规格时先创建具有新 UUID 的单模式虚拟屏，将旧虚拟屏与物理屏一次交接到新镜像源；旧屏先成为镜像成员，避免仍占用主屏，确认交接后再释放。正常切换不调用物理桌面还原，原始恢复快照保持字节一致。
- DisplayWorker 仅提交实际变化的镜像、模式和排列；先解除新源的镜像，再配置跟随屏，最后设置排列和主屏。同规格重复选择不重建；原状态重复提交的原生检查返回 `changedDisplays=0`。
- 278 项自动测试中 276 项通过、2 项跳过，0 失败；使用 warnings-as-errors。新增交接规划、镜像模式跟随、回退身份、热插拔及错误布局校验。
- 原生 `--smoke --adjustments` 通过 1252×1156 → 630×1400 → 1024×768 → 1400×630 切换。三次正常交接均记录 `physical_restore=false`，只在测试最后还原物理桌面；切换前与切换后的注入失败均记录 `source_retained=true`，上一次虚拟屏 UUID 保留。
- 测试结束后，三块物理屏幕的 UUID、逻辑/物理尺寸、刷新率、主屏、镜像和排列与初始状态一致，preferences.json 字节一致，session.json 已清除。证据位于 `.build/display-transition-20261013/`。这些检查不等于手机端闪动或远程点击验收。
- Universal Release、严格签名、公证 `ef26730c-85fe-4cee-94b0-9139f4fd66e4`（Accepted，issues=null）、App/DMG 票据与分发前检查通过。安装包 `dist/Better Remote-0.8.118.dmg` 的 SHA-256 为 `d1114aefff2b5fbea00d24999db71e54bda15d01f1bbf4ef11a355491e4bf64b`。DMG 复用上一版安装窗口元数据，未通过 Finder 自动化操作桌面。
- 已备份 0.8.117 至 `~/Library/Application Support/RemoteFit/Backups/0.8.117-before-0.8.118-20261013-211009/`，安装并启动 0.8.118；安装后的二进制与公证构建一致，只有一个安装路径进程，辅助功能仍已授权，原有偏好不变。本次未更新公开 appcast 或发布仓库。

---

# 0.8.116 (134) — 后台开销与窗口操作响应 — 2026-10-13

- 连接检测：先筛选 UU/ToDesk 相关电源断言，仅有 ToDesk 有效连接断言时查询会话进程。空闲、仅 UU 连接的回归测试均确认不会枚举进程；ToDesk 仍需断言和进程同时成立，进程查询失败保留 unknown。
- 窗口扫描：后台消费者共享进行中的扫描和 200 ms 快照；查询在后台运行，工具栏收起后停止应用快捷栏定时器。显式点击选窗仍取即时窗口列表，保证命中正确性。
- 窗口操作：WindowController 主线程门面维护 busy 状态，WindowControllerWorker / WindowAXWorker 执行跨进程 AX 操作；轮询继承调用 actor。取消、鼠标按下、区域变化均重新校验。选窗匹配按每个窗口一次读取计算距离；窗口日志由串行后台队列写入。
- `swift test`：272 项，270 通过，2 项 Event Tap 权限测试跳过，0 失败；新增 5 项性能/取消回归测试全部通过。测试运行器没有输入拦截权限，不能把跳过项算作通过。
- `scripts/build.sh`：arm64 / x86_64 构建、固定身份签名验证、DMG 校验通过。Xcode 提示 macOS 27 SDK 已弃用 x86_64，但本次双架构产物生成成功。本版随后已完成公证与发布（见下）。
- 已覆盖安装 `/Applications/Better Remote.app`；安装与产物可执行文件 SHA-256 一致：`fcf15c92df9914d5ed5b18e2079d285cd65bf183fb7b5cfec713921e5c866cdb`。旧版备份 `/tmp/Better Remote-before-performance-0.8.115.app`，用户配置保留。
- 真实窗口验证：创建临时 TextEdit 文档，通过现有调试入口执行左半屏排列；窗口由 `{300,200,900,600}` 变为 `{0,33,864,1117}`，对应目标 `{{0,33},{864,1084}}`，权限 trusted=true。
- 阻塞验证：短暂停止本次创建的 TextEdit 进程，执行右半屏操作，采样 3 秒。AX IPC 等待出现在 WindowAXWorker 后台线程；主线程 2420 个样本中 2353 个在事件循环等待，没有 AX 查询阻塞。测试进程已恢复，临时文档已关闭，调试配置已删除，Better Remote 已按正常模式重启。
- 重启后 4 秒空闲采样没有 processPaths / proc_name / AXUIElementCopy 调用；CPU 瞬时读数 0.0%。系统 Event Tap 列表无 Better Remote PID；两块物理屏保持 120 Hz / 60 Hz，无镜像。本次未建立真实手机远程连接，不能据此声称漂移已彻底解决或给出整机性能改善百分比。
- 原始测试、构建、阻塞采样和空闲采样存于 `.build/performance-0.8.116/`。源代码仅在本地提交，不推送源码仓库。

- 发布完成：Apple notarization `df21c0a0-fd0f-4059-b344-d7313c884dfb` 状态 Accepted；app/DMG 装订、Gatekeeper 和镜像校验通过。EdDSA 签名后上传 `Better-Remote-0.8.116.dmg`，Release `https://github.com/pincc-debug/better-remote-releases/releases/tag/v0.8.116` 已公开并设为 latest。更新源提交 `fead3fabd8be95edba7e826950ae9b970b710ee3`，保留旧版条目；新版说明仅为“优化操作体验，使用更流畅。”。

---

# 0.8.112 (130) — 全局卡片底色统一为原生纯白 — 2026-10-13

- 快捷操作大分组外框（窗口控制、全局操作、应用快捷操作）由淡灰半透明底色改为原生纯白卡片底色（`Color(nsColor: .controlBackgroundColor)`），彻底消除浅色模式下灰底套娃发暗缺陷。
- 全软件 5 个设置页（常规、分辨率、快捷操作、连接自动化、触控）卡片背景 100% 统一为原生纯白卡片，内外层次一致、清爽通透。
- 自动化测试与 16 份深浅色截图核验全量通过。

---

# 0.8.111 (129) — Developer ID 签名与苹果公证 — 2026-10-13

- 已使用 `Developer ID Application: lipin cao (F6UJMD6RCL)` 签名，开启 Hardened Runtime，App 与 DMG 均包含安全时间戳；arm64 与 x86_64 架构保留。
- 苹果公证提交 `399d0470-74ec-4499-be1a-f19875177b17` 返回 `Accepted`，日志显示 `Ready for distribution`，`issues` 为 null。结果和日志位于 `dist/notarization-0.8.111*.json`。
- App 与 DMG 的公证票据附加、票据验证和严格签名验证均通过；`syspolicy_check distribution` 通过所有分发前检查。当前机器 `spctl --status` 为 `assessments disabled`，其 accepted 输出含 security disabled override，因此不作为启用 Gatekeeper 的实际安装验收。
- 只读挂载 DMG，确认包内版本 0.8.111 / 129、严格签名、可执行文件与签名 App 一致、Applications 快捷方式正常，原生 `--check` 通过；已卸载镜像。DMG SHA-256：`d4b313139de73c5e936a84f227a09a8f73a749aeee86cdff3708c1b39e5ffef5`。
- 本次未替换 `/Applications` 中的应用，未切换显示配置；第二台 Mac 的安装、辅助功能授权和手机远程功能尚未验收。公证凭据保存在本机钥匙串，不写入仓库。

---

# 0.8.111 (128) — oil-ui-pro 界面全面优化 — 2026-10-13

- 快捷操作首屏可见性：简化窗口控制为单行开关，切除非交互假红绿灯（省 76pt 高度）；全局操作紧凑化（最小高度 42pt，去除“12 项”文字计数），使“应用快捷操作”分组标题及首张应用卡片在 900×720 固定视口首屏 100% 完整可见（解决首屏能见度 0% 体验缺陷）。
- 连接自动化对齐规范：使用 `settingCard` 与 `settingRow`，补齐 28×28 SF Symbol 图标底座；目标规格选择器增加 54pt 缩进，层级清晰。
- 触控页减法：删除 30 字填缝冗余文字，转为 `.help` 原生提示，界面干净留白。
- 分辨率伴随面板：补齐物理像素尺寸（`preset.sizeLabel`）；长设备名添加 `minimumScaleFactor(0.85)` 防止截断；显示大小在未启用规格时以柔和强调色指示当前缩放；“还原本机”移除厚重大边框卡片，恢复为轻量纯文字整行按钮。
- 应用快捷卡片细节：移除“x 个快捷操作”冗余副标题，菜单移除重复的“添加操作”。
- 单元测试与验证：全套 265 项测试全部通过（RemoteFitCoreTests 234 项，RemoteFitTests 31 项，0 失败）；16 份深/浅色全景与局部截图已在 `DesignExploration/oil-ui-review-20261013/screenshots/` 重新生成并人工目视核验通过。

---

# 0.8.110 (127) — 快捷操作页参考图布局 — 2026-10-13

- 按参考图分为窗口控制、全局操作、应用快捷操作三个区块。全局保留双列卡片及拖拽排序；应用改为独立卡片，显示名称/操作数量和下方快捷按钮，按钮可自动换行。
- 应用卡片增加有效的收起按钮与操作菜单；内置全局操作的铅笔可更换图标，保存沿用原子写入及工具条刷新。说明性文案精简。
- 原生预览已查看：固定 700×560、整页及两个应用卡片，另验证七个快捷操作的换行布局。预览包含依据参考图构造的 Chrome 条目，未写入用户配置。文件位于 `.build/shortcut-layout-validation/`。未独立视觉评审，真实交互待用户稍后验收。
- 当前 Xcode 许可未接受，未代用户接受协议。采用现有 Command Line Tools、macOS 26.5 SDK 编译；临时 ManifestAPI 副本排除了 CLT 中过期 private swiftinterface，未更改系统工具链或仓库 Package.swift。UI 更新复用已有图标资源，正式构建脚本仍保留原 actool 流程。
- Universal Release（Swift warnings-as-errors）、签名、DMG 校验通过。已覆盖安装 0.8.110（127），二进制与包一致，配置保留。按用户要求未启动，进程检查确认软件未运行。

---

# 0.8.109 (126) — 收起文案与固定设置窗口 — 2026-10-13

- 工具条断开子开关统一显示「断开时收起」。设置窗口移除 resizable，内容最小/最大尺寸都为 700×560，并在恢复历史窗口位置后校正尺寸。
- 已实际打开安装版的连接自动化页面，AX 文案核验通过；WindowServer 回读设置窗口为 700×560。
- Universal Release、签名、DMG 校验通过；已覆盖安装并启动 0.8.109（126），原配置保留，二进制与包一致。

---

# 0.8.108 (125) — 分区自动化配置 — 2026-10-13

- 页面采用分辨率、工具条、程序坞三个纵向区块，普通子开关行。程序坞只有连接时显示，默认关闭，断开不触发。
- 程序坞使用独立新偏好字段 autoShowDockOnConnect，不继承旧 autoShowDockEnabled 的默认开启值；沿用现有程序坞预设，稳定连接只执行一次，关闭或断开取消待执行任务。
- 29 项相关策略、迁移和自动分辨率测试及 1 项原生界面预览通过；700×580 截图已查看，位于 `.build/connection-automation-validation/sections-108.png`。
- Universal Release、签名、DMG 校验通过；已覆盖安装并启动 0.8.108（125），原配置保留，二进制与包一致。手机连接自动化实际效果待用户验收。

---

# 0.8.107 (124) — 自动化表格与独立开关 — 2026-10-13

- 改为行为行、连接时/断开时两列的表格；分辨率和工具条各自拥有连接与断开的独立开关。
- 工具条断开开关开启时按总开关保留悬浮球或隐藏，关闭时不自动改变工具条。旧配置默认开启该项，保持 0.8.106 行为。
- 27 项相关逻辑测试与 1 项原生界面预览检查通过，700×580 表格截图已查看，位于 `.build/connection-automation-validation/table-107.png`。
- Universal Release、签名、DMG 校验通过；已覆盖安装并启动 0.8.107（124），配置保留，安装二进制与包一致。手机连接/断开真实流程待用户验收。

---

# 0.8.106 (123) — 连接自动化 — 2026-10-13

- 连接行为改为连接自动化，连接/断开两列，实际 700×580 原生预览已查看；截图位于 `.build/connection-automation-validation/`。
- 连接可临时开启并展开原本未显示的工具条，不更改持久化总开关；断开后总开关开启则保留悬浮球，关闭则全部隐藏。临时展开的工具条也参与窗口避让。
- 连接分辨率切换与断开还原独立，程序坞自动展示开关、旧字段及自动按键路径全部移除。
- 26 项策略/迁移/自动分辨率测试及 1 项界面预览检查通过。覆盖总开关关闭时仍可连接展开、断开恢复总开关语义、旧程序坞字段丢弃与新设置持久化。
- Universal Release、签名、DMG 校验通过；已覆盖安装并启动 0.8.106（123），二进制匹配，原配置保留。真实手机连接/断开仍待用户验收。

---

# 0.8.105 (122) — 铺满与工具条之间的间隙 — 2026-10-13

- `DesktopToolbarLayout.workspace` 原先在工具条实际边缘外额外扣除 8 点；删除该间距，全局「铺满」和窗口布局共用的区域现在紧贴工具条，仍不覆盖工具条。
- 48 项针对性测试通过，含四个停靠方向、负坐标屏幕的无缝边界及原生窗口填充回归。
- Universal Release、签名和 DMG 校验通过，已覆盖安装并启动 0.8.105（122）。安装二进制与包一致，原配置保留。

---

# 0.8.103 (120) — 输入通道按需释放 — 2026-10-12

- 用户确认无远程连接、收起工具条时外接鼠标仍飘；内置触控板未明显复现。设备清单为 USB Logitech G102 LIGHTSYNC。
- 现场发现快捷键转发留下两个 null-event taps。它们不是普通鼠标移动监听，尚未证明是漂移唯一原因；本版改为释放事件发送完成后即销毁，下一次快捷键再创建。null 唤醒事件明确关闭本地输入抑制。
- 关闭菜单的全局/本地点击监听仅在菜单或伴随面板显示时注册，空闲即移除。
- 9 项执行测试通过；2 项真实事件通道测试因测试进程权限不足跳过。安装二进制的 CLI 诊断同样受启动上下文权限限制返回 unavailable，未据此声称发送回归通过。
- 已覆盖安装并启动 0.8.103（120）。Universal Release、签名、DMG 校验通过，二进制匹配且配置保留。现场 CGGetEventTapList 未发现 Better Remote 事件通道，remote-status active=[]。
- 程序退出前后显示器模式快照一致（内屏120Hz，两块外屏60Hz），没有退出时切换分辨率或刷新率。
- 试图验证已有快捷键编辑保存时用户同时操作，停止自动化以免争用鼠标；该项尚待用户实际编辑确认。外接鼠标主观体验仍待验收，未宣称彻底消失。

---

# 0.8.102 (119) — 本机鼠标与应用快捷键保存 — 2026-10-12

- 用户确认普通鼠标移动会飘，关闭单指滚动改善但未完全恢复，完全退出 Better Remote 后恢复正常。
- 单指转换仅在配置启用且远程连接已确认时注册；断开、关闭、退出时移除。普通本机输入取消远程延迟手势和惯性，释放已注入的按下。超出原点击范围不再回放旧位置。
- 19 项针对性测试通过，覆盖本机移动取消延迟事件、接管释放事件、停止时只释放一次、远程检测与点击容差。
- 应用快捷操作编辑改为单一 EditDraft 同时携带 Bundle ID 与快捷键。保存与删除读取最新配置，更新已有 ID，不依赖弹窗捕获的旧应用状态。实际保存回归尚待完成（用户正在操作电脑，停止自动化以免影响鼠标验收）。
- Universal Release、签名与 DMG 校验通过。已覆盖安装并启动 0.8.102（119），配置保留，二进制与包一致。
- 安装后现场核验：单指滚动配置为 true、remote-status active=[]，CGGetEventTapList 中 Better Remote 的事件监听为零。用户正在复测主观鼠标体验。

---

# 0.8.100 (117) — 无遮罩直接选窗口 — 2026-10-12

- 完全移除 PickerPanel / PickerOverlayView，不创建透明覆盖层，不吞掉或改写点击。全局及本应用事件监听记录真实窗口，松开后排入下一格。
- 忽略打开布局时遗留的 mouseUp；记录按下时窗口，布局动作在松开后执行。结束时移除监听与计时器，旧会话的异步事件不影响新会话。
- WindowPicking / WindowSnap 共 8 项测试通过；新增原生窗口回归通过，验证不创建覆盖窗口、仅松开后触发第二格及正确结束。
- Universal Release、签名、DMG 校验通过，已覆盖安装并启动 0.8.100（117），二进制与包一致，配置保留。手机真实操作仍待用户验收。

---

# 0.8.99 (114) — 应用快捷菜单外框 — 2026-10-12

- 小菜单与主工具条一样保留 6 点透明绘制空间，避免玻璃边缘被窗口边界截断。外圆角改为 20 点，与内部 12 点按钮圆角及 8 点内边距协调。
- 原生菜单点击与截图验证通过，深色截图已查看，存于 `.build/application-shortcuts-validation/application-menu-border-099.png`。电脑操作工具拒绝访问 Warp，采用 Finder 临时窗口及隔离配置验证，没有操作用户终端或更改快捷键配置。
- Universal Release、签名、DMG 校验通过；已覆盖安装并启动 0.8.99（114），二进制与包一致，配置保留。

---

# 0.8.98 (113) — 关闭窗口后的应用入口 — 2026-10-12

- 应用快捷入口候选需仍有屏幕上的可操作窗口；关闭最后一个窗口后隐藏，不跳到旧的已配置应用。保留手机点按导致本程序短暂激活时的目标回退。
- 工具条展开且启用应用快捷操作时，每 0.3 秒检查窗口变化，支持关闭、最小化及重新打开窗口。
- 15 项相关测试通过，覆盖进程仍活着但最后窗口已关闭、有剩余窗口及重新打开窗口的目标选择；手机真实交互待用户验收。
- Universal Release、签名与 DMG 校验通过。已覆盖安装并启动 0.8.98（113），二进制与包一致，原配置保留。

---

# 0.8.97 (112) — 手机点按应用入口消失 — 2026-10-12

- 本机操作日志中的 front=1873 已核对为 Better Remote 自身；全局快捷键回退正常，应用入口此前直接过滤 ownPID，导致入口消失。
- 应用入口与菜单统一使用最近普通应用回退，仅在本程序、辅助进程或前台暂缺时启用；真实普通应用切换不会回退到旧的已配置应用。
- 13 项相关测试通过。额外原生回归实际激活测试进程成为前台，断言应用入口与已打开菜单均保留，通过。尚待用户手机实测。
- Universal Release、签名与 DMG 校验通过；已覆盖安装并启动 0.8.97（112），安装二进制与包一致，原配置逐项一致。

---

# 0.8.96 (111) — 应用菜单方格 — 2026-10-12

- 应用快捷操作菜单改为全局按钮尺寸，最多四列，依次排列；两项菜单实际截图已查看，原生点击验证通过。
- Universal Release、固定签名与 DMG 校验通过。应用文件已覆盖更新，二进制与包一致。
- 用户完成编辑并要求覆盖安装后，已正常退出旧进程，重新覆盖安装并启动 0.8.96（111）。签名、二进制一致性及安装前后配置一致性均已核验。
- 用户新报首次安装 UU 自动切换未发生，已确认手动切换成功；尚待受影响 Mac 的 `--remote-status` 与 RemoteFit.log，未推断或修改连接识别规则。

---

# 0.8.95 (110) — 应用配置与贴边修正 — 2026-10-12

- 应用总开关移到首行，下面按应用逐行排列快捷操作；应用列表面板支持图标、名称、搜索和去重。
- 四个方向的展开工具条不再保留外边距，左右铺满可用高度，上下铺满可用宽度；收起状态沿用原位置。
- 28 项针对性测试通过（布局、应用配置、原生多显示器填充）；临时应用扫描与界面渲染测试通过，截图已查看，保存在 `.build/application-shortcuts-validation/`。
- Universal Release、固定证书签名、DMG 校验通过；已覆盖安装 0.8.95（110），安装二进制与包一致，原配置保留。
- 已在安装版实际打开添加应用面板并搜索 Finder，返回结果正确；取消后回到快捷操作设置。运行中左侧工具条面板坐标为 x=-6、y=27、84×1096，扣除 6 点透明绘制边距后，可见工具条为 x=0、y=33、72×1084，与本机可用屏幕边界一致。

---

# 0.8.94 (109) — 应用快捷操作与窗口布局 — 2026-10-12

- 新增按 Bundle ID 保存的应用快捷键；默认关闭的总开关不影响配置编辑。全局快捷操作保持原有数据。
- Finder 原生图标固定在红绿灯上方；原生测试点击后菜单出现，前台应用仍为 Finder；关闭开关入口消失。设置、工具条与二级菜单截图已实际查看，位于 `.build/application-shortcuts-validation/`。未独立视觉评审。
- 布局按窗口所在屏幕计算并扣除同屏工具条；复用完整 AX 写入、等待与 WindowServer 回读，失败不再被当作成功。右侧展开工具条取消 8 点边距。
- 多窗口选择移除可见遮罩、操作指引与成功提示；队列等待最后一个窗口完成后才结束。保留失败提示。
- `swift test`：243 项通过，0 失败。原生 NSWindow 填充测试覆盖本机各显示器及四个工具条方向。额外临时菜单点击/截图验证通过。
- Universal Release（arm64/x86_64）、warnings-as-errors、固定证书签名验证和 DMG checksum 通过。
- 已覆盖安装 `/Applications/Better Remote.app` 并启动，版本 0.8.94 / build 109；安装文件与打包产物 SHA-256 一致，原配置字段逐项一致。
- 尚未验证：手机远程真实点选、用户常用应用对 AX 布局的实际响应。由用户本轮测试确认。

---

# Better Remote 0.7.1 — 2026-09-20

Current product scope supersedes the old popover-only and runtime-dependency descriptions below.

Implemented:
- Better Remote branding and DMG, while retaining local.RemoteFit identity and the existing data directory for migration.
- Application-logo launcher and 72pt circular quick actions in one upward vertical column. Expanded actions persist across app switches; overflow pages use More.
- Settings has two top-level directories only. Resolution presets live in its content area. Recheck removed.
- Large resolution and application panels replace one another and Settings. Choosing an app dismisses immediately; successful explicit resolution application dismisses. Plus/minus preview remains open.
- Installed application discovery, frequent/running/all filters, app and Better Remote function search, persisted counts for successful launches through the panel.
- Named configurable shortcuts, optional built-ins, 12 icon choices for both kinds. Manual key selection is the default; optional recorder remains.
- Shortcut permission check before add/edit/record, with a draggable .app card beside System Settings. No permissions are granted by the app. Guide modeled on the local AppLoop AccessibilityPermissionGuideController implementation.
- Recording now uses a temporary suppressing event tap, removed after key release, focus loss or view removal.
- Corrected device-dependent left/right modifier flags. Saved WeType shortcut was verified as right Option (code 61), single press. User confirmed tap to start/tap to stop, so its mode was not changed.

Verification:
- Final 0.7.1 (10) DMG passed checksum verification and read-only mounting. Mounted app signature, arm64/x86_64 slices, exact binary hash, application branding, Applications shortcut and native capability check passed.
- 29 Swift tests passed: restoration, adjustment, histories, configuration migration, event sequencing, icon migration, left/right Option flags (0x80020/0x80040) and release to zero.
- Real temporary harness confirmed nonactivating floating panels, app activation, previous-app toggling, persistent expansion and vertical-column frames.
- Native window lifecycle harness confirmed only one of resolution/apps/settings was visible after each transition.
- Installed-catalog integration verified discovery, frequency ordering and persisted successful-open count; search harness verified Finder, resolution and Better Remote function lookup.
- Offscreen native rendering reviewed for settings, manual shortcut editor, app panel and wide/narrow resolution layouts. Compact resolution uses preset/adjustment tabs; action buttons remain fixed.
- Original temporary shortcut smoke helper crashed because it used fatal assertions while its manual run loop did not dispatch AppKit key events. The helper now pumps AppKit events and exits with normal error output. Single/double/hold/release passed in its dedicated receiver. This was not a crash of the installed application.
- Recorder checks covered modifier combinations and right Option identity. A separate controlled harness also verified that the temporary event tap records an injected test key and completes, and that all 12 preset icons resolve. The new right-Option device flags are covered in event-plan tests; live WeType voice activation has not been confirmed. Orca Computer Use could not expose the running input method as an application surface.

Not verified: target voice-input response, microphone forwarding, live permission drag/drop on a previously unauthorized app, other Macs/OS versions, Intel runtime and physical-phone touch precision. Current package remains ad-hoc signed and unnotarized. No automatic microphone routing is implemented.

UI review: fixed small touch targets, disappearing quick actions, crowded preset cards, hidden scale row, mixed settings sidebar and stacked quick panels. Active/disabled/holding/error/empty states inspected in source; relevant rendered layouts inspected. Approve for that coverage; remaining runtime gaps are listed above.

---

# 0.5.1 fixed adjustment rows — 2026-09-20

Only the preset catalog scrolls. Width, height and scale controls are outside the scroll view and keep their intrinsic height. Below 480pt panel height, the preset grid becomes a menu to preserve all three adjustment rows and bottom actions.

Offscreen AppKit renders at 360x580 and 360x420 were inspected: all three rows including 100% are visible without scrolling; footer buttons remain fully visible. No display engine changes. Phone interaction and keyboard-focus walkthrough: Not verified.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/RemoteFit/ControlPanel.swift:body | Adjustment rows scrolled with preset cards | Fixed adjustment rows, scrolling presets, compact menu for short panels | Keep primary touch controls visible |

Approve for the inspected layout; unverified interaction coverage remains open.

---

# 0.5.0 adjustment and touch UI validation — 2026-09-20

- Default presets retained. Selecting a preset or using width/height/scale controls previews the actual desktop. Width/height step is 32 base pixels; scale step is 10 percentage points. Effective logical dimensions are recalculated from the base without cumulative rounding.
- Save Copy writes a new preset with a new ID and the effective dimensions. It is enabled only after successful preview; save failures retain the draft. Successful save shows an inline saved state and prevents accidental duplicate taps until another adjustment/selection.
- Removed the normal title/status block from the popover as requested. Errors remain accessible through an error button.
- `swift test`: 18 tests passed, including boundaries, independent axes, scaling round-trip and copy serialization/identity.
- Universal Release build and DMG checksum passed. Mounted DMG signature and binary hash matched the built app before final copy-button feedback polish.
- Mounted `--smoke --adjustments`: width, height and scale live previews passed; final three-display snapshot exactly matched the initial snapshot. No recovery file remained. Existing app was closed for the test and reopened afterward.
- Offscreen AppKit rendering reviewed at 360x580 and 360x420. Bottom actions remain fixed; middle content scrolls. On shorter panels some presets/adjustment rows require scrolling.

UI polish review:

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/RemoteFit/ControlPanel.swift:ChoiceCard | 52pt card, no content padding | 64pt height, 10pt padding, horizontal icon/text, inset selection stroke | Optical spacing and selection boundaries |
| MEDIUM | Sources/RemoteFit/ControlPanel.swift:FooterButton, stepButton | Small text actions | 44pt minimum hit area and separated button surfaces | Easier remote touch interaction |
| MEDIUM | Sources/RemoteFit/AppController.swift:panelHeight, renderMenu | Fixed old popover clamp | Height follows available screen; central scrolling and fixed actions | Keep actions reachable after resolution changes |

Code-inspected states: selected/unselected, hover, disabled/busy, saved, error and preset list without custom entries. No new motion transitions. Not verified: real phone touch accuracy, keyboard focus walkthrough, and other Mac/macOS versions. Private CoreGraphics API and ad-hoc distribution limitations remain.

Approve for the inspected layout and code states; unverified coverage listed above remains open.

---

# 0.4.0 standalone validation — 2026-09-20

This section supersedes all remote-connection and automatic-switching behavior in older records below.

- Removed UU process/assertion detection, installation/open actions, remote-session policy, auto-switch toggle and periodic polling. No BetterDisplay or remote-app references remain in Sources.
- Manual apply, custom presets, restore, recovery snapshot and restore-on-exit retained. Old preference JSON loads while ignoring the removed enabled field.
- `swift test`: 14 retained tests, zero failures; obsolete remote-session tests removed.
- Universal Release build: arm64 and x86_64, Swift warnings treated as errors. Version 0.4.0 (4).
- ZIP: `dist/RemoteFit-0.4.0.zip`. Extracted outside the repository before runtime verification. Signature verified after extraction.
- Inspected both slices with `otool -L`: only `/System/Library/` and `/usr/lib/` dependencies. No third-party framework, CLI, interpreter or local build-path dependency.
- Extracted app `--check`: native display capability available.
- Extracted app custom 1366x768 hold-and-restore, portrait 630x1400, and injected-failure rollback: PASS. BetterDisplay was not running. Final display snapshots exactly matched the three-display baseline; recovery file removed.
- Extracted GUI app launch/exit test with PATH restricted to system tools: PASS. Startup did not change display configuration; SIGTERM exited successfully.

Limits: runtime tests on this Apple Silicon Mac only. Intel slice compiled, not tested on Intel hardware. No clean second-machine or older-macOS acceptance. The CoreGraphics virtual-display API is private. Package uses ad-hoc signing, not Developer ID or notarization; it is a test distribution, not a verified public release.

---

# 0.3.0 native display validation — 2026-09-20

This section supersedes the BetterDisplay-dependent results below.

- Release build with warnings as errors: PASS. Version 0.3.0 (3), ad-hoc signature verified.
- `swift test`: 27 tests, zero failures. Includes local manual persistence, later remote disconnect, and restore-state reset.
- `--check`: native virtual-display API available; native UU assertion and pmset agree (disconnected).
- BetterDisplay was fully exited for the release smoke checks; no BetterDisplay process was running.
- `--smoke --manual`: PASS. Applied custom 1366x768 through the manual request/poll flow with UU marked unavailable, verified 2x HiDPI and main mirror source, held beyond the disconnect debounce, then restored.
- `--smoke portrait`: PASS. Applied 630x1400 HiDPI and restored.
- `--smoke phone --inject-failure`: expected exit 1 with the injected error; recovery completed and session.json was removed.
- All three original displays restored, including resolution, pixel size, main display and arrangement. Final readback: 1728x1117 @120 Hz, 2560x1440 @60 Hz, 1152x2048 @60 Hz, all unmirrored.
- Debug native smoke also passed 1400x630 HiDPI and restoration.

Limits: tested on this Mac only. The virtual-display interface is private and requires revalidation after macOS updates. This revision has not repeated a real UU connect/disconnect session or manual visual UI acceptance. Unit tests cover the connection policy. No notarization or Developer ID signing.

---

# 本机验证记录

## 0.2.0 界面与自定义规格

- 快捷入口改为原生 popover，规格与显示大小直接展示，不再使用二级菜单。所有规格共用按宽高比例绘制的图标与明确的选中标记。
- 新增独立设置窗口，支持默认规格预览、另存为自定义、命名、宽高编辑、保存使用与删除；自定义列表与选择随偏好持久化，兼容旧版偏好。
- 21 项逻辑测试通过，新增旧偏好迁移、自定义保存恢复、非法与溢出输入、缩放边界，以及原生连接断言的类型、状态、进程校验。
- Release warnings-as-errors 构建和本机签名检查通过。设置窗口和比例图标已截图检查；新增与保存入口已实际打开。
- 用户要求自行验收，停止进一步界面操作。快捷面板完整点击流程、自定义键盘输入/编辑/删除、所有焦点/悬停状态以及新检测接口的真实手机连接状态标为 **Not verified**，由用户验收；逻辑测试不替代这些交互验证。
- 自动化测试过程中新增了一个本地 `1280×720` 自定义项（无名称）；它属于当前用户运行数据，不包含在 DMG 内，可在设置中编辑或删除。

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | ControlPanel.swift | 规格和显示大小需展开二级菜单 | 一级规格卡片与显示大小按钮 | 减少手机远程操作步骤 |
| MEDIUM | ControlPanel.swift / SettingsView.swift | 规格仅有文字 | 图标按实际比例绘制，选中有边框与勾选 | 直观区分比例且不只依赖颜色 |

已检查范围可交付；未检查交互不作通过结论。

### 检测开销

0.2.0 使用 IOKit `IOPMCopyAssertionsByProcess`，不再每次启动 `pmset` 子进程；仅状态变化时刷新界面，依赖应用列表每三秒更新。

- 旧命令单独执行 12 次：平均 CPU 约 8.29 ms/次，按 600 ms 间隔折算约占一个核心的 1.38%。
- 原生系统调用连续执行 100 次：平均本进程 CPU 约 0.045 ms/次。该数字不包含系统服务与整个应用的所有开销。
- 应用关闭设置窗口后采样约 15 秒：进程 CPU 约为一个核心的 0.53%，RSS 约 53.8 MB。采样未同步记录自动适配开关，因此只能作为该次空闲样本，不能认定为所有待机状态的基准。
- 未重新测量真实远程中的 UU、WindowServer、GPU 与应用总开销。原生接口与 `pmset` 在未连接状态下返回一致，已完成该项只读对照检查。

## 0.1.0 基线

日期：2026-09-20。环境：Apple M4 Pro，macOS 27.0，UU 远程 4.39.0，BetterDisplay 4.1.1。产物：`dist/RemoteFit.app`，版本 0.1.0（1），本机 ad-hoc 签名。

## 已完成

- Swift 6 Release 构建，warnings-as-errors，应用签名和 Info.plist 校验通过。
- 13 项核心逻辑测试通过：连接断言识别、两秒断线缓冲、检测失败不误判断线、关闭开关后恢复、有限重试、比例和缩放、HiDPI 判定、显示 ID 重建、唯一硬件标识兜底、标识歧义拒绝、主屏拔出后的排列恢复。
- 5 种比例 × 3 档大小，共 15 种配置逐一在实际显示器上切换，确认虚拟屏为镜像主屏且实际像素为逻辑尺寸的两倍；每轮恢复后的两块物理屏状态均与原快照完全一致。
- 模拟提交前切屏失败，确认自动恢复并清理会话快照。
- 用户使用手机实际连接 UU，新版应用自动切换到默认 1400×630 HiDPI；测得切屏流程约 3.1–3.8 秒（非手机端到端时延）。
- UU 保持连接期间，对应用发送 SIGTERM，经应用正常退出处理流程恢复显示并退出，完整退出约 2.66 秒。退出后继续观察三秒，未再次切屏。
- UU 仍连接时重新打开应用，自动重新适配，切屏流程约 3.155 秒。
- 用户断开 UU：日志在 16:33:56 记录断开信号，16:34:01 记录恢复完成。含两秒缓冲、轮询与恢复，总计约五秒；恢复动作本身为 1.993 秒。
- 断开后的状态再次读取确认：内置屏 1728×1117 HiDPI、120Hz、主屏、位置 (0, 0)；外接屏 2560×1440 HiDPI、60Hz、位置 (-64, -1440)，无镜像、无活动虚拟屏、无待恢复快照。
- 旧 `local.uuremote-display-adapter` LaunchAgent 已 bootout，原 plist 改名为 `.plist.disabled`。旧脚本和数据保留，新软件不依赖它们。

## 实现中处理的兼容问题

- 多比例共用虚拟屏模式列表时，镜像协商可能选中其他尺寸。每次连接只开放当前尺寸，并连续读取确认，必要时有限重提源屏模式。
- 本机 1000×450 镜像时回退到非 HiDPI；手机横屏最小档改为 1200×540，竖屏最小档为 540×1200，均已通过实际验证。
- AppKit 的退出等待可能阻塞主队列任务。恢复放到 detached task，通过主 RunLoop 回传退出结果，已在真实远程连接中复测。

## 验证边界

- 未测其他 Mac、其他 macOS / UU / BetterDisplay 版本；未做 Developer ID 签名、公证或公开分发。
- 未模拟卸载依赖软件、物理拔插显示器或强制结束后的全部组合；相关标识和恢复规则有逻辑测试覆盖，不能替代跨设备实测。
- 未完成手机端黑边、字号舒适度及端到端等待时间的主观验收。原生菜单栏 UI 已实现，自动化 UI 工具无法枚举该无窗口 accessory app，菜单视觉与点击交互仍需人工验收。
- 强制结束、崩溃与断电的即时恢复不作保证；恢复记录保留至下次启动处理。


## 0.7.2 permission-card update — 2026-09-20

- Permission guide now uses the compact icon/name row and a same-size drag preview, aligned with the System Settings content area. Native NSURL file dragging replaces the legacy custom pasteboard types. Dragging sends the actual app bundle and temporarily makes the guide non-interactive and lowers it.
- Permission status is always visible in settings. Accessibility and event-posting APIs must both report readiness; otherwise the row shows not authorized or pending. Monitoring continues while the settings section is visible, independently from whether the guide is open.
- Removed pencil overlays from built-in icon controls; clicking the icon still changes it.
- Concurrent UI edits were present in the workspace, so verification used an isolated source snapshot. 31 tests passed. A controlled native check replaced a deliberately stale in-memory permission state with the actual API result via the running timer; native file-URL payload and card rendering were checked. No system permission grants were changed.
- Release universal build, DMG checksum, mounted signature, version 0.7.2 (11), exact binary hash and native capability check passed. Artifact: `dist/Better Remote-0.7.2-permissions.dmg`.
- Actual user drag/drop and toggle authorization remain manual acceptance; the legacy-pasteboard UTI warning is gone, while the isolated clipboard probe still printed a sandbox-extension diagnostic without failing its file-URL readback.


## 0.8.0 native glass and authorization correction

- Corrected the previous permission-status regression: AXIsProcessTrusted is authoritative for Accessibility authorization. A false CGPreflightPostEventAccess no longer changes an authorized Accessibility status into pending. The sender separately calls CGRequestPostEventAccess when needed and reports an actionable failure if event posting remains denied.
- Replaced hand-painted bubble sheen/HUD surfaces with NSGlassEffectView on macOS 26+. Content is inside contentView, following the native AppKit composition model. Bubbles use clear glass; dense application/resolution panels use adaptive regular glass. Older systems fall back to active behind-window visual effects. Original application logo retained.
- Verified native class/content hierarchy and actual screen-composited output against a controlled colored backdrop. Both panel and bubble transparency were inspected; per-window screenshots exclude backdrop sampling and were not used as visual acceptance evidence. System Reduce Transparency was false during verification.
- 31 tests passed in an isolated snapshot, including AX-authorized/posting-preflight-false and revoked-state cases. Other installed-app authorization state was not modified; actual post-permission behavior still depends on macOS granting the separate posting request.
- UI states inspected: idle, unavailable, holding, hover, drag, older-OS fallback in source; current-system native surfaces visually checked. Other OS versions, Reduce Transparency enabled, and real phone ergonomics remain unverified.


## 0.8.1 stable signing and native circular controls

- Replaced layered/custom-drawn floating-ball canvases and their shadow containers with native NSButton glass bezels and circular border shapes on macOS 26+, including native image/title rendering. Image/title hug as one centered unit. Older systems use circular native controls. Screen-composited inspection shows no square backplate.
- Category targets are full-width 72pt-high rectangles including whitespace; close target enlarged, category changes immediate, glass hosting accepts first mouse. Physical-phone latency/accuracy remains user acceptance.
- Removed CGPreflightPostEventAccess/CGRequestPostEventAccess as sender gates. AX authorization remains mandatory; an isolated receiver received Command-C and Command-V immediately without changing clipboard contents. No restart warning remains in the sender.
- Build now uses a fixed existing local certificate (Aquarium Local Code Signing by default; BETTER_REMOTE_SIGN_IDENTITY override), rejecting ad-hoc fallback. No new private keys were created or exported. Current installed old build had a cdhash-based designated requirement. New package has identifier local.RemoteFit plus certificate-leaf identity.
- Changed a signed copy's resources and re-signed it: its CDHash changed while its designated requirement remained identical; codesign verified the updated copy against the old requirement. This validates signing continuity, not a forced change to the user's TCC grant. Migration from the old ad-hoc identity requires one new authorization.
- Isolated build: 31 tests passed. Mounted 0.8.1 (13) DMG verified fixed certificate requirement, signature, exact binary, both architectures and native display capability. Artifact: dist/Better Remote-0.8.1-stable.dmg.


## 0.8.2 display-size presets — 2026-09-21

Added five scale presets below the resolution catalog: 120%, 110%, 100%, 90%, 80%, plus 10-point adjustment buttons. All levels derive from the unchanged base dimensions; unsupported custom sizes disable the corresponding choice. Scale preview keeps the panel open. Header dimensions now use actual applied state. Short panels use a horizontal compact preset catalog to preserve the lower controls.

33 tests passed, including all standard-preset/scale combinations, boundary rejection, and scaling round-trip without cumulative rounding. Universal Release and DMG checksum passed; mounted app version, fixed-certificate signature, exact binary and native capability check verified. Physical phone interaction was not repeated.


## 0.8.6 UI refinements — 2026-09-22

- Added confirmation before deleting presets or custom actions; named the floating toggle for accessibility; respected Reduce Motion in launcher hover and settings navigation; unified floating-control labels; distinguished search-empty results with a clear-search action; shortened permission and introductory copy.
- Existing 35 tests passed after these UI changes. Universal Release build passed with warnings treated as errors.
- DMG checksum, mounted version 0.8.6 (18), strict code signature, arm64/x86_64 architectures, exact binary match, Applications symlink, and read-only native display capability check passed. Verification mount detached afterward.
- Artifact: `dist/Better Remote-0.8.6.dmg` (1,963,197 bytes). SHA-256: `041d298fae9084484ac5c82abb87cad6510afa7137faf1c8e4356a2b42d0d162`.
- Existing fixed local signing identity retained; no Developer ID notarization, installation replacement, or actual UI/phone interaction acceptance performed. Source changes remain uncommitted.

## 0.8.7 UI refinement (2026-09-28)

- `swift test`: 35 tests, 0 failures.
- SwiftUI/AppKit offscreen rendering uses isolated sample presets and application rows; no display modes or saved user preferences are changed. Checked resolution and launcher layouts at 900×640, resolution compact layout at 640×400, settings at 700×560, and floating settings at 640×500, in light and dark appearances.
- Removed the empty general page, moved permission status to the sidebar, reduced nested panel surfaces and app tile decoration, and aligned the settings window minimum with its SwiftUI content minimum.
- Offscreen render checks do not establish live keyboard, VoiceOver, remote touch, display switching, or installed-app acceptance.

## 0.8.8 Icon replacement (2026-09-29)

- Selected `assets/branding/better-remote-3d-v5.png` as production artwork; ICNS packaging generates all 16–1024 pixel representations with alpha preserved.
- Floating main button now loads the bundled full-color ICNS instead of the old drawn monochrome mark. Expanded close button and action symbols retain their existing behavior.
- Universal Release build with warnings-as-errors, fixed signature verification and DMG verification passed. Mounted DMG executable and ICNS hashes match the local app; mounted signature verified. Extracted 256px icon visually inspected.
- Live Finder icon-cache refresh and floating-button appearance are not verified; no installed app was overwritten.

## 0.8.9 Floating mark correction (2026-09-29)

- Restored the original monochrome floating main-button drawing and label tint. Drawing implementation matches the baseline exactly except comments; other existing floating-control edits are preserved.
- New generated artwork remains the application icon only.
- Universal Release build, strict signing and DMG verification passed. Mounted executable and icon match local artifacts. Live floating-button appearance remains unverified.

## 0.8.10 Simplified device icon (2026-09-29)

- Application artwork restored to v4: teal-grey tile with simplified lavender display and mint phone. Floating monochrome mark unchanged.
- Universal build, fixed signature and DMG verification passed. Mounted executable and ICNS match the local app; extracted 256px icon inspected. Installed application and live icon cache not changed.
# 0.8.11 UI refinement — 2026-09-30

- Resolution overlay retains direct percentage presets; the 10% increment/decrement controls now live in Settings and use the existing adjustment bounds and live-apply callback. Applied preset rows retain their selected background and checkmark without a duplicate disabled button.
- Shortcut editor removes its explanatory subtitle and basic-information heading. The unsaved shortcut preview is labelled `快捷键`. Launcher icons are 64pt, names 14pt, with a 40pt two-line text area and 128pt minimum tile height.
- `swift test`: 35 tests, 0 failures. `git diff --check`: passed.
- Isolated native SwiftUI/AppKit renders inspected in light/dark: Settings 700×560, resolution 900×640 and 640×400, launcher 640×500 with long two-line names, shortcut editor 460×660. Settings at 640×500 with 110% applied was also inspected; stale preset selection is correctly absent. Preview models use sample data and inert callbacks; no saved preferences or display modes were changed. Images: `dist/ui-preview-0.8.11/`.
- `./scripts/build.sh`: universal Release build with warnings-as-errors, fixed local signature and DMG verification passed. Mounted 0.8.11 (23) signature, executable/icon hashes and Applications link verified; image detached afterward.
- Artifact: `dist/Better Remote-0.8.11.dmg`. SHA-256: `07baf84f67ec25eebb2535c9e767dcfcfec9f2f6bce586001751c58c5eb18b0c`.
- Installed-app replacement, live keyboard/VoiceOver walkthrough and physical remote touch: not performed. These renders verify layout only. Existing local signing identity retained; no Developer ID notarization performed.

## 0.8.12 Unified action list — 2026-09-30

- Settings uses one operation list with aligned switches. Built-in rows offer switches only; custom rows offer edit, confirmed delete and enable/disable. Removed the separate custom/built-in headings and empty-custom placeholder.
- Custom shortcut enablement is stored independently of its configuration. Legacy shortcuts without the new field decode as enabled; disabled shortcuts remain editable and retain their state when saved. The floating switcher filters disabled shortcuts and releases held keys before rebuilding. Explicitly disabling all built-ins is respected on reload and after deleting the last custom action.
- `swift test`: 37 tests, 0 failures, including legacy enablement, disabled-shortcut persistence and all-builtins-off persistence. `git diff --check`: passed.
- Native isolated SwiftUI/AppKit rendering inspected for the unified list at 700×580 and 640×500 in light/dark, with three sample custom operations, mixed enabled/disabled state and all four built-ins. The minimum-height window scrolls the shared list; row controls fit the available width. Preview models and callbacks do not modify saved user data or send shortcuts. Images: `dist/ui-preview-0.8.12/floating*.png`.
- Universal Release build with warnings-as-errors and fixed local signature passed. Default APFS DMG creation stalled and was stopped; the same signed bundle was packaged using an HFS+ UDZO image. DMG checksum, mounted version 0.8.12 (24), signature, Applications link and executable/icon hashes against both the build and installed app passed. Image detached afterward. SHA-256: `28267e211875febdde84f57aa6d5e72be11ee285c9d16c7e40ceaf1bc3c75277`.
- Replaced `/Applications/Better Remote.app` after normal restore-before-exit, retaining a recoverable old bundle. Preferences and application-usage file hashes were unchanged by installation. Started the installed version and opened Settings → 悬浮球: one list shows the three existing custom rows with edit/delete/switch, followed by four built-in switch-only rows. Accessibility authorization remained granted. Live toggles, editing, deletion and remote touch were not exercised on user data.

### 0.8.12 Repackage and reinstall

- Packaging script now explicitly uses HFS+ for UDZO images to avoid the observed APFS creation stall. `./scripts/build.sh` completed end-to-end: universal Release, fixed signature and DMG checksum passed.
- Mounted version 0.8.12 (24), arm64/x86_64 architectures and executable/icon hashes matched the build. Installed directly from the mounted package after normal application shutdown, with an old-bundle backup. Installed signature and hashes matched the package; preference/usage hashes were unchanged. Mount detached.
- Started `/Applications/Better Remote.app`, opened the unified operation list and confirmed the existing custom rows, switch-only built-ins and granted accessibility state.
- Latest `dist/Better Remote-0.8.12.dmg` SHA-256: `02f23e25daf47ce47319ea7e24679cfc15826893582aaf38f7ed8fa7c13d0cf9`. This replaces the earlier package at the same path.

## 0.8.13 Compact floating controls — 2026-10-01

- Floating buttons are 80 pt with 12 pt spacing. Native circular glass uses dark appearance with light symbols and captions; labelled symbols are 28 pt, the close symbol 24 pt and the collapsed application mark 52 pt. Captions use 12 pt medium type at 85% opacity. Icon and caption are centered together.
- Operation-list switches use the small system control size. Icon backgrounds are 32 pt with 14 pt symbols; vertical row padding is 6 pt. Existing text sizes and the master floating switch are retained.
- Debug build and universal Release build with warnings-as-errors passed. No behavior or persistence code changed in this refinement; no additional tests were added.
- An isolated AppKit window containing the production button view was captured and inspected over dark and light backgrounds, including Chinese captions, an English custom name and the close control. Screenshot: `dist/ui-preview-0.8.13/floating-material.png`. Native glass was verified via a window screenshot because bitmap caching omits its bezel. Preview callbacks were inert and no user settings or display modes changed.
- `./scripts/build.sh` passed fixed local signing and DMG checksum validation. Read-only mounted package version 0.8.13 (25), arm64/x86_64 architectures, strict signature, Applications link and executable/icon hashes against the local build passed. The image was detached.
- Artifact: `dist/Better Remote-0.8.13.dmg`. SHA-256: `1d7bf42d41714b893e90e718742d309e652b527ec3597d313e689e1d8b904411`.
- Installed-app replacement, live shortcut/hold interaction, compact operation-list visual acceptance, physical remote touch and older macOS rendering were not performed. Existing local signing identity retained; no Developer ID notarization performed.

## 0.8.14 Conditional permission prompt — 2026-10-01

- Settings sidebar shows the permission status and authorization button only while accessibility permission is missing. The full permission area, including its padding, is removed when permission is granted. Existing permission monitoring drives updates.
- Debug compilation passed after the view change. Universal Release build with warnings-as-errors, fixed local signature and DMG checksum validation passed. `git diff --check` and build-script syntax checks passed.
- Read-only mounted package version 0.8.14 (26), arm64/x86_64 architectures, strict signature, Applications link and executable/icon hashes against the local build passed. The image was detached.
- Artifact: `dist/Better Remote-0.8.14.dmg`. SHA-256: `e5eba398c7d308ae8d9b14935ce6348d50ac6dc52c6d7f819a76c1644f02e76a`.
- Permission-state rendering and installed-app replacement were not performed. Application icon artwork/export is unchanged; the Finder icon-frame investigation did not introduce an icon fix. Existing local signing identity retained; no Developer ID notarization performed.

## 0.8.15 Window actions — 2026-10-02

- Added five opt-in built-ins to the existing operation list: maximize/restore, center and fit, move back to the floating control's screen, undo the latest window layout, and switch to the previous application. Existing defaults and saved enabled actions are preserved. Previous-app switching reuses the existing observed activation history.
- Native window operations resolve the focused/main window of the last external regular application, excluding the floating controls. Screen geometry uses accessibility coordinates and visible desktop bounds. Position/size writability and full-screen state are checked before mutation, and the resulting frame is read back. Partial adjustments retain a recovery snapshot. Undo targets the original window, while disconnected-display restoration fits it to a remaining visible screen. Records are kept only in memory.
- `swift test`: 45 tests, 0 failures. Eight new tests cover portrait fitting, negative display origins, offscreen and oversized windows, preserving visible-window positions, restoration to existing/disconnected displays and action preference migration. Debug warnings-as-errors and universal Release warnings-as-errors builds passed. `git diff --check` passed.
- Isolated production Settings rendering inspected at 700×950 and 640×500 in light/dark with two custom operations and all nine built-ins enabled. Full-height previews show every new row; the compact list scrolls. All builtin SF Symbols resolve. Images: `dist/ui-preview-0.8.15/`. Preview callbacks were inert, with no preference or display changes.
- An external-window harness compiled but did not run its mutation checks because its process lacked accessibility authorization (`AXIsProcessTrusted` was false). Real cross-application resize/move/undo, previous-app switching via the new button, live permission continuation, physical remote touch and older macOS behavior remain unverified. No permission changes or installed-app replacement were performed.
- `./scripts/build.sh` passed fixed local signing and DMG checksum validation. Read-only mounted version 0.8.15 (27), arm64/x86_64 architectures, strict signature, Applications link and executable/icon hashes against the local build passed. Image detached afterward.
- Artifact: `dist/Better Remote-0.8.15.dmg`. SHA-256: `5bbdecd720693970fd038f34e2a52d2834dc863ea38418f6eb258c0e46f3d6e5`. Existing local signing identity retained; no Developer ID notarization performed.

## 0.8.16 Maximize toggle, readback and native icon — 2026-10-02

- Maximize restoration is tracked independently per accessibility window identity and process. The saved original frame is no longer discarded because the current maximized frame differs from an exact target. Partially applied maximize retains its original so the next click can restore. Window actions run serially, allowing rapid repeat clicks to complete maximize then restore in order.
- Position/size readback waits up to 700 ms, sampling every 50 ms instead of rejecting a single immediate read. Resize results may be slightly smaller than requested (up to 32 pt for text-grid rounding), but larger-than-target or unchanged small windows are rejected. Restore requires the original dimensions within the normal 2 pt tolerance. The misleading `该窗口限制了位置或尺寸` message is replaced by `窗口未完成调整，请重试` only after readback fails to settle.
- Removed undo-layout and move-to-screen built-ins as requested. Legacy stored identifiers are dropped safely; remaining enabled actions are preserved. Center-window and previous-app controls remain.
- `swift test -Xswiftc -warnings-as-errors`: 50 tests passed. New regressions cover independent window originals, delayed resize readback, acceptable size rounding, true resize failure and removed-action preference migration. Universal Release warnings-as-errors build passed.
- Orca's installed main-window code sets a 600×400 minimum and includes a brief 1 pt resize/revert repaint sequence. This identifies potential constraints/timing, not the exact cause of the reported attempt. Read-only live screen/window metadata showed one 1728×1084 visible desktop and matching Orca bounds (0,33,1728,1084), confirming its current ability to fill the desktop. No user window was changed by this inspection.
- Native Icon Composer resource preserves the v4 raster artwork byte-for-byte, places it over an opaque teal background and supplies `Assets.car`, legacy ICNS and `CFBundleIconName`. Source/native exports were inspected. The mounted app rendered through `NSWorkspace.icon(forFile:)` shows the teal icon without the previous grey compatibility enclosure. Screenshot: `dist/ui-preview-0.8.16/mounted-system-icon.png`.
- Settings preview uses all seven remaining built-ins; rendered at full and compact sizes in light/dark. Preview callbacks do not modify saved preferences. Images: `dist/ui-preview-0.8.16/`.
- Live cross-application action harness remained unauthorized, including the temporary signed test build, and exited before creating a receiver or mutating any window. Actual Orca button clicks/restore remain unverified. No accessibility permissions or installed applications were changed.
- Build signing, DMG checksum, read-only mounted 0.8.16 (28), arm64/x86_64 architectures, strict signature, Applications link and executable/ICNS/asset-catalog hashes against the local build passed. Image detached. `git diff --check` passed.
- Artifact: `dist/Better Remote-0.8.16.dmg`. SHA-256: `ff3e9246c820e6ff77def6e6d04724d6d6038aa9a4c4f45d71f1aaf77a7c5121`. Existing local signing identity retained; no Developer ID notarization performed.

## 0.8.17 Native Zoom instead of manual maximize geometry — 2026-10-02

- User confirmed Orca maximizes/restores by double-clicking its titlebar, while Better Remote 0.8.16 reports incomplete geometry. The installed/running application was confirmed as `/Applications/Better Remote.app`, version 0.8.16. No previous per-window AX traces existed, so the precise failed AX value/ordering from that attempt remains unknown; the earlier timeout-only change did not establish a root-cause fix.
- Orca's installed menu definition exposes Electron's `zoom` role under its Window menu. Maximize now invokes Window > Zoom (English, Simplified Chinese and Traditional Chinese labels), falling back only to a control whose accessibility subrole explicitly identifies a Zoom button. A fullscreen control is never pressed as a replacement. The target window is raised before the command, and its application owns zoom/unzoom history.
- Completion observes a stable changed frame rather than requiring the application's native geometry to equal a calculated desktop rectangle. A uniquely identified WindowServer window is preferred for readback, with AX readback as fallback. The three-sample settlement check handles animation and restoration. Manual geometry setting remains for center-window only.
- Added rotating `WindowActions.log` with application identifier, window identity, command return values and before/after geometry. It does not log window titles or document content. This allows future failures to be investigated using the actual request instead of interpreting a generic alert.
- `swift test -Xswiftc -warnings-as-errors`: 51 tests passed, including native animation settlement and native restoration without custom frame history. Debug and universal Release warnings-as-errors builds passed. Actual Orca menu invocation and double-toggle through the installed app remain unverified because this session's automation/helper process lacks accessibility access. No permissions or installed app were changed.
- Fixed signature and DMG checksum passed. Read-only mounted 0.8.17 (29), arm64/x86_64 architectures, strict signature, executable/ICNS/Assets.car hashes and Applications link passed. Image detached. `git diff --check` passed.
- Artifact: `dist/Better Remote-0.8.17.dmg`. SHA-256: `51abb284afe9c9ba3a73c97cc288326badef94c88999749d2527610c235168af`.

## 0.8.18 Unified drag ordering and quieter actions — 2026-10-02

- Added a shared operation ordering for custom shortcuts and built-ins, using namespaced stable IDs. Settings uses a native reorderable List with row grips. A completed move is saved atomically before publishing the new preferences and rebuilding floating buttons. Disabled operations keep their positions; rename preserves identity; new operations append; deleted/unknown/duplicate stored IDs are handled safely. Legacy preferences without ordering retain their previous settings-list order.
- Floating controls use the same resolved ordering as Settings, filtered only by enablement. Each expanded column reads top to bottom in list order. Prefixing panel identifiers also prevents custom IDs from colliding with built-in IDs, and shortcut pressed/released state resolves the new identifiers.
- Renamed `摆正窗口` to `窗口居中`, retaining its saved action identifier. Previous-application action now silently returns when no target exists, without a dismissible alert.
- `swift test -Xswiftc -warnings-as-errors`: 58 tests passed. Seven new regressions cover legacy order, mixed moves and reload, disabled-slot retention, rename/add, deleted/unknown/duplicate IDs, identifier collisions and multiple-row movement.
- Isolated native floating-switcher harness passed: visible panel identifiers sorted top-to-bottom matched the configured mixed list; live reconfiguration and disabling an item preserved expected order; synthetic multi-column placement produced unique positions in top-to-bottom order. The harness used inert operation callbacks, did not send shortcuts or change user preferences, and hid its temporary panels afterward.
- Settings previews generated at 700×950 and 640×500 in light/dark. Full light and compact dark renders inspected: row grips, renamed action, switches and edit/delete controls fit; the native list scrolls below its fixed header. Images: `dist/ui-preview-0.8.18/`. Actual mouse/phone drag gestures and autoscroll were not exercised through the installed app; previous native-window limitations still apply.
- Universal Release warnings-as-errors build, fixed signature and DMG checksum passed. Read-only mounted 0.8.18 (30), arm64/x86_64 architectures, strict signature, executable/ICNS/Assets.car hashes and Applications link passed; image detached. Installed application was not replaced.
- Artifact: `dist/Better Remote-0.8.18.dmg`. SHA-256: `d9079d8aff8732fe6e6af7b417db6145f7bd03f0ac2aed54b0ca2528b9bd6564`.

## 0.8.19 Desktop toolbar and companion panels — 2026-10-02

- Replaced separate floating-circle windows with one right-edge toolbar: 36×56 collapsed handle, 72 pt expanded strip, vertically draggable grip and a bottom collapse control. Ordered shortcuts retain synchronous press/release callbacks; overflow scrolls inside the strip. Native glass, SF Symbols and short captions provide a dark utility surface.
- Applications and resolution open 340 pt companion panels to the left, constrained to the visible screen. Repeating an entry closes its panel. Collapse, outside clicks, display changes, disabling and external app activation dismiss companion panels. The toolbar remains available while a panel is open. Settings labels now say 工具条; stored preference keys remain compatible.
- Compact application view keeps search/categories and a three-column icon grid. Resolution view keeps presets and percentage choices in a scrollable compact grid, with a fixed management button. Panels are nonactivating/key-capable and do not become the application's main window; showing them no longer explicitly activates Better Remote. Search is not automatically focused.
- `swift test -Xswiftc -warnings-as-errors`: 62 tests passed. Four new layout tests cover collapsed placement, overflowing tools on short screens, companion placement on portrait screens and negative display coordinates. Universal Release warnings-as-errors build passed.
- Isolated native harness verified collapsed/expanded widths, sorted button identifiers, companion placement, repeated-entry dismissal and collapsing with an open panel. Initial screenshot attempts failed; after the corrected preview lifecycle, actual WindowServer captures succeeded for collapsed handle, toolbar, resolution, applications and the combined toolbar/resolution layout. All were visually inspected; resolution contrast was increased before the final captures. Images: `dist/ui-preview-0.8.19/`. Fixture resolution actions were inert and did not change displays.
- Fixed local signature and DMG checksum passed. Mounted 0.8.19 (31), arm64/x86_64 architectures and executable/ICNS/Assets.car hashes matched the build. Designated signing requirement matched the existing installation.
- At the user's request, normally terminated installed 0.8.17, waited for restore-before-exit and removal of the display session snapshot, preserved the old app at `~/Library/Application Support/RemoteFit/Backups/Better Remote-0.8.17-20261002-101612.app`, and installed from the read-only mounted package. Installed strict signature and file hashes matched. The image was detached.
- Native UI automation service failed to start, so the installed app was launched with the system application launcher. Confirmed exactly one process running `/Applications/Better Remote.app/Contents/MacOS/BetterRemote`, version 0.8.19. Preferences and application-usage file hashes were unchanged after launch. WindowServer metadata confirmed a visible 72×722 toolbar and adjacent 340×560 companion panel with an 8 pt gap. Real phone dragging/typing and remote keyboard delivery remain user acceptance items.
- Artifact: `dist/Better Remote-0.8.19.dmg`. SHA-256: `1fbdbfe035f16834acc2643eb7bef4ce3dce634f6d8351f52984d8ccdac4aa73`.

## 0.8.20 Multi-column toolbar and adaptive applications — 2026-10-02

- Latest user direction supersedes the proposed window submenu: maximize and center remain direct toolbar controls. No window-group action or migration was retained.
- Toolbar expands horizontally into balanced columns when one column cannot fit the visible screen. It preserves configured order down each column, left to right. Removed its scroll view entirely; previous/next-page controls are shown only if the entire screen capacity is exceeded. Item hit areas remain 56×58 pt.
- Applications resize by the selected category's unfiltered count, using 48 pt icons and 104 pt minimum tile height. Small categories use a moderate panel; larger categories grow horizontally. If side-by-side placement would require scrolling, the panel may use full screen width and retains its close control. Query text does not resize the panel, preventing search-field movement while typing.
- `swift test -Xswiftc -warnings-as-errors`: 66 tests passed, including balanced two-column placement, screen-capacity pagination, adaptive application dimensions, full-width fallback and empty/large collections on offset displays. Universal Release warnings-as-errors build passed.
- Native harness and actual WindowServer captures passed for a 136×402 two-column toolbar, direct window actions, panel toggling, category resize and stable search bounds. On a 1280×690 visible desktop, all 27 running apps were visible in a 1144×564 panel without scrolling; switching to Common produced a 772×564 panel for 16 apps. Toolbar and application captures visually inspected. Images: `dist/ui-preview-0.8.20/`. Fixture callbacks did not send shortcut keys or change display modes.
- Continued the user's authorized update/install workflow: normally exited 0.8.19, confirmed display restoration completed, backed up the old bundle to `~/Library/Application Support/RemoteFit/Backups/Better Remote-0.8.19-20261002-103704.app`, and installed the read-only mounted package. Fixed signing requirement matched; strict signatures, architectures, executable/ICNS/Assets.car hashes and Applications link passed. Mount detached.
- Confirmed one running process at `/Applications/Better Remote.app/Contents/MacOS/BetterRemote`, version 0.8.20 (32). Preferences and usage hashes were preserved after launch. Real phone dragging, tapping and keyboard delivery remain user acceptance items.
- Artifact: `dist/Better Remote-0.8.20.dmg`. SHA-256: `84c484a3e843da84aa8403b520c82a2df3a809f942b9f7c54544da88a9fe8016`.

## 0.8.21 Full-height columns and full left-area applications — 2026-10-02

- Multi-column toolbar surfaces now span the visible screen height with 8 pt top/bottom margins. Buttons retain their original dimensions and compact spacing; the collapse control stays at the bottom. Single-column and collapsed-handle placement remain movable.
- Application panel always fills the entire available rectangle to the left of the toolbar, with 8 pt outer margins and an 8 pt inter-panel gap. Removed count/category-driven resizing and toolbar-overlapping fallback. Category and search changes retain the same panel bounds. Slightly tightened grid vertical spacing so four rows fit the short-screen panel.
- `swift test -Xswiftc -warnings-as-errors`: 66 tests passed. Updated geometry regressions check full-height columns independent of drag center, full left-area occupancy, no toolbar overlap and offset-screen coordinates. Universal Release warnings-as-errors build passed.
- Native harness and actual WindowServer captures verified a 136×674 toolbar and 1120×674 application panel on a 1280×690 visible desktop, both starting at y=8. Running/Common/search retained identical panel frames. Direct actions, repeat-entry dismissal and collapse checks passed. Final compact-spacing toolbar and application images inspected in `dist/ui-preview-0.8.21/`.
- Continued the authorized installation workflow: normal restore-before-exit, backup of 0.8.20 at `~/Library/Application Support/RemoteFit/Backups/Better Remote-0.8.20-20261002-110722.app`, then replacement from the read-only mounted DMG. Signature identity, strict signatures, universal architectures and executable/ICNS/Assets.car hashes passed; mount detached.
- Started installed 0.8.21 (33), confirmed a single matching executable process, and verified preference/usage hashes unchanged after launch. Physical phone gesture acceptance remains with the user.
- Artifact: `dist/Better Remote-0.8.21.dmg`. SHA-256: `cf3ffb5800190a191897f7744636953309a3a5ec56baca610f7565d3e0fcf98c`.

## 0.8.22 Persistent footer, larger handle, layout-left mode — 2026-10-02

- UI is named 快捷操作; the new configurable action is 布局左侧. Expanded single/multi-column panels fill the visible height; collapsed handle is 64×80 pt. Settings/restore/collapse are always in a separated footer; settings/restore are excluded from saved configurable ordering.
- Layout-left persists until toggled off. It fills the initial focused standard window and fits other visible apps to the left of the expanded toolbar footprint (also retained while collapsed). AX window notifications and a 200 ms fallback check cover create/focus/move/resize. Filters are removed on disable/exit; failed input-tap creation disables the mode and reports a permissions status rather than showing a successful toggle.
- Active Quartz session event filtering constrains native-titlebar moves/right-edge resizes before event delivery. Custom titlebars are constrained once an actual translated window frame is observed; content gestures are not intentionally constrained. Mouse-up and timeout cleanup restore normal input. All pointer geometry uses Quartz coordinates, including negative-origin displays.
- This is NOT a system-wide reserved work area. Custom-titlebar first motion and native zoom animation can transiently overlap; fullscreen, oversized minimum-size windows, apps rejecting AX geometry, and remote software bypassing the session input stream are not guaranteed. No claim of a universal hard boundary. Cross-app/phone input acceptance remains unverified because the helper process lacks AX trust; no permissions or system protections were changed.
- Maximize uses native zoom plus geometry fallback, restores saved bounds per window, chooses the window's display, and constrains maximize/restore/center within the left area when enabled. Temporary AXEnhancedUserInterface changes restore their original value; VoiceOver/SwitchControl are respected.
- 77 warnings-as-errors Swift tests passed, including six drag-boundary tests (single-event overshoot, return from the edge, other edges, right-resize/shrink, negative display origins, oversized windows). A lifecycle review fixed a canceled-task reference that could block re-enabling the mode.
- Native fixture verified the 64×80 handle, 136×1068 expanded panel, 1568×1068 left app panel, category/search stability, ordered actions and fixed footer dispatch even with an empty operation list. Actual WindowServer captures succeeded in dist/ui-preview-0.8.22; toolbar and collapsed images inspected. Fixture callbacks were inert.
- Universal Release build, fixed signature, mounted package version 0.8.22 (34), arm64/x86_64, application hashes and Applications symlink passed. Designated requirement matches the installed app. DMG SHA-256: `42602a6da384c5c0468367163ff20120928c0764fde73e70b07446a22f7b28ae`. Package delivered without replacing the current running installation in this turn.

## 0.8.24 Placement selector, persistent parallel mode, flush height — 2026-10-02

- Bottom persistent action is 并排模式; removed from configurable actions/order. Preserves mode preference independent of old floatingActions flags. Footer highlights enabled mode.
- Enabling 显示快捷操作 reveals 位置 with 左侧/右侧 choices. Right is the legacy/default value; selection persists. Collapsed/expanded placement, collapse/expand arrows, application/resolution companion side, reserved region and left-edge resize constraints follow the selected side. Changing side dismisses existing panels.
- Expanded toolbar and application panel now exactly match visibleFrame top/bottom (removed 8 pt vertical gaps), preserving menu bar/Dock space. Horizontal margins and collapsed handle remain unchanged.
- 80 warnings-as-errors tests passed. Native inert fixture verified bottom dispatch with zero configurable operations, both sides and full-height geometry. WindowServer captures show 136×1084 strips at x=1584 and x=8, y=0; app panels use the full remaining width and identical height. Left toolbar image inspected. Fullscreen/custom-window limitations from 0.8.22 still apply; no new claim of phone gesture acceptance.
- Universal Release, mounted version/build, strict signature and content hashes verified. DMG SHA-256: `6c3be9aa63e005f3ac2e72b3c7e1af26e2dfaeac27ce8c7786e3a6a51de62850`. No overwrite installation this turn.

## 0.8.25 Restore snapshots and expanded-only parallel mode — 2026-10-02

- Actual WindowActions.log showed Orca repeatedly targeting its existing 1640×1084 workspace rectangle, including after a manually smaller 864×813 frame. Code could retain a no-op/stale restore record and initial workspace fill did not save the previous frame.
- Restore entries now track original and applied rectangles. Changed current geometry invalidates stale records; no-op maximization is not saved. Workspace initial fill records the prior frame; already-filled windows with no history request native unzoom. Five regression tests cover restore position/size, no-op, manual resize/move and initial workspace fill. 85 warnings-as-errors tests passed. Cross-app phone reproduction after installation remains unverified.
- Persistent bottom parallel control is icon-only; tooltip and accessibility name remain. Expanded-state callbacks immediately update the controller; effective mode and region require both saved opt-in and expanded/visible toolbar. Collapse stops event filtering/observers/adjustments without clearing the preference. Re-expansion resumes.
- Native inert fixture verified icon-only footer, expansion callback states [false,true,false], both-side panel placement and collapse. Screenshot inspected. Universal Release and mounted bundle hashes/signature/version passed. DMG SHA-256: `14e5978d6989a9f7c993a0e4600e37bc2b0262275b1687bd6d2f077d007fd639`. No installation performed in this turn.

## 0.8.26 Adaptive persistent footer — 2026-10-02

- Fixed actions use 56×44 pt cells, up to four columns: one-column toolbar keeps vertical buttons; wider toolbars use row-major footer cells without stretching. Footer height follows actual row count; primary capacity recomputes for each candidate width to reclaim space. Pagination joins the same grid when needed.
- 85 tests passed; native inert fixture verified four fixed buttons in two rows/two columns at width 136, all widths 56, left/right surfaces, footer actions and expansion lifecycle. Actual screenshot inspected. Universal Release and mounted bundle signature/version/content checks passed. No install this turn. DMG SHA-256: `5820f0157be94450100925cce50fd373cf1573021c31ee82aad59eb9ffdebbbc`.

## 0.8.27 Scroll direction pad — 2026-10-02

- Bottom cross has 44×44 up/left/right/down controls and central target picker. Minimum expanded width is 152 pt/two operation columns. Wide footers place the pad beside fixed controls; narrower footers stack the fixed grid below it.
- Nonactivating panel and non-focusable buttons retain existing input focus. Pixel scroll events carry a recorded window-relative location and go to that window's process; no cursor warp, synthetic click or application activation is used for scrolling. Press sends one step and starts a 30 Hz common-mode timer; release, leaving the button, collapse, rebuild, disable, lost mouse-button state or invalid target stops it.
- Passive position sampling remembers the last eligible foreground-window position outside our windows. Explicit center selection uses an active tap to swallow both down/up of the next selection click, locking the target without selecting editor content. Repeat center/right click/15-second timeout cancels selection. Switching applications clears the target; movement follows the recorded window offset; hidden/occluded/dead targets are not scrolled.
- 85 warnings-as-errors tests passed. Native inert fixture checked all five pad hit rectangles, no overlap with fixed controls, both sides, and generated CGEvent point/direction/empty modifiers. Event construction left cursor and responder unchanged; screenshots inspected.
- A separate native two-scroll-view routing probe had AXIsProcessTrusted=false and neither scroll view moved after postToPid. This does NOT establish successful dispatch: real cross-process scroll delivery and continuous phone hold remain unverified until run in the authorized installed app. No TCC or system protection changes were made.
- Universal Release, mounted 0.8.27 (39), strict signature and content hash checks passed. DMG SHA-256: `5997ff7dd68717e5cb45f061841fb4b2a6ef74e38d349054dbc4078d2cfec117`. No installation performed.

## 0.8.28 Remove scroll direction pad — 2026-10-02

- User canceled the feature after actual use. Deleted ScrollPadController, direction/target buttons, callbacks, scroll repeat timer, target sampling and selection interception. No direction-pad preferences had been persisted. Retained the independent window-boundary event tap used by parallel mode.
- Restored pre-pad toolbar sizing: single-column minimum 72 pt, fixed footer grid up to four columns and dynamic footer height. Existing left/right placement, expanded-only parallel mode, maximize snapshots and full-height surfaces remain.
- 85 warnings-as-errors tests passed. Universal Release, mounted 0.8.28 (40), strict signature, bundle hashes and absence of ScrollPadController symbols verified. DMG SHA-256: `0d7ef7f7b282adeb9bb5a94dd758a28a46a623599b495664acd029b3b7292044`. No installation performed.

## 0.8.29 Full-area resolution panel — 2026-10-02

- Resolution panel shares expanded-panel geometry with the application list: all available width on the inward side of the toolbar, full visibleFrame height, with the existing horizontal gap. Both initial presentation and visible-panel updates use the same geometry and side preference.
- Preset tiles adapt to available width (140–180 pt); scale choices use 100–150 pt cells. Management stays a compact 140×44 footer control instead of stretching across the screen. Scroll remains available for collections exceeding the full area.
- Retains 0.8.28 removal of direction pad/target picker/scroll monitoring. 85 tests passed. Native fixture checked full-area bounds with 24 presets, footer/left-right interactions and captures; resolution screenshot inspected.
- Universal Release, mounted 0.8.29 (41), strict signature, content hashes and absence of ScrollPadController symbols verified. DMG SHA-256: `03e87929ab009399ba51602d06abfdfea4b60a280631d95bfc893cb74461aef5`. No installation this turn.

## 0.8.30 Icon-only restore and collapsed entry — 2026-10-02

- User rejected footer captions; fixed controls remain icon-only. Restore now combines the display and return-arrow symbols, retaining tooltip/accessibility label 还原屏幕. Collapse keeps the direction-aware chevron with tooltip; collapsed entry uses macbook.and.iphone on both sides.
- Carries direction-pad removal and full-area adaptive resolution panel from 0.8.28/29. 85 tests passed; native fixture passed and actual collapsed/empty-toolbar captures inspected. Universal Release and mounted version/build/signature/content checks passed. DMG SHA-256: `244468760e4c197432c23487dae359c865dff86e46fccfcb8a71f85e243f4be8`. No overwrite installation this turn.

## 0.8.31 Restore icon simplification — 2026-10-02

- Per explicit correction, restore uses the single arrow.clockwise refresh symbol without a caption; removed the composite display/return drawing. Tooltip/action remain restore-screen. Collapsed entry remains macbook.and.iphone.
- Icon-only change: no additional test suite run. Universal warnings-as-errors Release, DMG verification, mounted version/signature/architectures and executable match passed. SHA-256: `74fca01f942182ce8d83ee42d12eb87b3b4ee686eb945b3196ec97ca6e92636e`. Not installed this turn.
# 0.8.33 UI tidy and sidebar branding — 2026-10-03

- Moved preset management beside the preset section, removed duplicate ratios and footer copy, enlarged resolution close/scale hit areas to 44 pt, and removed the duplicate add-preset row. Maintenance icons retain their hit areas with quieter styling; empty preset groups hide their border.
- Logo appears only above the settings sidebar navigation. Removed the right-side images from General and About.
- Warnings-as-errors Universal Release built; fixed signing identity and strict signature verified. DMG checksum verification passed.
- Gracefully exited the previous application, replaced `/Applications/Better Remote.app` with 0.8.33 (46), and launched it. Installed executable matches the build; exactly one installed-path process was observed.
- Inspected installed Resolution, General, and About pages; sidebar logo visible and no right-side logo. Accessibility permission remained enabled. Native preview additionally covered wide/narrow panels, selected states, the management entry, and empty presets. No live display switching or shortcut sending performed this turn.
- Screenshots and review notes: `DesignExploration/review-20261003/`.
- Follow-up build 47 centers the logo horizontally within the 160 pt sidebar. Universal build/signature/DMG verification passed; overwritten installation was launched and the installed settings screenshot confirmed centering. Exactly one installed-path process observed and executable matched the build.

## 0.8.34 Half-width panels and recent apps — 2026-10-03

- App and resolution panels use half of the inward available width, anchored 8 pt beside the toolbar on either side. Full available height is retained.
- Workspace activation notifications record bundle identifiers in newest-first order, persisted separately from usage counts. The default Recent view shows up to 16 installed apps; consecutive ranks fill the nearest column top to bottom before moving inward. Right/left layouts mirror, and small collections remain beside the toolbar.
- Removed About page, menu entry and General brand card. Version appears at the bottom of the settings sidebar; logo remains centered above navigation.
- 93 warnings-as-errors tests passed. Universal Release, strict fixed signature and DMG verification passed. Installed 0.8.34 (48), launched and confirmed installed executable matched the build.
- Native screenshots inspected for 16-app right/left fixtures and actual installed half-width resolution/app panels. Actual Chrome → Finder selections updated recent order, JSON readback matched, and the order remained after normal exit/relaunch. No-result search recovered via Clear. Installed sidebar version footer inspected.
- One independent screenshot review found no significant visible layout issues; main Agent performed the actual task walkthrough. No physical-phone reach test or live resolution-switch/shortcut test was performed. Evidence: `DesignExploration/single-hand-20261003/`.

## 0.8.35 Edge category rail and previous-app removal — 2026-10-03

- Recent/Running/All categories form a fixed 76 pt rail beside the toolbar side, with 64 pt buttons. App ordering mirrors the toolbar position; panel width remains half of inward available space. Narrow panels use compact search and omit counts.
- Category/query/presentation changes reset list scrolling. Installed category selection and native scrolling were exercised; switching back to Recent restored the top.
- Removed previousApplication enum/action/dispatch/switch methods and UI entry. Legacy preferences drop the removed action, icon and ordering ID without discarding custom shortcuts or other operations. Added migration coverage; 94 warnings-as-errors tests passed.
- Universal Release, fixed signature and DMG checks passed. Installed and launched 0.8.35 (49); installed executable matched build and exactly one installed process was observed.
- Independent screenshot review covered left/right 560×690 pt fixtures and a 208 pt narrow panel with no major issues. Installed 816×1084 pt panel and settings action list inspected: previous app absent, other enabled actions/shortcuts preserved. Evidence: `DesignExploration/category-rail-20261003/`.

## 0.8.36 Vertical labels and icon-only grid — 2026-10-03

- Category labels stack characters vertically; rail narrows to 52 pt with 44×88 pt hit areas and intact accessibility labels. App tiles show only 40 pt icons, with names retained in hover/accessibility metadata. Cells are 64–68×64 pt with 8 pt gaps; layout metrics are shared with grid calculation.
- Four relevant grid tests passed, including compact viewport capacity, hit-area dimensions, mirrored order and partial/narrow columns. Universal Release, fixed signature and DMG verification passed.
- Installed and launched 0.8.36 (50), confirming binary matches the build and a single installed process runs. Inspected left/right 560×690 pt and 208 pt narrow fixtures, and installed 816×1084 pt Recent/All views. Clicked the Chrome icon; panel closed and Chrome became first in Recent on reopening.
- One independent static review found no significant issues. Actual click verification by main Agent; no phone reach, animation or independent interaction review. Evidence: `DesignExploration/icon-grid-20261003/`.
- Pre-commit full warnings-as-errors suite passed: 95 tests, 0 failures. Build script syntax and Git whitespace checks passed. DesignExploration screenshots and drafts remain local review artifacts outside the source commit.

## 0.8.37 Height-limited application columns and flexible tiles — 2026-10-04

- App columns fill the available height from top to bottom, starting beside the toolbar and moving inward. The panel grows beyond its usual half width when required, stays inside the visible screen, and uses pages when the whole inward area cannot hold the collection. Removed vertical scrolling. Category/search/presentation changes reset the page; error and viewport changes recompute capacity.
- App tiles keep a 64 pt minimum width and 64 pt height; removed the 68 pt width ceiling so each tile fills its allocated column. Icons remain 40 pt. Resolution cards are unchanged.
- 100 warnings-as-errors tests passed, covering full-height ordering, mirrored columns, elastic width, narrow-screen pagination, complete page coverage and panel expansion. Git whitespace and build-script syntax checks passed.
- Native fixtures covered both sides at 560×690, two apps at 816×1084, 70 apps at 816×690 and 100 apps at 352×512. Native hit-view frames stayed within the panel, with widths of 64 pt, approximately 147 pt and 712 pt as appropriate; no NSScrollView was present. Synthetic window clicks advanced the narrow fixture to page 2, selected its first app, then searched and selected the final app. These were inert fixtures, not real app launches. Cached view bitmaps were inspected for layout; WindowServer capture was unavailable, so installed visual and physical-phone acceptance remain unverified. No independent review was run for this local change. Evidence: `DesignExploration/adaptive-apps-20261004/`.
- Rebuilt Universal Release, fixed signature and DMG checksum verification passed. Gracefully exited 0.8.36 via its restore-before-exit signal handler, replaced `/Applications/Better Remote.app`, and launched 0.8.37 (51). Strict installed signature and executable equality with the build passed; exactly one installed-path process was observed. Previous app retained in a temporary recovery backup. DMG SHA-256: `796d323c19e57eeac08bbedbdb287af4d8688f2f936c371dc9f1f06fb3ca5c19`.

## 0.8.38 Category contrast and consistent compact columns — 2026-10-04

- Replaced application-panel primary/system control colors with explicit light foregrounds and translucent white surfaces for the existing dark panel. Selected Recent/Running/All labels and counts now retain clear contrast. Header, search, empty state and pagination use the same foreground palette.
- Removed width sharing among occupied columns. App tiles are consistently 64×64 pt with 8 pt column gaps (72 pt between icon centers), independent of category, count or available width. Unused space stays on the outer side. Height-limited inward ordering, panel expansion and overflow pages remain.
- 100 warnings-as-errors tests passed; updated regression covers identical column width for 2/16/70/200 apps across four viewport widths. Native fixtures verified 64 pt hit widths, 72 pt column offsets, screen containment and no scrolling for Recent/Running/All and both toolbar sides. Inspected cached native previews for selected labels and two-column versus six-column spacing. Narrow fixture page/search/selection clicks passed. No independent review or live installed screenshot was performed. Evidence: `DesignExploration/compact-apps-20261004/`.
- Universal Release, fixed signature and DMG verification passed. Gracefully exited 0.8.37, retained a temporary backup, and installed/launched 0.8.38 (52). Strict installed signature, executable equality and exactly one installed-path process verified. DMG SHA-256: `2a46f746b07b89765c17fd94345be9be242b065c9a8abb6954a23fdef016f49d`.


## 0.8.39 Four-edge docking and anchored expansion — 2026-10-05

- Added top/bottom alongside left/right with legacy right default and Codable compatibility. Left/right toolbars expand vertically around the ball's Y coordinate; top/bottom expand horizontally around its X coordinate, clamp within the visible screen and paginate. Drag axis and collapse arrow follow the selected edge. Companion panels open inward, and workspace reservation converts the resulting AppKit region to accessibility coordinates.
- Added 6 pt transparent window padding while preserving the 52 pt visible ball. Logical toolbar frames exclude padding. Existing animations respect Reduce Motion. Application categories are horizontal for top/bottom docking; vertical categories and existing compact application tiles remain for left/right.
- 105 warnings-as-errors tests passed, covering preference migration, four-edge anchors, compact sizing, clamping, offset/portrait screens, paging, inward panel/workspace containment and horizontal application-panel chrome. Universal Release, fixed signature and DMG checksum verification passed for 0.8.39 (53).
- Native fixtures using current production views were inspected for all four expanded positions, the collapsed ball, a 640×580 pt settings window and the upper application panel. All toolbar button frames were inside their window. Native clicks verified collapse/reopen and top/bottom settings selection. Coordinate drag attempts did not produce observable movement in the automation environment; physical dragging and phone touch acceptance remain unverified. No independent review was run for this localized change. Evidence: `DesignExploration/four-edge-dock-20261005/`.
- Generated `dist/Better Remote-0.8.39.dmg`. At the user's request, gracefully terminated the installed app, retained a temporary 0.8.38 backup, replaced `/Applications/Better Remote.app` and relaunched 0.8.39 (53). Installed signature, binary equality and a single installed-path process passed. Initial-launch visual inspection revealed an autoresizing mismatch; replaced glass autoresizing with constraints that enforce the 6 pt inset and laid out after setting the final window frame, then rebuilt the universal package and reinstalled. Installed initial ball, expanded toolbar and collapse/reopen were visually verified. Evidence includes `installed-initial-ball.png` and `installed-expanded.png`.


## 0.8.40 Automatic toolbar workspace reservation — 2026-10-05

- Workspace avoidance now follows toolbar visibility/expansion automatically, with the existing Accessibility requirement and suspension during display changes/termination. Removed the workspace toggle action and persistent button, leaving Settings/Restore/Collapse. Legacy `leftWorkspaceEnabled` is ignored and no longer encoded; stale action IDs/icons/order entries are removed during migration.
- Closing or hiding the toolbar stops avoidance and preserves current window geometry, as explicitly requested. No automatic layout restoration was added. Existing four-edge inward workspace geometry remains.
- 106 warnings-as-errors tests passed, including legacy enabled/disabled migration and footer sizing without the removed control. Universal Release, fixed signature and DMG checksum verification passed for 0.8.40 (54).
- Installed and launched 0.8.40 (54) with a recoverable 0.8.39 backup. Strict installed signature, binary equality and one installed-path process passed. Installed toolbar screenshot/AX tree showed exactly Settings/Restore/Collapse in the fixed area.
- Native regular-window fixture verified automatic right-edge reservation: 1728 pt desktop width became a 1640 pt window, and after a live display-size change a 1252 pt desktop width had a 1164 pt window. Collapse preserved the 1164×1126 pt geometry unchanged. A fresh window after collapse stayed at the full 1252×1126 pt visible desktop size across multiple timer ticks, confirming release. No real user documents or preferences were changed by the fixture. Left/top/bottom workspace geometry remains covered by core tests; no phone gesture or independent review was run. Evidence: `DesignExploration/automatic-workspace-20261005/`.
## 0.8.41 Restore-screen icon — 2026-10-05

- Restore uses the native `arrow.uturn.backward.circle` symbol instead of circular refresh/sync arrows. Tooltip/accessibility label remains 还原屏幕; restoration behavior is unchanged.
- Confirmed the symbol exists on the running system. Universal warnings-as-errors Release, strict fixed signing and DMG verification passed. Overwritten installation of 0.8.41 (55) was launched; actual toolbar screenshot inspected at `/tmp/remotefit-reset-icon/installed-toolbar.png`.
- Small icon-only change: no new tests or independent visual review. Restore action was not invoked during visual verification.
- Repackage before local commit: all 106 warnings-as-errors tests passed. Fresh DMG checksum verification and read-only mounted checks passed for version/build, arm64+x86_64, strict signature, executable/resource equality and the Applications shortcut. DMG SHA-256: `90fd689a0d54fe4c00b23845a4ce54353819c4274cf37c7759fc065530fbfd13`.


## 0.8.42 Readable glass surfaces and focused shortcut editor — 2026-10-06

- Added a rounded translucent dark content backdrop to the shared floating glass surfaces while retaining the visible ball's existing appearance. Increased secondary-text contrast and rendered the application-search hint explicitly, with hit testing/accessibility disabled only on the visual hint; the actual editable search field retains its accessibility label.
- Application panels capture their current size at the beginning of a nonblank search. Result counts and live application updates keep that extent; clearing, hiding and reopening release it. Geometry clamps to changed screen/toolbar space on all four docking edges.
- Shortcut editing now presents Name → Keys → optional Icon. The current icon remains visible, More/Change exposes the existing grid, and selection returns to the compact form while preserving fields and explicit icon choices. Removed redundant current-icon preview and shortened More/Search/empty copy. Reduce Motion is respected. Existing save and shortcut execution paths are unchanged. Spec/custom-operation edit/delete hit regions are 44×44 pt.
- 108 warnings-as-errors tests passed, including search extents across result counts/edges and changed offset displays. Universal Release, fixed signature and DMG checksum verification passed for 0.8.42 (56). Installed signature, binary equality and exactly one installed-path process verified; 0.8.41 backup retained before replacement.
- Actual installed UI inspected for toolbar, ball, recent/all/single/no-result application views, specification and operation settings, and compact/expanded/scrolled/configured editor states. Search captures for all/single/no results were identically 2496×2100 px. Native actions verified clear/recovery, icon expansion/scroll/selection/collapse, name and key/modifier configuration with Save becoming enabled, and Cancel without adding the UI检查 draft. No real shortcut was sent or test record saved. Installed ball outline remains intact.
- One independent current-only visual review found no obvious layout/readability/entry-state problems; it noted that the inactive resolution screenshot shows no selected scale. That is the existing applied-state rule (`model.applied` is nil after shutdown/restoration), so no stored-but-unapplied value was presented as active. Selected-scale behavior was not revalidated by applying a real display change. No phone gesture, compressed remote-stream contrast, Intel runtime or animation intermediate-frame acceptance is claimed. Evidence: `DesignExploration/oil-ui-polish-20261006/`.


## 0.8.43 Full-span toolbar edges — 2026-10-06

- Per the user's latest correction, expanded left/right toolbars span the complete visible-desktop height; expanded top/bottom toolbars span the complete visible-desktop width. The primary-axis margin is removed for expansion, while existing perpendicular docking margin, button metrics, grid capacity/paging, fixed footer and collapsed-ball anchors remain.
- 108 warnings-as-errors tests passed. Replaced content-height expectations with full-edge regression coverage for all four edges, offset/portrait displays, multiple action counts and arbitrary collapsed anchors. Existing search-clamping, companion panels and workspace tests also passed.
- Native current-source fixture measured actual toolbar view/window frames against the 1728×1050 pt visible desktop: left/right logical toolbar height 1050 pt at minY=0, top/bottom width 1728 pt at minX=0. All visible toolbar button frames remained inside their window. Cached native right/top renders were visually inspected for layout. These cached images do not reproduce the full system-glass compositor or constitute live desktop screenshots.
- Live screenshot selection failed repeatedly with `cgWindowNotFound`, including after reconnecting. Current installed process and visible-window metadata were readable, but no live expanded-toolbar screenshot or animation/physical-phone acceptance is claimed. Evidence: `DesignExploration/full-span-toolbar-20261006/`.
- Universal Release, fixed signature and DMG checksum verification passed. Backed up 0.8.42, gracefully exited it, replaced `/Applications/Better Remote.app` and restarted 0.8.43 (57). Installed strict signature, executable equality and exactly one installed-path process passed.

## Shortcut investigation — 2026-10-07

- The user intentionally uses Tinycast Beta for ⌘Space. Its saved global binding is key code 49 with Carbon Command modifier 256; system Spotlight shortcuts 64/65 are disabled. Disabled Spotlight alone does not explain a third-party launcher failing to open.
- A temporary signed current-source probe, launched normally through LaunchServices, verified Accessibility and event-posting permissions, recorded only Command/Space events at HID/session taps, and clicked the existing installed 0.8.43 toolbar. No system shortcuts or saved application preferences were edited.
- Installed-button tests with 0/1/5/20/80/400 ms mouse-down intervals all opened Tinycast's 750×475 palette, still visible at 250 and 700 ms. Another test opening Better Remote Settings first also successfully opened the palette after returning focus to the previous app. Event captures showed complete Command-down, Space-down, Space-up, Command-up sequences from the installed process.
- One initial direct probe send did not expose the palette; subsequent direct sends and installed-button tests worked. The reported intermittent failure was not reproduced sufficiently to identify its cause, so no speculative production fix or installation replacement was made. Temporary probe source was removed, probe-created Settings/palette windows were closed, and the original source entry point was restored. Diagnostic evidence: `/tmp/remotefit-shortcut-check/`.

## 0.8.44 Remote shortcut compatibility — 2026-10-07

- Subsequent user evidence narrowed the failure to clicks made through ToDesk; WuJie remote clicks work. `CGGetEventTapList` showed enabled ToDesk Session interceptors for keyboard events at the session layer. This identifies an input-chain compatibility concern, but does not alone prove which interceptor causes the reported failure.
- Ordinary single-press actions now send a complete key-down/up cycle on a completed click. They use `combinedSessionState` and `cgSessionEventTap`, matching the login-session input path documented in the Apple CoreGraphics SDK. Modifier-only gestures retain HID delivery, and other stored modes retain their existing mouse-down/release behavior. The event source and delivery location are retained through release, including cancellation/app-switch cleanup.
- Current-source native toolbar tests using session-injected mouse clicks at 0/1/5/20/80/400 ms all opened Tinycast Beta; the palette remained visible at 250 and 700 ms. The probe waits for the toolbar's expansion animation before measuring its button: an initial fixture run sampled the moving button too early and missed it; this was a fixture timing error, not a shortcut failure.
- A native AppKit receiver confirmed ⌘C, ⌘V and Return produce complete down/up pairs, correct Command flags, and final modifier release to zero. Receiver events were consumed before editing/clipboard actions, preserving the user's clipboard. All 108 warnings-as-errors tests passed. Temporary probe entry point/source were removed from the release.
- A real phone-to-Mac ToDesk click has not been revalidated: the connected phone tool reported no available device. This is a tested compatibility change, not a claim that the original ToDesk failure is definitively resolved. At the user’s explicit request, backed up 0.8.43 to `~/Library/Application Support/RemoteFit/Backups/0.8.43-before-0.8.44-8vti770k/`, gracefully exited it through SIGTERM, overwrote `/Applications/Better Remote.app`, and launched 0.8.44 (58). Installed strict signature, exact release binary, one installed-path process and unchanged stored shortcuts passed; shutdown followed the existing display-restoration path. System Spotlight settings and stored user shortcuts were preserved. Diagnostic source/logs: `/tmp/remotefit-shortcut-check/`.

- Universal warnings-as-errors Release and DMG checksum verification passed. Read-only mounted package verified 0.8.44 (58), arm64/x86_64 architectures, strict signature, exact executable equality, Applications shortcut and native read-only `--check`. SHA-256: `3313a2df08d864aa8147dc75b098e2fd5de07d835535d61a08c92ea402a83ac4`. Mount detached afterward.
- After installation, native event-tap metadata showed the installed process’s workspace mouse interceptor enabled. Two injected mouse probes against the installed search button did not produce keyboard events or open Tinycast, while an active ToDesk Session mouse/keyboard interceptor was present. These results cannot isolate mouse delivery/filtering without the real client; no successful actual ToDesk acceptance is claimed. Probe windows/processes were cleaned up, and the installed app remains running for the user’s remote retest.


## 0.8.45 Workspace responsiveness and remote target selection — 2026-10-07

- A 3-second sample of installed 0.8.44 captured repeated main-thread WorkspaceLayoutController.invalidate/tick calls waiting in LaunchServices activation-policy queries and AX observer window-list reads. WindowActions.log also captured center/maximize targeting a 24×32 ToDesk helper, while normal-app operations resolved standard window frames. These are observed app-side problems; not proof of a ToDesk interceptor defect.
- Removed global AX window-observer scans and eager invalidation tasks. Existing 200 ms polling and drag guard remain, with first scan deferred until the expansion animation completes. Visible usable window PIDs and a 5-second activation-policy cache replace per-notification enumeration of all regular applications. Tiny helper frames are excluded from avoidance and target actions.
- Target selection now checks visible usable windows and rejects a tiny focused helper even when that PID owns another background window. Previous visible applications are preferred, with visible-window order as fallback; legitimate normal ToDesk client windows remain eligible. Sender respects an explicit nil from its resolver. Mouse-up hit testing handles events associated with a different window using the global pointer.
- Completed ordinary clicks queue serially, asynchronously await real foreground activation, then send the existing session down/up sequence. Pending operations cancel on toolbar shutdown/configuration. Held gestures keep synchronous down/release behavior, and modifier-only HID behavior is retained. Lightweight asynchronous metadata diagnostics record input receipt, target fallback and delivery/failure; no typed-text or clipboard capture.
- 113 warnings-as-errors tests passed, including tiny-helper exclusion, history fallback, valid remote-client windows and stale/missing windows. Current-source dependency-injected sender checks verified no events before activation, FIFO clicks, final modifier release, cancellation, explicit nil target and immediate held-key behavior, without posting actual keyboard events. A local 30-iteration metadata benchmark measured old all-app policy lookup at 0.249 s versus current cached visible-window snapshots at 0.082 s; this is not an end-to-end remote-frame timing claim.
- Universal Release, fixed signing and DMG verification passed. Backed up 0.8.44, gracefully exited it, covered `/Applications/Better Remote.app` with 0.8.45 (59), relaunched and verified strict signature, binary equality and one installed-path process. Latest native state showed the user's expanded toolbar.
- AndroMeld reported zero connected devices, so actual phone-to-Mac ToDesk acceptance is still pending. The changes address confirmed app-side issues and add diagnostics; no claim that every reported ToDesk failure has been reproduced/resolved. Evidence and checks retained at `DesignExploration/remote-actions-20261007/` and `/tmp/remotefit-responsive-check/`.


## 0.8.46 Isolated shortcut clicks — 2026-10-07

- The user's real ToDesk retry on 0.8.45 recorded button down/up inside the toolbar, correct target/front PID and execution of keyboard posting. This narrows the remaining failure to delivery/handling after the button action; it does not establish which remote interceptor is responsible.
- Completed ordinary clicks now use their own CGEventSource privateState, HID delivery and a cancellable 35 ms press interval. The source survives until key-up/modifier release. Modifier-only and legacy held interactions retain HID system state and synchronous initial presses. Existing focus waiting, target policy, cancellation and FIFO remain.
- A locally signed fixture registered its own unused Command-Option-Control-Shift-F20 Carbon hotkey. Session and HID posting triggered it; annotated-session posting did not. Private state on HID also triggered it. The final production ShortcutSender, compiled directly into that fixture, triggered the same hotkey once. This validates global-hotkey routing without changing the user's launcher binding or system settings.
- Dependency-injected current-source checks verify activation before keys, FIFO, a real press interval, queued cancellation, explicit nil targets, synchronous held input and cancellation during the 35 ms press releasing keys/modifiers exactly once. Core suite: 113 tests passed. No connected phone is available for actual ToDesk acceptance; the delivery change remains pending that retest.
- Probe artifacts: /tmp/remotefit-key-route-check/ and /tmp/remotefit-responsive-check/. No permission grants, saved shortcuts or system hotkeys were changed.
- Universal warnings-as-errors release, fixed signing and DMG checksum passed. Backed up 0.8.45, gracefully exited it, overwrote the installed app and relaunched 0.8.46 (60). Installed version, strict signature, executable equality and exactly one installed-path process verified. Native UI showed the floating ball with 展开快捷操作. DMG SHA-256: 83fff783924e62b7f4c0a4d6664857e5f09f8c52882f42a4891c80809d2103f0.


## 0.8.47 Session-tail shortcut delivery — 2026-10-07

- The user's 11:03 ToDesk clicks reached the installed 0.8.46 toolbar and produced complete Command/Space sequences in a passive HID trace. Neither the session-tail nor annotated-session trace recorded the same source PID. The active session interceptors belonged to ToDesk_Session (verified process path). This localizes failure after initial posting; the trace alone cannot distinguish dropped events from changed source attribution or isolate a particular interceptor.
- Ordinary completed-click shortcuts now enter through a tail session tap using CGEvent.tapPostEvent, before system hotkey dispatch. The tap only handles uniquely identified, same-process null wakeups; it never reads or filters user typing. Placement refreshes between gestures, keeps pending releases alive, retains private keyboard state, preserves FIFO and waits for posting before the 35 ms press interval. A missing wakeup falls back once after removing its packet, preventing late-wakeup duplication. Modifier-only and held HID behavior is retained.
- A signed native fixture compiled the production sender/relay directly. With ToDesk_Session running, its registered global hotkey fired exactly once, including under an additional interceptor that discarded the fixture's keyboard events. The real configured Command-Space opened Tinycast and a second invocation closed it. A separate focused native receiver consumed Command-C/Command-V before application actions: complete down/up pairs arrived in order, with Command flags and final modifier state zero. No clipboard or saved shortcut changes were made. An initial same-bundle self-activation fixture did not acquire focus; that empty capture was discarded and the separate receiver was used.
- 118 warnings-as-errors tests passed. New sender regression coverage checks activation gating, FIFO, press duration, cancellation before activation/during a press, and immediate modifier-only HID delivery. Native route/filter/receiver evidence is retained under /tmp/remotefit-live-input-check/.
- Universal Release, fixed signature and DMG checksum passed. Backed up 0.8.46, gracefully exited it, installed and started 0.8.47 (61). LaunchServices initially returned -600 after exit; explicit fresh launch succeeded. Verified one installed-path process, strict signature, release binary equality and unchanged preferences. DMG SHA-256: 4b8bc8070b93ed60059967f9511782d7522f7917a5d585110c2695b7e66a65e4.
- Temporary trace/receiver processes were stopped. The user subsequently confirmed twice that actual ToDesk clicks on installed 0.8.47 now work ("可以了 感觉生效了" / "已经生效"). An initial post-restart attempt saw loginwindow as foreground and correctly stopped at focus validation; subsequent clicks posted through the relay with the intended foreground target. This is actual ToDesk acceptance, not a claim of testing every remote program or every low-level shortcut listener.


## 0.8.48 Reuse the active virtual display — 2026-10-07

- User reports post-resolution click offset with multiple remote products. Code inspection confirmed that every changed specification restored the physical desktop, destroyed the current virtual display and created another. This is a verified topology-churn source, not a demonstrated complete explanation of the remote client's coordinate cache.
- Virtual display descriptors now allow the existing supported 512–3840 logical-pixel range on both axes. Native mode updates preserve the current mode alongside the requested mode, then CoreGraphics selects the new mode on the same display. The worker skips origin changes. First activation still creates/mirrors a display; explicit restore/shutdown still removes it.
- Update validation requires stable display IDs, UUIDs, hardware identities, main-display assignment, mirror relationships and origins, plus exact 2x mode readback twice. The original physical recovery snapshot is never rewritten by a successful resize. Update failure returns to the previous mode on the same display; only failed rollback invokes physical restore, after the native display reference unwinds.
- 123 warnings-as-errors tests passed, including source-only portrait updates, unchanged mirror topology, changed identities/origins/main/mirror rejection, invalid/missing sources and hotplug/duplicate-ID rejection.
- Native smoke applied 1366×768, then 1502×768, 1502×845, 1652×930, 630×1400 and 1366×768. All kept display ID 52 and the same UUID, main/mirror/origin configuration and byte-identical recovery data. An injected error after selecting 1280×800 returned to 1366×768 on the same display. A GUI-hosted CoreGraphics callback trace recorded one add at initial activation, no add/remove during updates/rollback, and one remove at final restore. Final physical modes, pixel sizes, positions, main/mirror states and UUIDs matched the pre-test baseline; session.json was removed.
- An initial smoke fixture retained a local strong display reference through restore. The reference was replaced with its numeric ID, and rollback-error escalation was similarly moved outside the native reference scope. The final native smoke passed. These live display tests do not validate phone touch mapping.
- Universal Release, fixed signature and DMG checksum passed. Backed up 0.8.47, gracefully exited it, installed/launched 0.8.48 (62), and verified one installed-path process, exact release binary, unchanged preferences and native --check. DMG SHA-256: 0793019f9e6a1f7445f8ab1fbee6f6ba15baa6b2f74fe413263629cb4d1c612b. Evidence: /tmp/remotefit-display-update-check/.
- Remote-client click accuracy remains pending actual retest. Scope is repeated mode changes on an already active virtual display; initial activation and switching back to physical displays still require the remote product to update its mapping.


## 0.8.49 Preserve Quartz key-identity flags — 2026-10-07

- The user's saved 所有窗口 shortcut is correctly configured as Control + Up (code 126, modifiers 262144). Logs confirmed completed clicks and session-relay posting. CopySymbolicHotKeys returned enabled Control/Fn arrow bindings; absent per-user symbolic-hotkey entries were not treated as disabled defaults.
- A read-only CGEvent construction probe showed that Quartz supplies SecondaryFn and NumericPad for arrow keys, SecondaryFn for function/navigation keys, and NumericPad for keypad Enter. ShortcutSender previously overwrote these flags with only the configured modifiers. Event construction now preserves those key-identity flags on ordinary key down/up while retaining exact flagsChanged cleanup. No physical Fn press is added and no user/system shortcut settings are changed.
- 127 warnings-as-errors tests passed. New tests cover all four Control arrows on down/up, final modifier release, function/navigation flags, keypad Enter versus Return and unchanged Command-C/V/Space key flags. The tests construct real CGEvents without posting them.
- Universal Release, fixed signature and DMG checksum passed. Backed up 0.8.48, installed/started 0.8.49 (63), verified exact release binary and unchanged preferences. DMG SHA-256: 05241dd9570219993052c724db9f662e093f9212fff5da6a3802535075d0b05d. Evidence: /tmp/remotefit-mission-control-check/.
- Installed toolbar AX activation produced Control-Up relay logs. Dock accessibility inspection timed out, so no automated visual acceptance was claimed. The user subsequently confirmed that the installed 所有窗口 shortcut now opens Mission Control ("能打开了"). This completes actual user acceptance for Control-Up.


## 0.8.49 Source submission and repackaging — 2026-10-07

- Rebuilt the current accepted 0.8.49 (63) source as an arm64/x86_64 Universal app and DMG. The unchanged code retains the 127-test passing result. Read-only mounted package passed strict signing, exact executable comparison and native --check; the mount was detached.
- Repackaged DMG SHA-256: 3f270237b1ba6d85d18a08c98d583c251c80021f31a295820e1ed5c6057eed30. Formal source, regression tests and documentation are submitted; local DesignExploration evidence and dist artifacts are excluded. No remote push or reinstall is part of this packaging step.

## 0.8.63 Preset mode registration — 2026-10-09

- The user reports persistent UU phone flicker after automatic connection adaptation followed by a manual preset change. RemoteFit logs show a single 1252×1156 → 1400×630 change, without repeated automatic application. WindowServer logs at 15:17:20 show `applyProxyModes`, virtual display off/on transitions and an intermediate unmirror state. Stable display IDs and final topology checks did not detect these intermediate changes. This identifies a disruptive application path; it does not establish the complete cause of UU's persistent rendering failure.
- Initial activation now registers existing preset dimensions and their supported display-size variants. Selecting a registered mode does not reapply virtual-display settings. Unregistered dimensions append to a stable mode list, retaining all previously registered modes and their order. The native catalog includes a 512×512 floor: the initial mixed-orientation fixture showed CoreAnimation rejecting a portrait mode below its derived minimum width; the floor removed this rejection. First activation, restore and first use of an unregistered adjustment still reconfigure displays.
- 161 warnings-as-errors tests pass. Added catalog coverage for all size variants, deduplication and invalid/overflow entries. Three older migration tests had six stale assertions expecting resolution/settings in the configurable list; updated them to the existing fixed-action policy, keeping checks that unrelated actions survive migration. No migration behavior was changed.
- Native smoke applied 1252×1156, 1400×630, 630×1400, returned to 1252×1156, appended 1502×768 / 1502×845 / 1652×930, and revisited registered modes. Display ID 43, UUID, mirror/main/origin state and byte-identical recovery snapshot were retained. An injected failure at 1280×800 returned to 1252×1156 on the same display. Final physical display modes, pixels, positions, refresh rates, UUIDs and topology matched the pre-test snapshot; session.json was removed.
- WindowServer trace confirms no `applyProxyModes` or display off transition during registered landscape/portrait changes at 15:33:17–15:33:21. The trace does show settings updates on initial activation and three previously unregistered adjustments, as expected. Evidence: `/tmp/remotefit-uu-flicker-check/`. Actual UU phone flicker acceptance remains pending.
- Universal Release, fixed signing and DMG checksum verification passed. Read-only mounted package passed strict signing, executable equality, Applications shortcut and native `--check`; detached afterward. Backed up 0.8.62 under `~/Library/Application Support/RemoteFit/Backups/0.8.62-before-0.8.63-20261009-153532/`, gracefully stopped it while no remote session was active, installed/launched 0.8.63 (77), and verified one installed-path process, strict signature, release-binary equality and byte-identical preferences. DMG SHA-256: `7f1dde51e3435ad691e3027c25e76a4537e634c1a9a037b6c267ad6c8a45d60c`.
- Actual UU retest failed: the user reports the same persistent flicker after automatic 1252×1156 adaptation and manual 630×1400 selection at 15:39:23. Returning to physical screens and selecting 1024×768 also continued to flicker. The retest trace shows one mode selection, updated display dimensions and a capture aspect-ratio notification; it does not show the removed `applyProxyModes` reset during that manual switch. Therefore 0.8.63 is not a confirmed fix for UU flicker. Evidence: `/tmp/remotefit-uu-flicker-check/system-retest.log`.

## 0.8.64 Unified capture-display replacement — 2026-10-09

- Follow-up capture logs show UU creating an SCContentFilter at 630×1400 at 15:39:52, while the requested desktop became 1024×768 at 15:39:53. Earlier automatic adaptation similarly created a capture filter at the previous 1400×630 size before becoming 1252×1156. No subsequent SCStream recreation/configuration update was observed at the manual 630×1400 resize. The trace supports stale capture setup as a compatibility concern; it does not prove the complete rendering failure mechanism.
- Per the user's explicit direction, all remote software now shares the same automatic/manual switching path. Each changed size restores/removes the previous virtual display, then creates one with a fresh serial/UUID and a single target mode. There is no provider-specific branch. Removed live mode-list updates and preset pre-registration. The original physical recovery snapshot survives replacements byte-for-byte; failure attempts to recreate the previous specification. Repeat selection of the current size is a no-op.
- The initial native pixel canvas must match the requested 2x dimensions. macOS initially selected a 1x logical view for the portrait fixture (1260×2800 for requested 630×1400), with the same 1260×2800 pixel canvas; the transaction that establishes mirroring selects the 2x logical mode. An initial strict logical-size fixture rejected this valid state, restored the previous specification and physical screens; the final pixel-canvas check and smoke passed.
- Native smoke at 15:57 verified 1252×1156 → 630×1400 → 1024×768 → 1400×630 with distinct UUIDs, correct target pixels, unchanged original recovery data, and no replacement for repeat selections. An invalid 4000×900 request preserved the current specification. An injected failure creating 1280×800 recreated 1400×630 with a fresh UUID. Final physical modes, pixels, refresh rates, origins, UUIDs and main/mirror topology matched the pre-test snapshot, with session.json removed.
- Evidence: `/tmp/remotefit-uu-flicker-check/fresh/`. These are local display checks, not UU/ToDesk/mobile visual acceptance. Actual persistent flicker and remote input mapping still require a phone retest. Switching intentionally changes display topology and may briefly black out or reposition windows.
- All 160 warnings-as-errors tests and Universal Release passed. Read-only DMG verified signature, executable equality, version, Applications shortcut and native `--check`; detached after a brief busy retry. Backed up 0.8.63 to `~/Library/Application Support/RemoteFit/Backups/0.8.63-before-0.8.64-20261009-160021/`, installed/launched 0.8.64 (78), and verified a single installed-path process, fixed strict signature, arm64/x86_64 architectures, exact release binary and unchanged preferences. DMG SHA-256: `55663f99855c7f6301190b42330efa01061458f25e6405f488149cf97a29b22c`.

## 0.8.65 Move overlapping windows only at expansion — 2026-10-09

- The explicit toolbar expansion event takes one snapshot of overlapping visible windows. After the existing 200 ms animation, a single pass moves eligible unchanged standard windows. No periodic workspace timer, active drag guard, focused-window fill or collapse-time fill is started. Rendering, application switches, new windows and screen changes do not schedule another pass. Collapse, manual window actions, changed toolbar geometry and user interaction cancel pending work without retrying.
- The automatic window path writes only AXPosition once, with no AXSize, frame correction, activation or raise calls. Fullscreen/minimized windows are excluded; windows changed since the snapshot are skipped. Geometry supports all four edges and negative screen coordinates. If a same-size move cannot fit inside the visible screen, the window is left alone. Explicit maximize/center buttons retain their existing behavior.
- All 168 warnings-as-errors tests pass. New tests cover four-edge size-preserving moves, non-overlap/edge contact, oversized windows and negative coordinates. Dependency-injected controller tests verify one snapshot per expansion, no response to subsequently added windows, cancellation on collapse/geometry changes, and no retry after user interaction. These tests do not constitute actual installed-window or phone interaction acceptance.

## 0.8.66 Avoid actual overlaps after window/app changes — 2026-10-09

- The user clarified that dragging and application switches should still trigger avoidance. The unwanted behavior was an unrelated window being enlarged at expansion: the original `fillFocused` path selected the whole workspace for the initial target window without checking toolbar overlap. That path remains removed.
- While expanded, a 250 ms check observes visible geometry, toolbar region and foreground-app changes. It filters for actual toolbar overlap and uses the same position-only write introduced in 0.8.65. Checks pause during mouse presses and resume after release; unchanged failed moves do not loop. Collapse stops checks without filling windows. No mouse-event drag interceptor is enabled. Same-size moves that cannot fit on screen are skipped; explicit maximize/center actions remain available.
- All 168 warnings-as-errors tests pass. Controller tests now cover an unrelated foreground window remaining untouched, newly overlapping windows, drag-release handling, application changes, stable-failure suppression and collapse stopping all moves. Four-edge, no-overlap and oversized-window geometry coverage remains. These are automated logic tests, not installed native-window or phone acceptance.
- Universal Release, fixed signing, DMG checksum and read-only mounted-package checks passed. Backed up 0.8.65 to `~/Library/Application Support/RemoteFit/Backups/0.8.65-before-0.8.66-20261009-162450/`, installed/launched 0.8.66 (80), and verified one installed-path process, arm64/x86_64, strict signature, exact packaged executable and unchanged preferences. DMG SHA-256: `b5c0b610224b4d216d3172587d6c52f0ab266629ba6707875475006af4ee38d5`.
- The user subsequently confirmed that the previously reported persistent UU flicker no longer occurs on the installed build. This is actual UU acceptance of the fresh-display switching path retained from 0.8.64; it does not establish acceptance for every remote client or the window-avoidance interaction.

## 0.8.67 Overlap-only size fallback and ten-point collapse fill — 2026-10-09

- The user's Chrome was 1728×1050 at (0,30). With no space for a same-size move, 0.8.66 skipped it by design. The user explicitly approved trimming only an overlapping window when translation cannot fit. Geometry now prefers translation and otherwise clips only the obstructed axis/edge, preserving the perpendicular size and opposite edge. Non-overlapping windows still never enter the automatic action path.
- Restored the explicit-collapse 0–10 point inner-edge fill for left/right toolbars, preserving height and the opposite edge. It has a separate cancellable task so the subsequent collapsed-state render does not discard the fill; re-expansion cancels pending fill. Disabling/hiding and shutdown do not initiate fill. Candidate identity, unchanged frame and standard/non-fullscreen status are rechecked before native writes.
- All 171 warnings-as-errors tests pass, including actual 1728×1050 Chrome geometry through avoid/fill, fallback on all four edges, exact 10 versus over-10 thresholds, collapsed render preserving fill, re-expansion cancelling it, and unchanged unrelated windows.
- Universal Release and mounted DMG verification passed. Backed up 0.8.66 to `~/Library/Application Support/RemoteFit/Backups/0.8.66-before-0.8.67-20261009-163753/`, installed/launched 0.8.67 (81), and verified one installed-path process, strict signing, arm64/x86_64, exact packaged binary and unchanged preferences. DMG SHA-256: `8480ae550e93a7f493f8e91a5abd4d4feef2f839b412a60271c617c7678a340c`.
- Actual installed toolbar clicks through native CUA verified collapse fill and subsequent expansion. Chrome PID 14298 was identified from its executable path. At 16:38:37 collapse changed its frame from (8,30,1640,1050) to (8,30,1720,1050); at 16:39:36 expansion trimmed it back to (8,30,1640,1050). Native frame-readback verification completed successfully for these writes. A second adjacent window also followed the approved edge rule. Toolbar AX state confirmed expanded/collapsed transitions. Phone-side acceptance and every third-party application's minimum-size behavior are not claimed.

## 0.8.68 Full-height built-in display restoration — 2026-10-09

- The user reports the notch region disappearing after remote use and requests restoration on disconnect and the restore button. Live state was built-in 1728×1080 / 3456×2160 at 120 Hz, safe-area top 0 with no auxiliary notch area. Earlier chat evidence confirmed the desired 1728×1117 mode. The mode list exposes same-width/scale/refresh full-height variants, flagged native by IOKit; the cropped mode is not native. This is an actual mode difference, not only a stale repaint.
- Restoration normalizes only physical, unmirrored built-in targets: a cropped 16:10 mode is matched to the native panel's full-height aspect while preserving logical width, backing scale and refresh. A small height increase and an available matching mode are required. External, non-notched, already-full-height and unmatched modes remain unchanged. Worker selection prefers the matching mode ID, then closest refresh variant. Existing physical identity/topology restoration and rollback remain in place.
- The shared restore path covers remote disconnect, explicit restore and normal exit. With no session.json, explicit restore still repairs a cropped physical screen and checks readback. Startup does not change a physical-only desktop merely because the app launched. The button no longer returns early solely because no virtual-display recovery record exists.
- All 176 warnings-as-errors tests pass. Added cropped/full-height, fractional refresh, alternate backing scale, other scaling levels, external/non-notched panels and unavailable-mode coverage. Native tests verified no-session repair, restoration from an intentionally cropped saved baseline through repeated fresh-display replacements and injected rollback, and repeat restore as a no-op. Final state matched the full-height baseline; refresh, external display configuration, origins and preferences were preserved; session.json was removed.
- Native AppKit readback after restoration: built-in frame 1728×1117, safeAreaInsets.top=32, auxiliaryTopLeftArea present. Original 120 Hz was retained. Evidence: `/tmp/remotefit-notch-restore/`. Actual future phone-disconnect timing still depends on the existing remote-session detection path; no new privacy-screen repair is included.
- Universal Release, fixed signing, DMG checksum and mounted package checks passed. Backed up 0.8.67 to `~/Library/Application Support/RemoteFit/Backups/0.8.67-before-0.8.68-20261009-174356/`, installed/launched 0.8.68 (82), and verified one installed-path process, exact binary, arm64/x86_64 and unchanged preferences. DMG SHA-256: `6737aa6e8995956106ab89b813e773401c3011076a2819baf62902726c27e2b5`.
- Installed-button verification: with no active remote session or session.json, the built-in screen was temporarily returned to the original 1728×1080 fixture using the app's worker. A native CUA click on `persistent:restoreDisplay` produced `manual_restore_start` at 17:45:02 and `full_height_restore` at 17:45:03. Readback confirmed 1728×1117 / 3456×2234 at 120 Hz, safe-area top 32 and auxiliary notch area present. External display mode/origin and primary assignment remained unchanged. Toolbar was collapsed afterward.


## 2026-10-17 — UU direct-touch Return recovery (0.8.133 / 151)

- Reproduction: after toolbar Return, UU-origin mouse down/up pairs reused the Return position even when the user tapped elsewhere. Moving the toolbar item did not fix it. The system reported Return and the left mouse button released. Disabling our single-finger scroll tap did not resolve the symptom.
- Controls: making Return a no-op restored subsequent touch coordinates; application-targeted key delivery and the legacy HID path both reproduced the problem. These experimental routes and the temporary `/tmp/BetterRemote-ReturnProbe.mode` switch were removed from the final implementation.
- Evidence: during failure the cursor visibility query returned hidden. With the fix, Return at Unix time 1792205823.357303 hid the cursor at 1792205823.375607; stationary recovery was posted at 1792205823.471298 and visibility returned at 1792205823.476348, without changing coordinates. Other post-Return clicks reached distinct buttons and positions. This supports a cursor-visibility compatibility issue; UU's internal mode-switch decision was not directly observed.
- Implementation: retain the original shortcut delivery. After plain Return key-up and a short receiver-processing interval, post a zero-delta mouse-moved event at the current cursor position. Skip after cancellation, target changes, or while a mouse button is pressed. No synthetic click, saved-position warp, global cursor-hide counter change, or persistent cursor polling is installed.
- `swift test --filter 'ShortcutSenderTests|ShortcutKeyboardEventTests'`: 14 passed, zero failures. New coverage checks recovery after key-up, cancellation, unchanged modified shortcuts, and a stationary move rather than a click. Universal Release build and installed signature verification passed. This is a local Developer ID-signed build without timestamp/notarization; no public update was published.
- User confirmed the real UU phone session works with 0.8.133. The temporary single-finger-scroll disable was subsequently restored to its original enabled state; that restored setting still needs normal-use confirmation. Source changes remain uncommitted.
