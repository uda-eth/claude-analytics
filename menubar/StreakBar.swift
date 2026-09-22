// StreakBar: a menu bar item showing the combined Claude streak from docs/data.json.
// Reads the published Pages copy, falls back to the local checkout, and recounts the
// streak against the local calendar so it rolls over at your midnight, not the build's.
import AppKit

let remoteURL = URL(string: "https://uda-eth.github.io/claude-analytics/data.json")!
let localURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("dev/claude-analytics/docs/data.json")
let dashboardURL = URL(string: "https://uda-eth.github.io/claude-analytics/")!
let refreshSeconds: TimeInterval = 15 * 60

struct Stats {
    var current = 0, longest = 0, todayMessages = 0
    var accounts: [(name: String, current: Int)] = []
    var generatedAt = ""
}

func dayString(_ d: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

/// Same rule as scripts/build.py: current still counts if today is empty but yesterday wasn't.
func currentStreak(_ days: Set<String>) -> Int {
    let cal = Calendar.current
    var d = Date()
    if !days.contains(dayString(d)) { d = cal.date(byAdding: .day, value: -1, to: d)! }
    var n = 0
    while days.contains(dayString(d)) {
        n += 1
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return n
}

func parse(_ data: Data) -> Stats? {
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let days = j["days"] as? [String: [String: Any]] else { return nil }
    var s = Stats()
    let active = Set(days.filter { ($0.value["messages"] as? Int ?? 0) > 0 }.keys)
    s.current = currentStreak(active)
    s.longest = max(j["longestStreak"] as? Int ?? 0, s.current)
    s.todayMessages = days[dayString(Date())]?["messages"] as? Int ?? 0
    s.generatedAt = j["generatedAt"] as? String ?? ""
    if let accts = j["accounts"] as? [String: [String: Any]] {
        s.accounts = accts.keys.sorted().map { name in
            let mine = Set(days.filter { (($0.value["byAccount"] as? [String: Int])?[name] ?? 0) > 0 }.keys)
            return (name, currentStreak(mine))
        }
    }
    return s
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        item.autosaveName = "StreakBar"
        render(nil)
        refresh()
        // Log where macOS placed the item; a notch-covered item reports occluded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [item] in
            let w = item.button?.window
            FileHandle.standardError.write("item frame=\(w.map { NSStringFromRect($0.frame) } ?? "none") onScreen=\(w?.occlusionState.contains(.visible) ?? false)\n".data(using: .utf8)!)
        }
        timer = Timer.scheduledTimer(withTimeInterval: refreshSeconds, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func refresh() {
        var req = URLRequest(url: remoteURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let stats = data.flatMap(parse) ?? (try? Data(contentsOf: localURL)).flatMap(parse)
            DispatchQueue.main.async { self.render(stats) }
        }.resume()
    }

    func render(_ s: Stats?) {
        if let button = item.button {
            let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Claude streak")
            flame?.isTemplate = true
            button.image = flame
            button.imagePosition = .imageLeading
            button.title = s.map { " \($0.current)d" } ?? " –"
            button.toolTip = "Combined Claude streak"
        }

        let menu = NSMenu()
        func info(_ t: String) { let m = NSMenuItem(title: t, action: nil, keyEquivalent: ""); m.isEnabled = false; menu.addItem(m) }
        if let s = s {
            info("Combined streak: \(s.current) days")
            info("Longest: \(s.longest) days")
            info("Today: \(s.todayMessages.formatted()) messages")
            menu.addItem(.separator())
            for a in s.accounts { info("\(a.name): \(a.current) days") }
            if !s.generatedAt.isEmpty { menu.addItem(.separator()); info("Built \(s.generatedAt.prefix(16).replacingOccurrences(of: "T", with: " ")) UTC") }
        } else {
            info("Loading…")
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit StreakBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for m in menu.items where m.action != nil && m.action != #selector(NSApplication.terminate(_:)) { m.target = self }
        item.menu = menu
    }

    @objc func openDashboard() { NSWorkspace.shared.open(dashboardURL) }
}

// `StreakBar --print` prints what the menu would show and exits (for checking without the UI).
if CommandLine.arguments.contains("--print") {
    let data = (try? Data(contentsOf: remoteURL)) ?? (try? Data(contentsOf: localURL))
    guard let s = data.flatMap(parse) else { print("no data"); exit(1) }
    print("streak \(s.current)d, longest \(s.longest)d, today \(s.todayMessages) msgs,",
          s.accounts.map { "\($0.name) \($0.current)d" }.joined(separator: ", "))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
