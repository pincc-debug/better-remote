import Foundation

public enum ShortcutIcon: String, Codable, CaseIterable, Sendable {
    // MARK: - Most Common (Top 18 shown in collapsed state)
    case copy = "doc.on.doc"
    case clipboard = "doc.on.clipboard"
    case scissors = "scissors"
    case undo = "arrow.uturn.backward"
    case redo = "arrow.uturn.forward"
    case selectAll = "checklist"

    case save = "square.and.arrow.down.fill"
    case fullscreen = "arrow.up.left.and.arrow.down.right"
    case terminal = "terminal.fill"
    case screenshot = "camera.viewfinder"
    case safari = "safari.fill"
    case spotlight = "text.magnifyingglass"

    case volumeUp = "speaker.wave.3.fill"
    case volumeDown = "speaker.wave.1.fill"
    case mute = "speaker.slash.fill"
    case lockScreen = "lock.desktopcomputer"
    case sleepMode = "bed.double.fill"
    case keyboard = "keyboard"

    // MARK: - Windows & Desktop
    case exitFullscreen = "arrow.down.right.and.arrow.up.left"
    case minimize = "minus.circle.fill"
    case window = "macwindow"
    case newWindow = "macwindow.badge.plus"
    case splitScreen = "rectangle.split.2x1.fill"
    case spaces = "rectangle.on.rectangle"
    case sidebar = "sidebar.left"
    case missionControl = "macwindow.on.rectangle"
    case dock = "dock.rectangle"
    case launchpad = "circle.grid.3x3.fill"
    case switching = "arrow.left.arrow.right"
    case splitVertical = "rectangle.split.1x2.fill"
    case grid2x2 = "rectangle.split.2x2.fill"
    case threeColumns = "rectangle.split.3x1.fill"
    case sidebarRight = "sidebar.right"
    case leftHalf = "rectangle.lefthalf.inset.filled"
    case rightHalf = "rectangle.righthalf.inset.filled"
    case topHalf = "rectangle.tophalf.inset.filled"
    case bottomHalf = "rectangle.bottomhalf.inset.filled"
    case fillWindow = "arrow.up.left.and.arrow.down.right.square"
    case minimizeWindow = "minus.rectangle"
    case centerWindow = "rectangle.center.inset.filled"
    case enlarge = "arrow.up.left.and.down.right.magnifyingglass"
    case windowStack = "rectangle.stack.fill"
    case tabs = "square.on.square"
    case windowClose = "xmark.rectangle"
    case eyeOff = "eye.slash.fill"
    case cloud = "cloud.fill"
    case sync = "arrow.triangle.2.circlepath.circle"
    case flashlight = "flashlight.on.fill"
    case magnet = "magnet"

    // MARK: - Editing & Documents & Tools
    case compose = "square.and.pencil"
    case pencil = "pencil"
    case brush = "paintbrush.fill"
    case document = "doc.fill"
    case folder = "folder.fill"
    case trash = "trash.fill"
    case printDoc = "printer.fill"
    case findReplace = "character.cursor.ibeam"
    case bold = "bold"
    case italic = "italic"
    case underline = "underline"
    case text = "textformat"
    case note = "note.text"
    case todo = "list.bullet.clipboard"
    case calculator = "plus.forwardslash.minus"
    case paperclip = "paperclip"
    case link = "link"
    case bookmark = "bookmark.fill"
    case tag = "tag.fill"
    case pin = "pin.fill"
    case chart = "chart.bar.fill"
    case list = "list.bullet"

    // MARK: - Web & Browser & Code
    case search = "magnifyingglass"
    case refresh = "arrow.clockwise"
    case newTab = "plus.square.fill"
    case closeTab = "xmark.square.fill"
    case code = "curlybraces"
    case script = "chevron.left.forwardslash.chevron.right"
    case share = "square.and.arrow.up"
    case download = "square.and.arrow.down"
    case password = "key.fill"
    case translate = "character.bubble.fill"

    // MARK: - Media & Controls
    case play = "play.fill"
    case pause = "pause.fill"
    case stop = "stop.fill"
    case backward = "backward.fill"
    case forward = "forward.fill"
    case speaker = "speaker.wave.2.fill"
    case headphones = "headphones"
    case music = "music.note"
    case microphone = "mic"
    case micMute = "mic.slash.fill"
    case camera = "camera"
    case video = "video.fill"
    case videoOff = "video.slash.fill"
    case screenRecord = "record.circle.fill"
    case photo = "photo.fill"
    case viewfinder = "viewfinder"

    // MARK: - Hardware & System
    case display = "display"
    case settings = "gearshape"
    case power = "power"
    case restart = "arrow.triangle.2.circlepath"
    case lock = "lock.fill"
    case unlock = "lock.open.fill"
    case battery = "battery.100"
    case wifi = "wifi"
    case bluetooth = "dot.radiowaves.left.and.right"
    case airplay = "airplayvideo"
    case sun = "sun.max.fill"
    case brightnessDown = "sun.min.fill"
    case moon = "moon.fill"
    case bell = "bell.fill"
    case chip = "cpu"
    case sliders = "slider.horizontal.3"

    // MARK: - Keys & Navigation
    case escapeKey = "escape"
    case tabKey = "arrow.right.to.line"
    case returnKey = "return"
    case deleteLeft = "delete.left"
    case command = "command"
    case optionKey = "option"
    case arrowUp = "arrow.up"
    case arrowDown = "arrow.down"
    case arrowLeft = "arrow.left"
    case arrowRight = "arrow.right"
    case pageUp = "arrow.up.to.line"
    case pageDown = "arrow.down.to.line"
    case pointer = "cursorarrow"
    case tap = "hand.tap.fill"
    case zoomIn = "plus.magnifyingglass"
    case zoomOut = "minus.magnifyingglass"
    case rotateRight = "rotate.right.fill"

    // MARK: - Communication & Life
    case phone = "phone.fill"
    case phoneDevice = "iphone"
    case message = "message.fill"
    case mail = "envelope.fill"
    case chat = "bubble.left.and.bubble.right.fill"
    case person = "person.fill"
    case people = "person.2.fill"
    case globe = "globe"
    case calendar = "calendar"
    case clock = "clock.fill"
    case timer = "timer"
    case map = "map.fill"
    case location = "location.fill"
    case cart = "cart.fill"
    case card = "creditcard.fill"
    case gift = "gift.fill"
    case home = "house.fill"
    case game = "gamecontroller.fill"

    // MARK: - Symbols & Badges
    case bolt = "bolt"
    case star = "star"
    case heart = "heart.fill"
    case flag = "flag.fill"
    case sparkles = "sparkles"
    case wand = "wand.and.stars"
    case lightbulb = "lightbulb.fill"
    case hammer = "hammer.fill"
    case like = "hand.thumbsup.fill"
    case hand = "hand.raised.fill"
    case plus = "plus"
    case minus = "minus"
    case checkmark = "checkmark"
    case close = "xmark"
    case help = "questionmark.circle.fill"
    case info = "info.circle.fill"
    case warning = "exclamationmark.triangle.fill"
    case eye = "eye.fill"
    case number = "number"
    case mention = "at"
    case airplane = "airplane"
    case car = "car.fill"
    case walk = "figure.walk"
    case drop = "drop.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"

    public var title: String {
        switch self {
        case .copy: "复制"
        case .clipboard: "粘贴"
        case .scissors: "剪切"
        case .undo: "撤销"
        case .redo: "重做"
        case .selectAll: "全选"
        case .save: "保存"
        case .fullscreen: "全屏"
        case .terminal: "终端"
        case .screenshot: "截屏"
        case .safari: "浏览器"
        case .spotlight: "聚焦"
        case .volumeUp: "音量加"
        case .volumeDown: "音量减"
        case .mute: "静音"
        case .lockScreen: "锁屏"
        case .sleepMode: "休眠"
        case .keyboard: "键盘"

        case .exitFullscreen: "退出全屏"
        case .minimize: "最小化"
        case .window: "窗口"
        case .newWindow: "新建窗口"
        case .splitScreen: "左右分屏"
        case .spaces: "桌面"
        case .sidebar: "侧边栏"
        case .splitVertical: "上下分屏"
        case .grid2x2: "田字格"
        case .threeColumns: "三列"
        case .sidebarRight: "右侧边栏"
        case .leftHalf: "左半屏"
        case .rightHalf: "右半屏"
        case .topHalf: "上半屏"
        case .bottomHalf: "下半屏"
        case .fillWindow: "填充"
        case .minimizeWindow: "最小化窗口"
        case .centerWindow: "居中"
        case .enlarge: "放大窗口"
        case .windowStack: "窗口堆叠"
        case .tabs: "标签页"
        case .windowClose: "关闭窗口"
        case .eyeOff: "隐藏"
        case .cloud: "云"
        case .sync: "同步"
        case .flashlight: "手电筒"
        case .magnet: "吸附"
        case .missionControl: "调度中心"
        case .dock: "程序坞"
        case .launchpad: "启动台"
        case .switching: "切换"

        case .compose: "编辑"
        case .pencil: "铅笔"
        case .brush: "画笔"
        case .document: "文件"
        case .folder: "文件夹"
        case .trash: "删除"
        case .printDoc: "打印"
        case .findReplace: "光标"
        case .bold: "加粗"
        case .italic: "斜体"
        case .underline: "下划线"
        case .text: "文字"
        case .note: "备忘录"
        case .todo: "待办"
        case .calculator: "计算器"
        case .paperclip: "附件"
        case .link: "链接"
        case .bookmark: "书签"
        case .tag: "标签"
        case .pin: "图钉"
        case .chart: "图表"
        case .list: "列表"

        case .search: "搜索"
        case .refresh: "刷新"
        case .newTab: "新建标签"
        case .closeTab: "关闭标签"
        case .code: "代码"
        case .script: "脚本"
        case .share: "分享"
        case .download: "下载"
        case .password: "密码"
        case .translate: "翻译"

        case .play: "播放"
        case .pause: "暂停"
        case .stop: "停止"
        case .backward: "快退"
        case .forward: "快进"
        case .speaker: "声音"
        case .headphones: "耳机"
        case .music: "音乐"
        case .microphone: "语音"
        case .micMute: "麦克风静音"
        case .camera: "相机"
        case .video: "视频"
        case .videoOff: "关闭摄像头"
        case .screenRecord: "录屏"
        case .photo: "照片"
        case .viewfinder: "取景"

        case .display: "屏幕"
        case .settings: "设置"
        case .power: "电源"
        case .restart: "重启"
        case .lock: "锁定"
        case .unlock: "解锁"
        case .battery: "电量"
        case .wifi: "网络"
        case .bluetooth: "蓝牙"
        case .airplay: "投屏"
        case .sun: "亮度加"
        case .brightnessDown: "亮度减"
        case .moon: "夜间"
        case .bell: "通知"
        case .chip: "芯片"
        case .sliders: "调节"

        case .escapeKey: "Esc"
        case .tabKey: "Tab"
        case .returnKey: "回车"
        case .deleteLeft: "退格"
        case .command: "Command"
        case .optionKey: "Option"
        case .arrowUp: "向上"
        case .arrowDown: "向下"
        case .arrowLeft: "向左"
        case .arrowRight: "向右"
        case .pageUp: "翻页向上"
        case .pageDown: "翻页向下"
        case .pointer: "鼠标"
        case .tap: "点击"
        case .zoomIn: "放大"
        case .zoomOut: "缩小"
        case .rotateRight: "旋转"

        case .phone: "电话"
        case .phoneDevice: "手机"
        case .message: "信息"
        case .mail: "邮件"
        case .chat: "对话"
        case .person: "个人"
        case .people: "联系人"
        case .globe: "语言"
        case .calendar: "日历"
        case .clock: "时钟"
        case .timer: "计时"
        case .map: "地图"
        case .location: "位置"
        case .cart: "购物"
        case .card: "卡片"
        case .gift: "礼物"
        case .home: "主页"
        case .game: "游戏"

        case .bolt: "快捷"
        case .star: "收藏"
        case .heart: "喜欢"
        case .flag: "标记"
        case .sparkles: "高亮"
        case .wand: "效果"
        case .lightbulb: "想法"
        case .hammer: "工具"
        case .like: "赞"
        case .hand: "手掌"
        case .plus: "添加"
        case .minus: "减少"
        case .checkmark: "完成"
        case .close: "关闭"
        case .help: "帮助"
        case .info: "说明"
        case .warning: "警告"
        case .eye: "显示"
        case .number: "数字"
        case .mention: "提及"
        case .airplane: "飞行"
        case .car: "汽车"
        case .walk: "步行"
        case .drop: "水滴"
        case .flame: "火焰"
        case .leaf: "叶子"
        }
    }

    public var keywords: [String] {
        switch self {
        case .copy: ["复制", "copy", "c", "拷贝", "duplicate"]
        case .clipboard: ["粘贴", "paste", "v", "剪贴板", "clipboard"]
        case .scissors: ["剪切", "cut", "x", "剪刀"]
        case .undo: ["撤销", "undo", "z", "返回", "后退", "cancel"]
        case .redo: ["重做", "redo", "y", "前进"]
        case .selectAll: ["全选", "select all", "a", "勾选", "checklist"]
        case .save: ["保存", "save", "s", "存储", "存盘"]
        case .printDoc: ["打印", "print", "p"]
        case .search: ["搜索", "search", "f", "查找", "find"]
        case .spotlight: ["聚焦", "spotlight", "全局搜索", "search"]
        case .fullscreen: ["全屏", "fullscreen", "最大化", "max", "放大窗口"]
        case .exitFullscreen: ["退出全屏", "exit fullscreen", "还原", "小屏"]
        case .minimize: ["最小化", "minimize", "m", "隐藏窗口"]
        case .window: ["窗口", "window", "视窗"]
        case .newWindow: ["新建窗口", "new window"]
        case .spaces: ["分屏", "spaces", "桌面", "多桌面"]
        case .splitScreen: ["左右分屏", "split screen", "分屏", "平铺"]
        case .sidebar: ["侧边栏", "sidebar", "边栏"]
        case .splitVertical: ["上下分屏", "上下", "split vertical", "top bottom", "分屏"]
        case .grid2x2: ["田字格", "四格", "2x2", "grid", "四分屏", "分屏"]
        case .threeColumns: ["三列", "三栏", "3 columns", "三分屏", "分屏"]
        case .sidebarRight: ["右侧边栏", "右边栏", "sidebar right", "侧边栏"]
        case .leftHalf: ["左半屏", "左半", "left half", "靠左"]
        case .rightHalf: ["右半屏", "右半", "right half", "靠右"]
        case .topHalf: ["上半屏", "上半", "top half", "靠上"]
        case .bottomHalf: ["下半屏", "下半", "bottom half", "靠下"]
        case .fillWindow: ["填充", "铺满", "fill", "最大化", "maximize"]
        case .minimizeWindow: ["最小化", "最小化窗口", "minimize", "收起窗口"]
        case .centerWindow: ["居中", "中间", "center", "居中窗口"]
        case .enlarge: ["放大窗口", "放大", "enlarge", "全屏", "缩放"]
        case .windowStack: ["窗口堆叠", "堆叠", "stack", "层叠", "多窗口"]
        case .tabs: ["标签页", "标签", "tabs", "切换标签"]
        case .windowClose: ["关闭窗口", "关闭", "close window", "窗口"]
        case .eyeOff: ["隐藏", "不可见", "hide", "隐藏窗口"]
        case .cloud: ["云", "云端", "cloud", "同步"]
        case .sync: ["同步", "刷新", "sync", "重新加载"]
        case .flashlight: ["手电筒", "照明", "flashlight"]
        case .magnet: ["吸附", "磁吸", "snap", "对齐"]
        case .missionControl: ["调度中心", "mission control", "任务视窗", "多任务"]
        case .dock: ["程序坞", "dock"]
        case .launchpad: ["启动台", "launchpad", "应用库", "app"]
        case .terminal: ["终端", "terminal", "cmd", "bash", "zsh", "shell", "命令行", "iterm"]
        case .script: ["脚本", "script", "代码", "sh", "命令"]
        case .code: ["代码", "code", "dev", "开发", "编程", "json", "html"]
        case .lock: ["锁定", "lock", "锁"]
        case .unlock: ["解锁", "unlock"]
        case .lockScreen: ["锁屏", "lock screen", "屏幕锁定"]
        case .power: ["电源", "关机", "power", "开机"]
        case .sleepMode: ["休眠", "睡眠", "sleep", "待机"]
        case .restart: ["重启", "restart", "reboot", "重新启动"]
        case .settings: ["设置", "settings", "偏好设置", "config", "首选项"]
        case .display: ["屏幕", "显示器", "display", "monitor", "分辨率"]
        case .battery: ["电量", "电池", "battery", "充电"]
        case .wifi: ["网络", "wifi", "无线网", "网络连接"]
        case .bluetooth: ["蓝牙", "bluetooth", "bt"]
        case .airplay: ["投屏", "airplay", "隔空播放", "屏幕镜像"]
        case .camera: ["相机", "camera", "拍照"]
        case .screenshot: ["截屏", "截图", "screenshot", "snip"]
        case .screenRecord: ["录屏", "录制", "screen record", "录像"]
        case .safari: ["浏览器", "safari", "chrome", "网页", "web", "上网"]
        case .newTab: ["新建标签", "new tab", "标签页", "tab"]
        case .closeTab: ["关闭标签", "close tab"]
        case .refresh: ["刷新", "refresh", "重新加载", "reload"]
        case .share: ["分享", "share", "发送"]
        case .download: ["下载", "download"]
        case .document: ["文件", "文档", "file", "doc"]
        case .folder: ["文件夹", "目录", "folder", "dir"]
        case .compose, .pencil: ["编辑", "修改", "edit", "pencil", "写"]
        case .brush: ["画笔", "brush", "涂鸦"]
        case .trash: ["删除", "trash", "delete", "移除"]
        case .note: ["便签", "备忘录", "note", "笔记"]
        case .todo: ["待办", "todo", "清单", "提醒", "checklist"]
        case .calculator: ["计算器", "calc", "calculator", "计算"]
        case .calendar: ["日历", "calendar", "日程"]
        case .clock, .timer: ["时钟", "时间", "clock", "timer", "倒计时", "秒表"]
        case .speaker, .volumeUp: ["声音", "音量加", "调大", "volume up", "喇叭"]
        case .volumeDown: ["音量减", "调小", "volume down", "降音量"]
        case .mute: ["静音", "mute", "静音扬声器", "闭音"]
        case .micMute: ["麦克风静音", "mic mute", "关闭麦克", "闭麦"]
        case .microphone: ["语音", "麦克风", "mic", "录音", "说话"]
        case .video: ["视频", "video", "摄像头", "录像"]
        case .videoOff: ["关闭摄像头", "video off", "关闭相机"]
        case .brightnessDown: ["亮度减", "brightness down", "变暗"]
        case .sun: ["白天", "亮度加", "sun", "变亮", "屏幕亮度"]
        case .moon: ["夜间", "暗色", "深色", "moon", "暗黑模式"]
        case .bell: ["通知", "bell", "提醒", "闹铃"]
        case .password: ["密码", "password", "key", "钥匙", "凭据"]
        case .translate: ["翻译", "translate", "语言", "词典"]
        case .escapeKey: ["esc", "escape", "取消", "退出键"]
        case .tabKey: ["tab", "切换", "制表符"]
        case .command: ["command", "cmd", "苹果键"]
        case .optionKey: ["option", "alt"]
        case .returnKey: ["回车", "enter", "return"]
        case .deleteLeft: ["退格", "backspace", "删除键"]
        case .arrowUp: ["上", "up", "向上", "方向键", "箭头"]
        case .arrowDown: ["下", "down", "向下", "方向键", "箭头"]
        case .arrowLeft: ["左", "left", "向左", "方向键", "箭头"]
        case .arrowRight: ["右", "right", "向右", "方向键", "箭头"]
        case .pageUp: ["page up", "pgup", "向上翻页", "上一页"]
        case .pageDown: ["page down", "pgdn", "向下翻页", "下一页"]
        case .zoomIn: ["放大", "zoom in", "放大镜"]
        case .zoomOut: ["缩小", "zoom out"]
        case .rotateRight: ["旋转", "rotate", "翻转"]
        case .keyboard: ["键盘", "keyboard", "打字", "输入"]
        default: []
        }
    }

    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if title.lowercased().contains(q) || rawValue.lowercased().contains(q) {
            return true
        }
        return keywords.contains { $0.lowercased().contains(q) }
    }

    public static func suggested(for name: String, keyLabel: String = "") -> ShortcutIcon? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyLabel.uppercased()

        if trimmed.contains("全屏") || trimmed.contains("最大化") {
            return trimmed.contains("退出") ? .exitFullscreen : .fullscreen
        }
        if trimmed.contains("最小化") {
            return .minimize
        }
        if trimmed.contains("复制") || (key.contains("C") && key.contains("⌘")) {
            return .copy
        }
        if trimmed.contains("粘贴") || (key.contains("V") && key.contains("⌘")) {
            return .clipboard
        }
        if trimmed.contains("剪切") || (key.contains("X") && key.contains("⌘")) {
            return .scissors
        }
        if trimmed.contains("撤销") || (key.contains("Z") && key.contains("⌘") && !key.contains("⇧")) {
            return .undo
        }
        if trimmed.contains("重做") || (key.contains("Z") && key.contains("⌘") && key.contains("⇧")) || (key.contains("Y") && key.contains("⌘")) {
            return .redo
        }
        if trimmed.contains("全选") || (key.contains("A") && key.contains("⌘")) {
            return .selectAll
        }
        if trimmed.contains("保存") || (key.contains("S") && key.contains("⌘")) {
            return .save
        }
        if trimmed.contains("打印") || (key.contains("P") && key.contains("⌘")) {
            return .printDoc
        }
        if trimmed.contains("聚焦") {
            return .spotlight
        }
        if trimmed.contains("截屏") || trimmed.contains("截图") {
            return .screenshot
        }
        if trimmed.contains("录屏") {
            return .screenRecord
        }
        if trimmed.contains("终端") || trimmed.contains("命令行") {
            return .terminal
        }
        if trimmed.contains("代码") {
            return .code
        }
        if trimmed.contains("脚本") {
            return .script
        }
        if trimmed.contains("浏览器") || trimmed.contains("网页") {
            return .safari
        }
        if trimmed.contains("新建标签") || (key.contains("T") && key.contains("⌘") && !key.contains("⇧")) {
            return .newTab
        }
        if trimmed.contains("关闭标签") || (key.contains("W") && key.contains("⌘")) {
            return .closeTab
        }
        if trimmed.contains("锁屏") {
            return .lockScreen
        }
        if trimmed.contains("休眠") || trimmed.contains("睡眠") {
            return .sleepMode
        }
        if trimmed.contains("重启") {
            return .restart
        }
        if trimmed.contains("投屏") {
            return .airplay
        }
        if trimmed.contains("计算器") {
            return .calculator
        }
        if trimmed.contains("便签") || trimmed.contains("备忘录") {
            return .note
        }
        if trimmed.contains("待办") || trimmed.contains("清单") {
            return .todo
        }
        if trimmed.contains("分屏") {
            return .splitScreen
        }
        if trimmed.contains("调度中心") {
            return .missionControl
        }
        if trimmed.contains("启动台") {
            return .launchpad
        }
        if trimmed.contains("搜索") || trimmed.contains("查找") || (key.contains("F") && key.contains("⌘")) {
            return .search
        }
        if trimmed.contains("静音麦") || trimmed.contains("闭麦") {
            return .micMute
        }
        if trimmed.contains("静音") {
            return .mute
        }
        if trimmed.contains("音量+") || trimmed.contains("音量加") {
            return .volumeUp
        }
        if trimmed.contains("音量-") || trimmed.contains("音量减") {
            return .volumeDown
        }
        if trimmed.contains("声音") || trimmed.contains("音量") {
            return .speaker
        }
        if trimmed.contains("关摄像头") || trimmed.contains("关相机") {
            return .videoOff
        }
        if trimmed.contains("删除") {
            return .trash
        }
        return nil
    }
}
