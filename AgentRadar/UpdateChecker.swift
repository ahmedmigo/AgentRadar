import Foundation
import AppKit

class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "ahmedmigo"
    private let repoName = "AgentRadar"

    /// Check for updates on launch (with a short delay to not block startup)
    func checkOnLaunch() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            self.checkForUpdate()
        }
    }

    func checkForUpdate() {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            if self.isNewer(remote: remoteVersion, current: currentVersion) {
                DispatchQueue.main.async {
                    self.showUpdateAlert(version: remoteVersion, url: htmlURL)
                }
            }
        }.resume()
    }

    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "AgentRadar Update Available"
        alert.informativeText = "Version \(version) is available. You are running \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }
}
