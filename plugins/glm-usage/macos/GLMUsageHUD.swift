// ============================================================================
// 文件作用：GLM Coding Plan 用量悬浮窗（macOS 原生实现）
//
// 当前版本：v1.0
//   - 无边框圆角悬浮面板，始终置顶，可用鼠标任意位置拖拽
//   - 全局快捷键（默认 Ctrl+G）随时唤出 / 收起
//   - 菜单栏图标兜底，快捷键失效时也能操作
//   - 窗口位置自动记忆，下次弹出保持在上次拖到的地方
//
// 为什么这样做：
//   - 用 Swift + AppKit，Mac 自带 Command Line Tools 即可编译，零第三方依赖
//   - 数据不自己请求接口，而是复用官方 glm-usage.mjs 脚本的 --json 输出，
//     保证显示口径和终端里 /glm-usage 完全一致，脚本升级后无需改这里
//   - 全局快捷键走 Carbon RegisterEventHotKey，不需要「辅助功能」授权
//
// 支持范围：macOS 12+，Apple Silicon / Intel 均可
//
// 注意事项：
//   - 应用以 accessory 模式运行，不占 Dock，不抢焦点
//   - 配置文件 ~/.zcode/glm-usage-hud/config.json 可改快捷键和刷新间隔
// ============================================================================

import AppKit
import Carbon.HIToolbox

// MARK: - 全局常量与路径

enum HUDPaths {
    static let home = NSHomeDirectory()
    static var baseDir: String { home + "/.zcode/glm-usage-hud" }
    static var configPath: String { baseDir + "/config.json" }
    /// 官方查询脚本所在的插件缓存根目录
    static var pluginCacheDir: String { home + "/.zcode/cli/plugins/cache" }
}

enum HUDMetrics {
    static let width: CGFloat = 372
    static let height: CGFloat = 306
    static let pad: CGFloat = 18
    static let corner: CGFloat = 16
}

// MARK: - 配置读写

/// 悬浮窗配置，保存在 config.json，允许用户手工编辑
struct HUDConfig {
    var hotkey: String = "ctrl+g"
    var autoShowOnStart: Bool = true
    var refreshIntervalMinutes: Double = 5
    var originX: Double? = nil
    var originY: Double? = nil
    var nodePath: String? = nil
    /// 独立使用（不依赖 ZCode 登录态）时手工填写的凭据，会以 --key/--base 传给查询脚本
    var apiKey: String? = nil
    var apiBase: String? = nil

    static func load() -> HUDConfig {
        var cfg = HUDConfig()
        guard let data = FileManager.default.contents(atPath: HUDPaths.configPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return cfg
        }
        if let v = obj["hotkey"] as? String, !v.isEmpty { cfg.hotkey = v }
        if let v = obj["autoShowOnStart"] as? Bool { cfg.autoShowOnStart = v }
        if let v = obj["refreshIntervalMinutes"] as? Double, v > 0 { cfg.refreshIntervalMinutes = v }
        if let v = obj["originX"] as? Double { cfg.originX = v }
        if let v = obj["originY"] as? Double { cfg.originY = v }
        if let v = obj["nodePath"] as? String, !v.isEmpty { cfg.nodePath = v }
        if let v = obj["apiKey"] as? String, !v.isEmpty { cfg.apiKey = v }
        if let v = obj["apiBase"] as? String, !v.isEmpty { cfg.apiBase = v }
        return cfg
    }

    func save() {
        var obj: [String: Any] = [
            "hotkey": hotkey,
            "autoShowOnStart": autoShowOnStart,
            "refreshIntervalMinutes": refreshIntervalMinutes,
        ]
        if let x = originX { obj["originX"] = x }
        if let y = originY { obj["originY"] = y }
        if let n = nodePath { obj["nodePath"] = n }
        if let k = apiKey { obj["apiKey"] = k }
        if let b = apiBase { obj["apiBase"] = b }
        try? FileManager.default.createDirectory(atPath: HUDPaths.baseDir,
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: HUDPaths.configPath))
        }
    }
}

// MARK: - 官方脚本 JSON 的数据模型

struct UsageDetailDTO: Codable {
    let modelCode: String?
    let usage: Int?
}

struct QuotaLimitDTO: Codable {
    let type: String?
    let unit: Int?
    let number: Int?
    let percentage: Double?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
    let nextResetTime: Double?
    let usageDetails: [UsageDetailDTO]?
}

struct QuotaDTO: Codable {
    let limits: [QuotaLimitDTO]?
    let level: String?
}

struct ModelSummaryDTO: Codable {
    let modelName: String?
    let totalTokens: Double?
}

struct TotalUsageDTO: Codable {
    let totalModelCallCount: Double?
    let totalTokensUsage: Double?
    let modelSummaryList: [ModelSummaryDTO]?
}

struct ModelUsageDTO: Codable {
    let totalUsage: TotalUsageDTO?
}

struct UsageRootDTO: Codable {
    let quota: QuotaDTO?
    let modelUsage: ModelUsageDTO?
}

// MARK: - 展示用的格式化工具

enum Fmt {
    /// 接口实测：unit 3/5/6 对应 小时/月/周，与官方脚本保持一致
    static let unitName: [Int: String] = [3: "小时", 5: "个月", 6: "周"]

    static func period(_ unit: Int?, _ number: Int?) -> String {
        let n = number ?? 0
        guard let u = unit, let name = unitName[u] else { return "\(n)×unit\(unit ?? -1)" }
        return "\(n)\(name)"
    }

    /// 行标题，规则对齐官方脚本 labelFor()
    static func label(for l: QuotaLimitDTO) -> String {
        let p = period(l.unit, l.number)
        if l.type == "TIME_LIMIT" { return "MCP 工具调用（\(p)）" }
        if p.contains("小时") { return "\(l.number ?? 5) 小时 Prompt 池" }
        if p.contains("周") { return "每周额度" }
        return "\(p)额度"
    }

    static func icon(for l: QuotaLimitDTO) -> String {
        if l.type == "TIME_LIMIT" { return "🔧" }
        return period(l.unit, l.number).contains("小时") ? "🕐" : "📅"
    }

    /// token 数量的中文缩写，1.25 亿 / 9.2 万
    static func tokens(_ n: Double) -> String {
        if n >= 1e8 { return String(format: "%.2f 亿", n / 1e8) }
        if n >= 1e4 { return String(format: "%.1f 万", n / 1e4) }
        return String(format: "%.0f", n)
    }

    /// 千分位整数
    static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 毫秒时间戳 -> "09/04 18:22"
    static func clock(_ ms: Double) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    /// 毫秒时间戳 -> "5 天 3 小时 13 分钟后"
    static func countdown(_ ms: Double) -> String {
        let sec = Int(ms / 1000 - Date().timeIntervalSince1970)
        if sec <= 0 { return "即将重置" }
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d) 天") }
        if h > 0 { parts.append("\(h) 小时") }
        if m > 0 { parts.append("\(m) 分钟") }
        if parts.isEmpty { parts.append("不到 1 分钟") }
        return parts.joined(separator: " ") + "后"
    }

    /// 按已用比例给进度条配色：越接近用尽越警示
    static func tint(_ usedPercent: Double) -> NSColor {
        if usedPercent >= 85 { return .systemRed }
        if usedPercent >= 60 { return .systemOrange }
        return NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.45, alpha: 1.0)
    }
}

// MARK: - 数据抓取：调用官方 glm-usage.mjs --json

enum FetchResult {
    case success(UsageRootDTO)
    case failure(String)
}

final class UsageFetcher {

    private static var cachedNode: String?

    /// 定位 node 可执行文件。应用可能被 Finder/launchd 拉起，PATH 很干净，必须自己找。
    static func resolveNode(preferred: String?) -> String? {
        if let c = cachedNode, FileManager.default.isExecutableFile(atPath: c) { return c }
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["GLM_HUD_NODE"] { candidates.append(env) }
        if let p = preferred { candidates.append(p) }
        // nvm 安装的版本，按版本号从新到旧
        let nvmDir = HUDPaths.home + "/.nvm/versions/node"
        if let vers = try? fm.contentsOfDirectory(atPath: nvmDir) {
            let sorted = vers.sorted { a, b in
                a.compare(b, options: .numeric) == .orderedDescending
            }
            candidates.append(contentsOf: sorted.map { nvmDir + "/" + $0 + "/bin/node" })
        }
        candidates.append(contentsOf: ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"])
        for c in candidates where fm.isExecutableFile(atPath: c) {
            cachedNode = c
            return c
        }
        // 兜底：走一次登录 shell 问 PATH
        if let out = runSync("/bin/zsh", ["-lc", "command -v node"], timeout: 8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty, fm.isExecutableFile(atPath: out) {
            cachedNode = out
            return out
        }
        return nil
    }

    /// 定位官方查询脚本：
    ///   1. 优先找应用包旁边自带的 scripts/glm-usage.mjs（分享给别人的机器也能用）
    ///   2. 回退到本机 ZCode 插件缓存，插件版本升级后自动选最新
    static func resolveScript() -> String? {
        let fm = FileManager.default
        // Bundle.main.bundleURL 是 …/GLMUsageHUD.app/，上一级就是应用所在目录
        let local = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("scripts/glm-usage.mjs").path
        if fm.fileExists(atPath: local) { return local }

        let root = HUDPaths.pluginCacheDir
        guard let markets = try? fm.contentsOfDirectory(atPath: root) else { return nil }
        var found: [(version: String, path: String)] = []
        for market in markets {
            let skillRoot = root + "/" + market + "/glm-usage"
            guard let versions = try? fm.contentsOfDirectory(atPath: skillRoot) else { continue }
            for v in versions {
                let p = skillRoot + "/" + v + "/skills/glm-usage/scripts/glm-usage.mjs"
                if fm.fileExists(atPath: p) { found.append((v, p)) }
            }
        }
        return found.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            .first?.path
    }

    /// 同步执行外部命令，带超时保护
    private static func runSync(_ exe: String, _ args: [String], timeout: TimeInterval) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return nil }

        // 超时看门狗，避免网络卡死时悬浮窗一直转圈
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()

        if task.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            let out = String(data: outData, encoding: .utf8) ?? ""
            let msg = (err + "\n" + out).trimmingCharacters(in: .whitespacesAndNewlines)
            UsageFetcher.lastStderr = msg
            return nil
        }
        return String(data: outData, encoding: .utf8)
    }

    static var lastStderr: String = ""

    /// 后台线程抓取数据，完成后回主线程回调
    static func fetch(config: HUDConfig, completion: @escaping (FetchResult, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = resolveScript() else {
                DispatchQueue.main.async {
                    completion(.failure("找不到 glm-usage.mjs，请确认 glm-usage 插件已安装"), nil)
                }
                return
            }
            guard let node = resolveNode(preferred: config.nodePath) else {
                DispatchQueue.main.async {
                    completion(.failure("找不到 node，可在 config.json 里手工填写 nodePath"), nil)
                }
                return
            }
            lastStderr = ""
            // 独立部署时把 config.json 里的凭据显式传给脚本，不依赖 ZCode 登录态
            var args = [script, "--json"]
            if let k = config.apiKey, let b = config.apiBase {
                args += ["--key", k, "--base", b]
            }
            guard let raw = runSync(node, args, timeout: 25) else {
                let detail = lastStderr.split(separator: "\n").first.map(String.init) ?? "脚本执行失败"
                DispatchQueue.main.async { completion(.failure(detail), node) }
                return
            }
            // 脚本理论上只输出纯 JSON，这里仍从第一个 { 开始截，避免混入额外日志
            guard let start = raw.firstIndex(of: "{"),
                  let data = String(raw[start...]).data(using: .utf8),
                  let dto = try? JSONDecoder().decode(UsageRootDTO.self, from: data) else {
                DispatchQueue.main.async { completion(.failure("返回内容解析失败"), node) }
                return
            }
            DispatchQueue.main.async { completion(.success(dto), node) }
        }
    }
}

// MARK: - 进度条视图

final class BarView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    var tint: NSColor = .systemGreen { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        guard r.height > 0 else { return }
        let radius = r.height / 2

        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()

        let ratio = max(0, min(1, progress))
        guard ratio > 0 else { return }
        // 比例极小时也保证画出一个圆点，视觉上不至于「什么都没有」
        let w = max(ratio * r.width, r.height)
        tint.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: r.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - 单条额度行

final class QuotaRowView: NSView {
    let titleLabel = HUDContentView.makeLabel(12.5, .semibold, .labelColor)
    let valueLabel = HUDContentView.makeLabel(12, .medium, .secondaryLabelColor, align: .right)
    let bar = BarView()
    let subLabel = HUDContentView.makeLabel(10.5, .regular, .tertiaryLabelColor)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(bar)
        addSubview(subLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    static let rowHeight: CGFloat = 46

    override func layout() {
        super.layout()
        let w = bounds.width
        titleLabel.frame = NSRect(x: 0, y: 0, width: w - 110, height: 16)
        valueLabel.frame = NSRect(x: w - 110, y: 0, width: 110, height: 16)
        bar.frame = NSRect(x: 0, y: 20, width: w, height: 6)
        subLabel.frame = NSRect(x: 0, y: 30, width: w, height: 14)
    }

    func apply(_ l: QuotaLimitDTO) {
        let used = l.percentage ?? 0
        titleLabel.stringValue = "\(Fmt.icon(for: l))  \(Fmt.label(for: l))"
        bar.progress = CGFloat(used / 100)
        bar.tint = Fmt.tint(used)

        if l.type == "TIME_LIMIT", let total = l.usage, let cur = l.currentValue {
            valueLabel.stringValue = "\(Fmt.int(cur)) / \(Fmt.int(total)) 次"
        } else {
            valueLabel.stringValue = String(format: "剩余 %.1f%%", max(0, 100 - used))
        }

        var sub: [String] = []
        if l.type == "TIME_LIMIT", let rem = l.remaining { sub.append("剩余 \(Fmt.int(rem))") }
        if let reset = l.nextResetTime {
            sub.append("↻ \(Fmt.clock(reset)) 重置 · \(Fmt.countdown(reset))")
        }
        subLabel.stringValue = sub.joined(separator: " · ")
    }
}

// MARK: - 面板内容视图

final class HUDContentView: NSView {

    static func makeLabel(_ size: CGFloat,
                          _ weight: NSFont.Weight,
                          _ color: NSColor,
                          align: NSTextAlignment = .left) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = align
        l.lineBreakMode = .byTruncatingTail
        l.isSelectable = false
        return l
    }

    let titleLabel = makeLabel(14, .bold, .labelColor)
    let metaLabel = makeLabel(10.5, .regular, .tertiaryLabelColor)
    let refreshButton = NSButton()
    let closeButton = NSButton()
    var rows: [QuotaRowView] = []
    let separator = NSBox()
    let footerLabel = makeLabel(11.5, .medium, .labelColor)
    let footerSubLabel = makeLabel(10.5, .regular, .tertiaryLabelColor)
    let hintLabel = makeLabel(10, .regular, .quaternaryLabelColor)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.stringValue = "⚡ GLM Coding Plan"
        metaLabel.stringValue = "正在读取…"

        configureIconButton(refreshButton, title: "↻", tooltip: "立即刷新")
        configureIconButton(closeButton, title: "✕", tooltip: "收起面板")

        separator.boxType = .separator

        for _ in 0..<3 {
            let r = QuotaRowView()
            rows.append(r)
            addSubview(r)
        }
        [titleLabel, metaLabel, refreshButton, closeButton,
         separator, footerLabel, footerSubLabel, hintLabel].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configureIconButton(_ b: NSButton, title: String, tooltip: String) {
        b.title = title
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.font = .systemFont(ofSize: 13, weight: .medium)
        b.contentTintColor = .secondaryLabelColor
        b.toolTip = tooltip
        b.setButtonType(.momentaryChange)
    }

    override func layout() {
        super.layout()
        let pad = HUDMetrics.pad
        let w = bounds.width - pad * 2
        var y = pad - 2

        titleLabel.frame = NSRect(x: pad, y: y, width: w - 60, height: 20)
        closeButton.frame = NSRect(x: bounds.width - pad - 20, y: y, width: 20, height: 20)
        refreshButton.frame = NSRect(x: bounds.width - pad - 46, y: y, width: 20, height: 20)
        y += 21
        metaLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
        y += 14 + 12

        for r in rows {
            r.frame = NSRect(x: pad, y: y, width: w, height: QuotaRowView.rowHeight)
            r.needsLayout = true
            y += QuotaRowView.rowHeight + 8
        }

        y += 2
        separator.frame = NSRect(x: pad, y: y, width: w, height: 1)
        y += 11
        footerLabel.frame = NSRect(x: pad, y: y, width: w, height: 16)
        y += 17
        footerSubLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
        y += 15
        hintLabel.frame = NSRect(x: pad, y: y, width: w, height: 13)
    }

    /// 内容高度随实际行数变化，用于自适应窗口高度
    var preferredHeight: CGFloat {
        let visibleRows = rows.filter { !$0.isHidden }.count
        return HUDMetrics.pad - 2 + 21 + 14 + 12
            + CGFloat(visibleRows) * (QuotaRowView.rowHeight + 8)
            + 2 + 1 + 11 + 16 + 1 + 14 + 1 + 13 + HUDMetrics.pad
    }

    func render(_ dto: UsageRootDTO, hotkeyText: String) {
        let level = (dto.quota?.level ?? "").uppercased()
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        metaLabel.stringValue = (level.isEmpty ? "" : "\(level) 套餐 · ")
            + "更新于 \(df.string(from: Date()))"

        let limits = dto.quota?.limits ?? []
        for (i, row) in rows.enumerated() {
            if i < limits.count {
                row.isHidden = false
                row.apply(limits[i])
            } else {
                row.isHidden = true
            }
        }

        if let total = dto.modelUsage?.totalUsage {
            let calls = Int(total.totalModelCallCount ?? 0)
            let tk = total.totalTokensUsage ?? 0
            footerLabel.stringValue = "📊  近 24 小时　\(Fmt.int(calls)) 次 · \(Fmt.tokens(tk)) tokens"
            let models = (total.modelSummaryList ?? []).compactMap { m -> String? in
                guard let name = m.modelName else { return nil }
                return "\(name) \(Fmt.tokens(m.totalTokens ?? 0))"
            }
            footerSubLabel.stringValue = models.isEmpty ? "" : models.joined(separator: " · ")
        } else {
            footerLabel.stringValue = "📊  近 24 小时用量暂不可用"
            footerSubLabel.stringValue = ""
        }
        hintLabel.stringValue = "\(hotkeyText) 唤出 / 收起 · 拖拽面板可移动位置"
        needsLayout = true
    }

    func renderError(_ message: String, hotkeyText: String) {
        metaLabel.stringValue = "读取失败"
        for row in rows { row.isHidden = true }
        rows.first?.isHidden = false
        rows.first?.titleLabel.stringValue = "⚠️  查询失败"
        rows.first?.valueLabel.stringValue = ""
        rows.first?.bar.progress = 0
        rows.first?.subLabel.stringValue = message
        footerLabel.stringValue = "可点右上角 ↻ 重试"
        footerSubLabel.stringValue = ""
        hintLabel.stringValue = "\(hotkeyText) 唤出 / 收起 · 拖拽面板可移动位置"
        needsLayout = true
    }

    func renderLoading() {
        metaLabel.stringValue = "正在读取…"
    }
}

// MARK: - 悬浮面板

final class HUDPanel: NSPanel {
    // 无边框窗口默认不能成为 key window，这里放开以便响应 Esc
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 全局快捷键（Carbon，不需要辅助功能授权）

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onFire: (() -> Void)?

    /// 解析 "ctrl+g" / "cmd+shift+u" 这类描述
    static func parse(_ text: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = text.lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " })
            .map(String.init)
        guard let keyToken = parts.last else { return nil }
        var mods: UInt32 = 0
        for p in parts.dropLast() {
            switch p {
            case "ctrl", "control", "^": mods |= UInt32(controlKey)
            case "cmd", "command", "meta": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            case "alt", "option", "opt": mods |= UInt32(optionKey)
            default: return nil
            }
        }
        guard let code = keyCodeMap[keyToken] else { return nil }
        return (code, mods)
    }

    static let keyCodeMap: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// 人类可读的快捷键文案，用于面板底部提示
    static func display(_ text: String) -> String {
        var out = ""
        for p in text.lowercased().split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " }) {
            switch p {
            case "ctrl", "control": out += "⌃"
            case "cmd", "command": out += "⌘"
            case "shift": out += "⇧"
            case "alt", "option", "opt": out += "⌥"
            default: out += p.uppercased()
            }
        }
        return out
    }

    @discardableResult
    func register(_ text: String) -> Bool {
        unregister()
        guard let (code, mods) = HotKeyCenter.parse(text) else { return false }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.shared.onFire?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        // signature 用四字符码 'GLMH' 标识本应用的热键
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C_4D48), id: 1)
        let status = RegisterEventHotKey(code, mods, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }
}

// MARK: - 应用主体

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: HUDPanel!
    private var content: HUDContentView!
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var countdownTimer: Timer?
    private var config = HUDConfig.load()
    private var lastData: UsageRootDTO?
    private var hotkeyOK = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildStatusItem()
        setupHotKey()

        if config.autoShowOnStart { showPanel() }
        refresh()
        startTimers()
    }

    /// 再次 open 本应用时（ZCode 每次启动会调一次），把面板重新弹出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel()
        refresh()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregister()
    }

    // MARK: 界面搭建

    private func buildPanel() {
        let rect = NSRect(x: 0, y: 0, width: HUDMetrics.width, height: HUDMetrics.height)
        panel = HUDPanel(contentRect: rect,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true   // 面板任意位置都能拖拽
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        let effect = NSVisualEffectView(frame: rect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = HUDMetrics.corner
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        effect.autoresizingMask = [.width, .height]

        content = HUDContentView(frame: rect)
        content.autoresizingMask = [.width, .height]
        content.refreshButton.target = self
        content.refreshButton.action = #selector(refreshAction)
        content.closeButton.target = self
        content.closeButton.action = #selector(hidePanel)
        effect.addSubview(content)

        panel.contentView = effect
        restoreFrame()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⚡"
        statusItem.button?.toolTip = "GLM Coding Plan 用量"

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示 / 收起面板", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshAction), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let cfgItem = NSMenuItem(title: "打开配置文件夹", action: #selector(openConfigDir), keyEquivalent: "")
        cfgItem.target = self
        menu.addItem(cfgItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setupHotKey() {
        HotKeyCenter.shared.onFire = { [weak self] in self?.togglePanel() }
        hotkeyOK = HotKeyCenter.shared.register(config.hotkey)
        if !hotkeyOK {
            // 快捷键被别的应用占用时不阻塞使用，菜单栏图标依然可用
            statusItem.button?.toolTip = "GLM 用量（快捷键 \(config.hotkey) 注册失败，可能被占用）"
        }
    }

    private func startTimers() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: config.refreshIntervalMinutes * 60,
                                            repeats: true) { [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            self.refresh()
        }
        // 每分钟只重画倒计时文案，不重新请求接口
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self, let d = self.lastData, self.panel.isVisible else { return }
            self.content.render(d, hotkeyText: self.hotkeyText)
        }
    }

    private var hotkeyText: String {
        hotkeyOK ? HotKeyCenter.display(config.hotkey) : "菜单栏 ⚡"
    }

    // MARK: 窗口位置

    private func restoreFrame() {
        let size = NSSize(width: HUDMetrics.width, height: HUDMetrics.height)
        var origin: NSPoint
        if let x = config.originX, let y = config.originY,
           isOnAnyScreen(NSRect(origin: NSPoint(x: x, y: y), size: size)) {
            origin = NSPoint(x: x, y: y)
        } else if let screen = NSScreen.main {
            // 默认停在主屏右上角
            let f = screen.visibleFrame
            origin = NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24)
        } else {
            origin = NSPoint(x: 100, y: 100)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func isOnAnyScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }

    func windowDidMove(_ notification: Notification) {
        config.originX = Double(panel.frame.origin.x)
        config.originY = Double(panel.frame.origin.y)
        config.save()
    }

    // MARK: 行为

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel(); refresh() }
    }

    @objc func showPanel() {
        if !isOnAnyScreen(panel.frame) { restoreFrame() }
        resizeToContent()
        panel.orderFrontRegardless()   // 不抢占前台应用焦点
    }

    @objc func hidePanel() {
        panel.orderOut(nil)
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func openConfigDir() {
        NSWorkspace.shared.open(URL(fileURLWithPath: HUDPaths.baseDir))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func resizeToContent() {
        let h = max(content.preferredHeight, 120)
        guard abs(h - panel.frame.height) > 0.5 else { return }
        // 保持左上角不动地改变高度，视觉上不跳
        var f = panel.frame
        f.origin.y += f.height - h
        f.size.height = h
        panel.setFrame(f, display: true)
    }

    private func refresh() {
        content.renderLoading()
        UsageFetcher.fetch(config: config) { [weak self] result, node in
            guard let self = self else { return }
            if let n = node, self.config.nodePath != n {
                self.config.nodePath = n
                self.config.save()
            }
            switch result {
            case .success(let dto):
                self.lastData = dto
                self.content.render(dto, hotkeyText: self.hotkeyText)
            case .failure(let msg):
                self.content.renderError(msg, hotkeyText: self.hotkeyText)
            }
            self.resizeToContent()
        }
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
