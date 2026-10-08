// DevinUsageBar — shows Devin CLI quota usage in the macOS menu bar.
// Data source: SeatManagementService/GetUserStatus (same RPC `devin auth status` uses).
// Auth: windsurf_api_key from ~/.local/share/devin/credentials.toml

import AppKit

let CREDENTIALS_PATH = NSHomeDirectory() + "/.local/share/devin/credentials.toml"
let STATUS_URL = "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus"
let USAGE_PAGE_URL = URL(string: "https://app.devin.ai/settings/usage")!
let REFRESH_SECONDS: TimeInterval = 60

// MARK: - Credentials

enum FetchResult {
    case ok(UsageInfo)
    case noCredentials
    case error(String)
}

struct UsageInfo {
    var planName: String = ""
    var dailyRemaining: Int?
    var weeklyRemaining: Int?
    var dailyReset: Date?
    var weeklyReset: Date?
    var planEnd: Date?
    var overageMicros: String?
}

func loadApiKey() -> String? {
    guard let text = try? String(contentsOfFile: CREDENTIALS_PATH, encoding: .utf8) else { return nil }
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("windsurf_api_key") {
            return line
                .components(separatedBy: "=")
                .dropFirst()
                .joined(separator: "=")
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

// MARK: - Fetch

func fetchUsage(apiKey: String) -> FetchResult {
    var req = URLRequest(url: URL(string: STATUS_URL)!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 15
    let body: [String: Any] = ["metadata": [
        "api_key": apiKey,
        "ide_name": "devin-cli",
        "ide_version": "1.0.0",
        "extension_name": "devin-cli",
        "extension_version": "1.0.0",
    ]]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let sem = DispatchSemaphore(value: 0)
    var out: FetchResult = .error("no response")
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }
        if let err = err { out = .error(err.localizedDescription); return }
        guard let data = data,
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let us = json["userStatus"] as? [String: Any]
        else { out = .error("request failed"); return }

        var info = UsageInfo()
        if let ps = us["planStatus"] as? [String: Any] {
            info.dailyRemaining = ps["dailyQuotaRemainingPercent"] as? Int
            info.weeklyRemaining = ps["weeklyQuotaRemainingPercent"] as? Int
            info.overageMicros = ps["overageBalanceMicros"] as? String
            if let t = (ps["dailyQuotaResetAtUnix"] as? String).flatMap(Int64.init) {
                info.dailyReset = Date(timeIntervalSince1970: TimeInterval(t))
            }
            if let t = (ps["weeklyQuotaResetAtUnix"] as? String).flatMap(Int64.init) {
                info.weeklyReset = Date(timeIntervalSince1970: TimeInterval(t))
            }
            if let s = ps["planEnd"] as? String {
                info.planEnd = ISO8601DateFormatter().date(from: s)
            }
            if let pi = ps["planInfo"] as? [String: Any] {
                info.planName = pi["planName"] as? String ?? ""
            }
        }
        out = .ok(info)
    }.resume()
    sem.wait()
    return out
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var lastInfo: UsageInfo?
    private var lastFetched: Date?
    private var lastError: String?

    func applicationDidFinishLaunching(_: Notification) {
        statusItem.button?.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Devin usage"
        )
        statusItem.button?.imagePosition = .imageLeft
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: REFRESH_SECONDS, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Refresh

    func refresh() {
        DispatchQueue.global().async {
            guard let key = loadApiKey() else {
                DispatchQueue.main.async { self.apply(result: .noCredentials) }
                return
            }
            let result = fetchUsage(apiKey: key)
            DispatchQueue.main.async { self.apply(result: result) }
        }
    }

    private func apply(result: FetchResult) {
        switch result {
        case let .ok(info):
            lastInfo = info
            lastFetched = Date()
            lastError = nil
            updateTitle()
        case .noCredentials:
            lastInfo = nil
            lastError = "credentials.toml が見つかりません"
            updateTitle()
        case let .error(msg):
            lastError = msg
            updateTitle()
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if let d = lastInfo?.dailyRemaining, let w = lastInfo?.weeklyRemaining {
            button.title = " D:\(d)% W:\(w)%"
        } else {
            button.title = lastError == nil ? " --" : " !"
        }
    }

    // MARK: Menu

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func detail(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func menuWillOpen(_: NSMenu) {
        let menu = statusItem.menu!
        menu.removeAllItems()

        if let info = lastInfo {
            if !info.planName.isEmpty { menu.addItem(detail("Plan: \(info.planName)")) }
            if let d = info.dailyRemaining {
                var s = "Daily quota 残り \(d)%"
                if let r = info.dailyReset {
                    s += " (リセット \(Self.timeFmt.string(from: r)))"
                }
                menu.addItem(detail(s))
            }
            if let w = info.weeklyRemaining {
                var s = "Weekly quota 残り \(w)%"
                if let r = info.weeklyReset {
                    s += " (リセット \(Self.timeFmt.string(from: r)))"
                }
                menu.addItem(detail(s))
            }
            if let m = info.overageMicros, let micros = Double(m), micros != 0 {
                menu.addItem(detail(String(format: "Overage balance: $%.2f", micros / 1_000_000)))
            }
            if let end = info.planEnd {
                menu.addItem(detail("Plan 終了: \(Self.timeFmt.string(from: end))"))
            }
            if let f = lastFetched {
                menu.addItem(detail("更新: \(Self.timeFmt.string(from: f))"))
            }
        } else {
            menu.addItem(detail(lastError ?? "データなし"))
        }
        if let e = lastError, lastInfo != nil {
            menu.addItem(detail("最後の取得でエラー: \(e)"))
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "今すぐ更新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let usagePage = NSMenuItem(title: "Usage ページを開く", action: #selector(openUsage), keyEquivalent: "u")
        usagePage.target = self
        menu.addItem(usagePage)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func refreshNow() { refresh() }
    @objc private func openUsage() { NSWorkspace.shared.open(USAGE_PAGE_URL) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
