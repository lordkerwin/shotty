import AppKit

let shottyVersion = "0.1" // bump this when cutting a release; must match the git tag

// Minimal self-updater: reads the latest GitHub Release, compares versions, offers to download.
// No dependency, no auth — works because the repo is public. Full silent install isn't possible
// without an Apple Developer ID (Gatekeeper quarantines an unsigned downloaded app), so we hand the
// user the downloaded .zip in Finder to swap in.
enum Updater {
    static let owner = "lordkerwin"
    static let repo = "shotty"

    /// `verbose` = report "up to date" / errors too (menu). Silent on launch.
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
            let zip = ((json["assets"] as? [[String: Any]]) ?? [])
                .first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
            DispatchQueue.main.async {
                if isNewer(latest, than: shottyVersion) {
                    prompt(latest: latest, page: page, zip: zip)
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

    private static func prompt(latest: String, page: URL?, zip: URL?) {
        let a = NSAlert()
        a.messageText = "There's an update"
        a.informativeText = "Shotty v\(latest) is available — you have v\(shottyVersion)."
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if let zip { download(zip) } else if let page { NSWorkspace.shared.open(page) }
    }

    private static func download(_ url: URL) {
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(url.lastPathComponent)")
        URLSession.shared.downloadTask(with: url) { tmp, _, _ in
            guard let tmp else {
                DispatchQueue.main.async { info("Download failed.") }
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: tmp, to: dest)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                info("Downloaded to your Downloads folder. Unzip it and replace Shotty.app, then reopen.")
            }
        }.resume()
    }

    private static func info(_ text: String) {
        let a = NSAlert(); a.messageText = text; a.addButton(withTitle: "OK"); a.runModal()
    }
}
