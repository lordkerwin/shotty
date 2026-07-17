import AppKit

let shottyVersion = "0.3" // bump this when cutting a release; must match the git tag

// Checks the latest GitHub Release on launch. If a newer version exists, shows a dialog that links to
// the release page — the app never downloads anything. Dismissing it remembers that version so the
// user isn't nagged again until an even newer release appears.
enum Updater {
    static let owner = "lordkerwin"
    static let repo = "shotty"
    private static let skippedKey = "skippedVersion"

    /// `verbose` (menu "Check for Updates…") always reports and ignores the remembered dismissal.
    /// Silent (launch) stays quiet when up to date or when this version was already dismissed.
    static func check(verbose: Bool) {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if verbose { DispatchQueue.main.async { info("Couldn't check for updates right now.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String).flatMap(URL.init)
            DispatchQueue.main.async {
                if isNewer(latest, than: shottyVersion) {
                    if !verbose, UserDefaults.standard.string(forKey: skippedKey) == latest { return }
                    prompt(latest: latest, page: page)
                } else if verbose {
                    info("You're up to date (v\(shottyVersion)).")
                }
            }
        }.resume()
    }

    // Dotted numeric compare: "0.10" > "0.9" > "0.1".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) where (i < pa.count ? pa[i] : 0) != (i < pb.count ? pb[i] : 0) {
            return (i < pa.count ? pa[i] : 0) > (i < pb.count ? pb[i] : 0)
        }
        return false
    }

    private static func prompt(latest: String, page: URL?) {
        let a = NSAlert()
        a.messageText = "Shotty v\(latest) is available"
        a.informativeText = "You have v\(shottyVersion). Open the release page on GitHub to download it."
        a.addButton(withTitle: "View on GitHub")
        a.addButton(withTitle: "Ignore")
        NSApp.activate(ignoringOtherApps: true)
        let resp = a.runModal()
        UserDefaults.standard.set(latest, forKey: skippedKey) // don't nag again until a newer version
        if resp == .alertFirstButtonReturn, let page { NSWorkspace.shared.open(page) }
    }

    private static func info(_ text: String) {
        let a = NSAlert(); a.messageText = text; a.addButton(withTitle: "OK"); a.runModal()
    }
}
