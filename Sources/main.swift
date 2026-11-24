// Kullanım: Claude plan kullanım yüzdesini menü çubuğunda sürekli gösterir.
// Veriyi ~/.claude/kullanim.json dosyasından okur. O dosyayı yazanlar: Claude Code modu ("kullanim"),
// Chrome eklentisi (yerel bağlantı) ya da uygulamanın kendi claude.ai bağlantısı (bir kez giriş yapılan
// pencere; oturum yalnız bu Mac'te, uygulamanın WebKit deposunda durur, yalnız claude.ai ile konuşur).

import Cocoa
import ServiceManagement
import WebKit

let isTurkish = (Locale.preferredLanguages.first ?? "en").hasPrefix("tr")
func L(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

let dataURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/kullanim.json")
let staleAfter: TimeInterval = 3 * 3600

// MARK: - Veri

struct Window { let kind: String; let percent: Double; let resetsAt: Date? }
struct Reading { let updatedAt: Date; let windows: [Window] }

func parseDate(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

func loadReading() -> Reading? {
    guard let data = try? Data(contentsOf: dataURL),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let list = root["rateLimits"] as? [[String: Any]] else { return nil }
    let windows = list.compactMap { entry -> Window? in
        guard let kind = entry["kind"] as? String,
              let percent = (entry["percentUsed"] as? NSNumber)?.doubleValue else { return nil }
        return Window(kind: kind, percent: percent, resetsAt: parseDate(entry["resetsAt"]))
    }
    guard !windows.isEmpty else { return nil }
    let updatedAt = parseDate(root["updatedAt"]) ?? .distantPast
    // Model bazlı satırı (Fable) yalnız uygulama kartı verir. Eski sürüm bir oturum dosyayı onsuz
    // yazarsa, son 20 dakikadaki model satırları korunur; satır gidip gelmez.
    if windows.contains(where: { $0.kind.hasPrefix("seven_day_") }) {
        modelCache = (windows.filter { $0.kind.hasPrefix("seven_day_") }, updatedAt)
        return Reading(updatedAt: updatedAt, windows: windows)
    }
    if let cache = modelCache, updatedAt.timeIntervalSince(cache.at) < 20 * 60 {
        return Reading(updatedAt: updatedAt, windows: windows + cache.windows)
    }
    return Reading(updatedAt: updatedAt, windows: windows)
}
var modelCache: (windows: [Window], at: Date)?

func percentText(_ value: Double) -> String {
    let n = Int(value.rounded())
    return isTurkish ? "%\(n)" : "\(n)%"
}

func windowTitle(_ kind: String) -> String {
    switch kind {
    case "five_hour": return L("5 saatlik sınır", "5-hour limit")
    case "seven_day": return L("Haftalık · tüm modeller", "Weekly · all models")
    case "spend_limit": return L("Harcama sınırı", "Spend limit")
    default:
        if kind.hasPrefix("seven_day_") { return L("Haftalık", "Weekly") + " · " + kind.dropFirst(10).capitalized }
        return kind
    }
}

func span(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return isTurkish ? "\(d) gün \(h) saat" : "\(d)d \(h)h" }
    if h > 0 { return isTurkish ? "\(h) saat \(m) dk" : "\(h)h \(m)m" }
    return isTurkish ? "\(m) dk" : "\(m)m"
}

/// Doluluğa göre renk: sakin, uyarı, sınırda. `nil` = menü çubuğunun kendi rengi.
func levelColor(_ percent: Double) -> NSColor? {
    if percent >= 90 { return .systemRed }
    if percent >= 70 { return .systemOrange }
    return nil
}

// MARK: - Menü çubuğu görünümü

enum Icon: Int, CaseIterable {
    case ringLabel = 7, ring = 8, labelBar = 9, gauge = 0, robot = 1, brain = 2, bolt = 3, coin = 4, bar = 5, none = 6

    var title: String {
        switch self {
        case .ringLabel: return L("Halka ve \"Claude\" yazısı", "Ring and \"Claude\" label")
        case .ring: return L("Yalnız halka", "Ring only")
        case .labelBar: return L("\"Claude\" yazısı ve çubuk", "\"Claude\" label and bar")
        case .gauge: return L("Gösterge", "Gauge")
        case .robot: return "🤖  " + L("Robot", "Robot")
        case .brain: return "🧠  " + L("Beyin", "Brain")
        case .bolt: return "⚡️  " + L("Şimşek", "Bolt")
        case .coin: return "🪙  " + L("Jeton", "Coin")
        case .bar: return L("Dolan çubuk", "Filling bar")
        case .none: return L("Yalnız rakam", "Number only")
        }
    }

    var emoji: String? {
        switch self {
        case .robot: return "🤖"
        case .brain: return "🧠"
        case .bolt: return "⚡️"
        case .coin: return "🪙"
        default: return nil
        }
    }

    var showsName: Bool { self == .ringLabel || self == .labelBar }

    static var current: Icon {
        get { (UserDefaults.standard.object(forKey: "simge") as? Int).flatMap(Icon.init(rawValue:)) ?? .ringLabel }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "simge") }
    }
}

/// Saat 12'den başlayıp kullanım kadar dolan halka.
func drawRing(percent: Double, in rect: NSRect, color: NSColor) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2 - 1.6
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = 2.6
    color.withAlphaComponent(0.28).setStroke()
    track.stroke()
    let fraction = CGFloat(min(max(percent, 0), 100) / 100)
    guard fraction > 0 else { return }
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * max(fraction, 0.03), clockwise: true)
    arc.lineWidth = 2.6
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()
}

func drawBar(percent: Double, in rect: NSRect, color: NSColor) {
    color.setStroke(); color.setFill()
    let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3, yRadius: 3)
    outline.lineWidth = 1.3
    outline.stroke()
    let inner = rect.insetBy(dx: 2.6, dy: 2.6)
    let width = max(1.5, inner.width * CGFloat(min(max(percent, 0), 100) / 100))
    NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height), xRadius: 1.2, yRadius: 1.2).fill()
}

/// Seçili görünümün resmi. Renkli ise şablon değildir; değilse menü çubuğunun rengini alır.
func statusImage(_ icon: Icon, percent: Double) -> NSImage? {
    let tint = levelColor(percent)
    func drawn(_ size: NSSize, _ body: @escaping (NSRect, NSColor) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in body(rect, tint ?? .black); return true }
        image.isTemplate = tint == nil
        return image
    }
    switch icon {
    case .ringLabel, .ring: return drawn(NSSize(width: 16, height: 16)) { drawRing(percent: percent, in: $0, color: $1) }
    case .labelBar, .bar: return drawn(NSSize(width: 26, height: 12)) { drawBar(percent: percent, in: $0, color: $1) }
    case .gauge:
        let symbol = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "speedometer", accessibilityDescription: nil)
        return symbol?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
    default: return nil
    }
}

func statusTitle(_ icon: Icon, percent: Double?) -> String {
    let number = percent.map(percentText) ?? "–"
    if let emoji = icon.emoji { return emoji + " " + number }
    if icon.showsName { return " Claude " + number }
    return (icon == .none ? "" : " ") + number
}

// MARK: - Açılan panel

final class PanelView: NSView {
    let reading: Reading?
    static let width: CGFloat = 270

    init(reading: Reading?) {
        self.reading = reading
        let rows = CGFloat(reading?.windows.count ?? 0)
        super.init(frame: NSRect(x: 0, y: 0, width: PanelView.width, height: 46 + rows * 52 + (reading == nil ? 34 : 22)))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let left: CGFloat = 16, right = bounds.width - 16
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignRight: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
            let width = (s as NSString).size(withAttributes: attributes).width
            (s as NSString).draw(at: NSPoint(x: alignRight ? x - width : x, y: y), withAttributes: attributes)
        }
        text("Claude", left, 10, size: 14, weight: .semibold, color: .labelColor)
        text(L("Plan kullanımı", "Plan usage"), left, 28, size: 11, weight: .regular, color: .secondaryLabelColor)
        guard let reading = reading else {
            text(L("Henüz okuma yok.", "No reading yet."), left, 50, size: 12, weight: .regular, color: .secondaryLabelColor)
            return
        }
        var y: CGFloat = 52
        for window in reading.windows {
            text(windowTitle(window.kind), left, y, size: 12.5, weight: .medium, color: .labelColor)
            text(percentText(window.percent), right, y, size: 12.5, weight: .semibold, color: .labelColor, alignRight: true)
            let track = NSRect(x: left, y: y + 21, width: right - left, height: 6)
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
            let fill = NSRect(x: left, y: y + 21, width: max(6, track.width * CGFloat(min(max(window.percent, 0), 100) / 100)), height: 6)
            (levelColor(window.percent) ?? .controlAccentColor).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
            if let reset = window.resetsAt, reset > Date() {
                text(span(reset.timeIntervalSinceNow) + L(" sonra sıfırlanır", " until reset"), left, y + 31, size: 10.5, weight: .regular, color: .secondaryLabelColor)
            }
            y += 52
        }
        text(L("Son okuma ", "Last reading ") + span(Date().timeIntervalSince(reading.updatedAt)) + L(" önce", " ago"),
             left, y, size: 10.5, weight: .regular, color: .tertiaryLabelColor)
    }
}

// MARK: - Okumayı kaydetme (eklenti ve claude.ai bağlantısı ortak)

func utcStamp() -> String {
    ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
}

/// Son durumu tek satır olarak yazar (tanı için; yüzde dışında veri yok).
func writeLog(_ line: String) {
    let url = dataURL.deletingLastPathComponent().appendingPathComponent("kullanim-tarayici.log")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? (utcStamp() + " " + String(line.prefix(900)) + "\n").write(to: url, atomically: true, encoding: .utf8)
}

/// Yalnız yüzde ve sıfırlanma zamanı kabul eder, dosyaya yazar.
@discardableResult
func saveReading(_ list: [[String: Any]], source: String, note: String? = nil) -> Bool {
    let clean: [[String: Any]] = list.compactMap { entry in
        guard let kind = entry["kind"] as? String, kind.count < 40,
              let percent = (entry["percentUsed"] as? NSNumber)?.doubleValue, percent >= 0, percent <= 1000 else { return nil }
        var row: [String: Any] = ["kind": kind, "percentUsed": percent]
        if let reset = entry["resetsAt"] as? String, reset.count < 40 { row["resetsAt"] = reset }
        return row
    }
    guard !clean.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: ["updatedAt": utcStamp(), "source": source, "rateLimits": clean], options: [.prettyPrinted])
    else { return false }
    try? FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: dataURL, options: .atomic)
    writeLog(source + " tamam: " + clean.compactMap { $0["kind"] as? String }.joined(separator: ",")
             + (note.map { " | iskelet: " + String($0.prefix(600)) } ?? ""))
    return true
}

// MARK: - claude.ai bağlantısı (Safari ya da başka tarayıcı kullananlar için)

/// claude.ai'nin kendi kullanım sayfasının okuduğu veriyi okur (Chrome eklentisindeki ayrıştırıcının aynısı).
let usageScript = """
const getJSON = async (u) => {
  const r = await fetch(u, { credentials: 'include', headers: { accept: 'application/json' } })
  if (!r.ok) throw new Error(u.replace(/[0-9a-f-]{36}/, '<org>') + ' -> ' + r.status)
  return r.json()
}
const ORDER = k => (k === 'seven_day' ? 0 : k.startsWith('seven_day_') ? 1 : 2)
const shapeOf = (node, depth) => {
  if (node === null) return 'null'
  if (typeof node !== 'object') return typeof node === 'number' ? 'n' : typeof node === 'string' ? 's' : typeof node
  if (depth > 3) return '...'
  if (Array.isArray(node)) return '[' + (node.length ? shapeOf(node[0], depth + 1) : '') + ']'
  return '{' + Object.entries(node).filter(([, v]) => v !== null).map(([k, v]) => k + ':' + shapeOf(v, depth + 1)).join(',') + '}'
}
const orgs = await getJSON('https://claude.ai/api/organizations')
if (!Array.isArray(orgs) || orgs.length === 0) throw new Error('no organizations')
const paid = orgs.find(o => (o.capabilities || []).some(c => /max|pro|ultra|team|enterprise/i.test(c)))
const org = paid || orgs[0]
const data = await getJSON('https://claude.ai/api/organizations/' + org.uuid + '/usage')
const rateLimits = []
const skip = new Set(['limits', 'windows', 'models', 'model', 'by', 'by_model', 'usage', 'rate', 'rate_limits', 'weekly', 'per'])
const walk = (node, path, depth) => {
  if (!node || typeof node !== 'object' || depth > 4) return
  for (const [key, v] of Object.entries(node)) {
    if (!v || typeof v !== 'object') continue
    const u = typeof v.utilization === 'number' ? v.utilization : typeof v.percent_used === 'number' ? v.percent_used : null
    const segs = [...path, String(v.model || v.model_name || v.name || key)].map(x => x.toLowerCase().replace(/[^a-z0-9_]+/g, '_'))
    if (u === null) { walk(v, Array.isArray(node) ? path : [...path, key], depth + 1); continue }
    const flat = segs.join('_')
    let kind
    if (flat === 'seven_day' || flat === 'five_hour') kind = flat
    else if (flat.includes('five_hour')) kind = 'five_hour_' + segs.filter(x => x !== 'five_hour' && !skip.has(x)).join('_')
    else {
      const extra = segs.flatMap(x => x.replace(/^seven_day_?/, '').split('_')).filter(x => x && !skip.has(x) && x !== 'seven' && x !== 'day')
      kind = extra.length ? 'seven_day_' + extra.join('_') : 'seven_day'
    }
    rateLimits.push({ kind, percentUsed: Math.round(u * 10) / 10, resetsAt: v.resets_at || v.resetsAt || undefined })
  }
}
// Asıl kaynak: "limits" listesi (haftalık toplam ve model bazlı sınırlar, ör. scope.model.display_name = "Fable").
for (const l of (Array.isArray(data.limits) ? data.limits : [])) {
  if (!l || typeof l.percent !== 'number') continue
  const g = String(l.group || l.kind || '').toLowerCase()
  const base = g.includes('week') ? 'seven_day' : /session|five|hour/.test(g) ? 'five_hour' : null
  if (!base) continue
  const scope = l.scope || {}
  const name = (scope.model && (scope.model.display_name || scope.model.id)) || (scope.surface && (scope.surface.display_name || scope.surface.id || (typeof scope.surface === 'string' ? scope.surface : '')))
  let kind = base
  if (name) kind = base + '_' + String(name).toLowerCase().replace(/[^a-z0-9]+/g, '_')
  else if (String(l.kind || '').includes('scoped')) kind = base + '_scoped'
  rateLimits.push({ kind, percentUsed: Math.round(l.percent * 10) / 10, resetsAt: l.resets_at || undefined })
}
// Yedek: eski biçim (seven_day: { utilization }) ya da başka yerdeki pencereler.
if (rateLimits.length === 0) walk(data, [], 0)
const seen = new Set()
const unique = rateLimits.filter(w => (seen.has(w.kind) ? false : (seen.add(w.kind), true)))
unique.sort((a, b) => ORDER(a.kind) - ORDER(b.kind))
return JSON.stringify({ rateLimits: unique, shape: shapeOf(data, 0).slice(0, 600) })
"""

final class ClaudeLink: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let shared = ClaudeLink()
    static let connectedKey = "claudeAiConnected"
    var isConnected: Bool { UserDefaults.standard.bool(forKey: ClaudeLink.connectedKey) }
    var onChange: (() -> Void)?

    private var window: NSWindow?
    private var loginView: WKWebView?
    private var loginTimer: Timer?
    private var poller: WKWebView?
    private var pollStarted = Date.distantPast

    func start() {
        let timer = Timer(timeInterval: 180, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        poll()
    }

    func openLogin() {
        if let window = window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: config)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L("claude.ai'ye giriş · Kullanım", "Sign in to claude.ai · Kullanım")
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        loginView = view
        view.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.checkLogin() }
        RunLoop.main.add(timer, forMode: .common)
        loginTimer = timer
    }

    /// Giriş tamamlandı mı: claude.ai kuruluş listesini veriyorsa evet.
    private func checkLogin() {
        guard let view = loginView, view.url?.host == "claude.ai" else { return }
        let js = "const r = await fetch('/api/organizations', { credentials: 'include' }); if (!r.ok) return 0; const j = await r.json(); return Array.isArray(j) ? j.length : 0"
        view.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            if case .success(let value) = result, let count = value as? NSNumber, count.intValue > 0 { self?.loginSucceeded() }
        }
    }

    private func loginSucceeded() {
        guard loginTimer != nil else { return }
        loginTimer?.invalidate(); loginTimer = nil
        UserDefaults.standard.set(true, forKey: ClaudeLink.connectedKey)
        window?.close()
        poll()
        onChange?()
    }

    func windowWillClose(_ notification: Notification) {
        loginTimer?.invalidate(); loginTimer = nil
        loginView = nil
        window = nil
    }

    func disconnect() {
        UserDefaults.standard.set(false, forKey: ClaudeLink.connectedKey)
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("claude") }) {}
        }
        onChange?()
    }

    /// Görünmez bir sayfada okur, kaydeder ve sayfayı kapatır (her 3 dakikada bir).
    func poll() {
        guard isConnected else { return }
        if poller != nil, Date().timeIntervalSince(pollStarted) < 60 { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        view.navigationDelegate = self
        poller = view
        pollStarted = Date()
        view.load(URLRequest(url: URL(string: "https://claude.ai/api/organizations")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === poller else { return }
        webView.callAsyncJavaScript(usageScript, arguments: [:], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value):
                if let text = value as? String, let data = text.data(using: .utf8),
                   let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let list = object["rateLimits"] as? [[String: Any]], saveReading(list, source: "claude.ai", note: object["shape"] as? String) {
                    self?.onChange?()
                } else {
                    writeLog("claude.ai: okuma boş")
                }
            case .failure(let error):
                let text = "\(error)"
                writeLog("claude.ai: " + text)
                if text.contains("-> 401") || text.contains("-> 403") {
                    UserDefaults.standard.set(false, forKey: ClaudeLink.connectedKey)
                    self?.onChange?()
                }
            }
            self?.poller = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === poller { writeLog("claude.ai: \(error.localizedDescription)"); poller = nil }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === poller { writeLog("claude.ai: \(error.localizedDescription)"); poller = nil }
    }
}

// MARK: - Uygulama

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        ClaudeLink.shared.onChange = { [weak self] in self?.refresh() }
        ClaudeLink.shared.start()
        if CommandLine.arguments.contains("--connect") && !ClaudeLink.shared.isConnected { ClaudeLink.shared.openLogin() }
    }

    private func refresh() {
        guard let button = item.button else { return }
        let icon = Icon.current
        let reading = loadReading()
        let windows = reading?.windows ?? []
        let top = windows.first(where: { $0.kind == "seven_day" }) ?? windows.max(by: { $0.percent < $1.percent })
        button.image = statusImage(icon, percent: top?.percent ?? 0)
        button.title = statusTitle(icon, percent: top?.percent)
        button.appearsDisabled = reading.map { Date().timeIntervalSince($0.updatedAt) > staleAfter } ?? true
        button.toolTip = L("Claude plan kullanımı", "Claude plan usage")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let panel = NSMenuItem()
        panel.view = PanelView(reading: loadReading())
        menu.addItem(panel)
        menu.addItem(.separator())
        let link = ClaudeLink.shared.isConnected
            ? NSMenuItem(title: L("claude.ai bağlantısını kes", "Disconnect claude.ai"), action: #selector(toggleClaudeLink), keyEquivalent: "")
            : NSMenuItem(title: L("claude.ai'ye bağlan…", "Connect to claude.ai…"), action: #selector(toggleClaudeLink), keyEquivalent: "")
        link.target = self
        menu.addItem(link)
        let icons = NSMenuItem(title: L("Görünüm", "Appearance"), action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        for icon in Icon.allCases {
            let entry = NSMenuItem(title: icon.title, action: #selector(pickIcon(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = icon.rawValue
            entry.state = icon == .current ? .on : .off
            iconMenu.addItem(entry)
        }
        icons.submenu = iconMenu
        menu.addItem(icons)
        let login = NSMenuItem(title: L("Açılışta başlat", "Start at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: L("Çıkış", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func pickIcon(_ sender: NSMenuItem) {
        if let icon = Icon(rawValue: sender.tag) { Icon.current = icon }
        refresh()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch { NSSound.beep() }
    }

    @objc private func toggleClaudeLink() {
        if ClaudeLink.shared.isConnected { ClaudeLink.shared.disconnect() } else { ClaudeLink.shared.openLogin() }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - Önizleme (yalnız geliştirme için)

func renderPreview(to path: String, icons: [Icon], percents: [Double]) {
    let barW: CGFloat = 270, barH: CGFloat = 26, rowH: CGFloat = 36, numW: CGFloat = 24, pad: CGFloat = 12, gap: CGFloat = 12, scale: CGFloat = 4
    let panel = PanelView(reading: loadReading())
    let width = pad * 2 + numW + (barW + gap) * CGFloat(percents.count) - gap
    let height = pad * 3 + rowH * CGFloat(icons.count) + panel.bounds.height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    let num: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor(white: 0.2, alpha: 1)]
    let text: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.white]
    for (row, icon) in icons.enumerated() {
        let y0 = height - pad - rowH * CGFloat(row + 1) + (rowH - barH) / 2
        ("\(row + 1)" as NSString).draw(at: NSPoint(x: pad, y: y0 + 4), withAttributes: num)
        for (column, percent) in percents.enumerated() {
            let x0 = pad + numW + CGFloat(column) * (barW + gap)
            NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0, y: y0, width: barW, height: barH), xRadius: 6, yRadius: 6).fill()
            var x = x0 + barW - 10
            let clock = "17:40" as NSString
            let clockSize = clock.size(withAttributes: text)
            x -= clockSize.width
            clock.draw(at: NSPoint(x: x, y: y0 + (barH - clockSize.height) / 2), withAttributes: text)
            x -= 14
            let label = statusTitle(icon, percent: percent) as NSString
            let labelSize = label.size(withAttributes: text)
            x -= labelSize.width
            label.draw(at: NSPoint(x: x, y: y0 + (barH - labelSize.height) / 2), withAttributes: text)
            if let image = statusImage(icon, percent: percent) {
                var shown = image
                if image.isTemplate {
                    shown = NSImage(size: image.size)
                    shown.lockFocus(); image.draw(in: NSRect(origin: .zero, size: image.size)); NSColor.white.set()
                    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop); shown.unlockFocus()
                }
                shown.draw(in: NSRect(x: x - image.size.width, y: y0 + (barH - image.size.height) / 2, width: image.size.width, height: image.size.height))
            }
        }
    }
    // açılan panel
    let panelRect = NSRect(x: pad + numW, y: pad, width: panel.bounds.width, height: panel.bounds.height)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: panelRect, xRadius: 10, yRadius: 10).fill()
    panel.appearance = NSAppearance(named: .aqua)
    if let panelRep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) {
        panel.cacheDisplay(in: panel.bounds, to: panelRep)
        panelRep.draw(in: panelRect)
    }
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

let arguments = CommandLine.arguments

// MARK: - Chrome yerel bağlantısı (eklenti "Kullanım göstergesi" buraya yazar)
// Chrome bu programı "chrome-extension://<kimlik>/" bağımsız değişkeniyle başlatır, stdin'den
// 4 bayt uzunluk + JSON okur, aynı biçimde cevap bekler. Yalnız yüzdeler kabul edilir.

func nativeReply(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    var length = UInt32(body.count).littleEndian
    FileHandle.standardOutput.write(Data(bytes: &length, count: 4))
    FileHandle.standardOutput.write(body)
}

func runNativeHost() {
    let input = FileHandle.standardInput
    while true {
        let head = input.readData(ofLength: 4)
        guard head.count == 4 else { return }
        let length = head.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length > 0, length < 1_000_000 else { return }
        let body = input.readData(ofLength: Int(length))
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { nativeReply(["ok": false]); continue }
        if let error = message["error"] as? String {
            writeLog("tarayıcı: " + error)
            nativeReply(["ok": true]); continue
        }
        let list = message["rateLimits"] as? [[String: Any]] ?? []
        guard saveReading(list, source: "browser", note: message["shape"] as? String) else { nativeReply(["ok": false]); continue }
        nativeReply(["ok": true])
    }
}

if arguments.dropFirst().contains(where: { $0.hasPrefix("chrome-extension://") }) {
    runNativeHost()
    exit(0)
}
if let i = arguments.firstIndex(of: "--render"), i + 1 < arguments.count {
    _ = NSApplication.shared
    let live = loadReading()?.windows.first(where: { $0.kind == "seven_day" })?.percent ?? 14
    renderPreview(to: arguments[i + 1], icons: [Icon.current], percents: [live])
    exit(0)
}
if arguments.contains("--print") {     // tanı: dosyadan ne okunduğunu yazar
    if let reading = loadReading() {
        for w in reading.windows { print("\(windowTitle(w.kind)): \(percentText(w.percent))") }
        print("okuma zamanı: \(reading.updatedAt)")
    } else { print("okuma yok") }
    exit(0)
}
if arguments.contains("--login-off") {  // açılışta başlatmayı kapatır (kaldırırken)
    try? SMAppService.mainApp.unregister()
    exit(0)
}
if arguments.contains("--login-on") {  // açılışta başlatmayı açar
    do { try SMAppService.mainApp.register() } catch { print("hata: \(error)") }
    print(SMAppService.mainApp.status == .enabled ? "acilista baslat: acik" : "acilista baslat: kapali")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
