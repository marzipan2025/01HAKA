import AppKit

// Result of one update check against the GitHub releases feed.
enum UpdateStatus: Equatable {
    case upToDate(current: String)
    case available(latest: String, current: String, dmgURL: URL?)
    case failed
}

// Self-update against the public GitHub releases feed. A newer release offers a
// one-click install: the dmg is downloaded to a temp dir and mounted silently
// (no Finder window); a detached helper then replaces the running bundle in
// place, unmounts, and relaunches. Ported from the 04DOPL / 08FOSE engine —
// this only works because 01haka runs WITHOUT the App Sandbox (a sandboxed app
// can neither write outside its container nor spawn /bin/bash + hdiutil).
// Releases without a dmg asset fall back to opening the releases page.
@MainActor
enum UpdateCheck {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static let releasesPageURL = URL(string: "https://github.com/marzipan2025/01HAKA/releases")!
    private static let latestAPIURL = URL(string: "https://api.github.com/repos/marzipan2025/01HAKA/releases/latest")!

    static func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    static func fetchStatus() async -> UpdateStatus {
        guard let release = await fetchLatestRelease() else { return .failed }
        let latest = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        return isNewer(latest, than: appVersion)
            ? .available(latest: latest, current: appVersion, dmgURL: release.dmgURL)
            : .upToDate(current: appVersion)
    }

    enum UpdateError: Error { case mountFailed }

    // Downloads the release dmg, mounts it silently, verifies the app is inside,
    // then hands off to a detached helper that replaces this bundle and
    // relaunches. `onStatus` drives inline UI text; `onFailure` runs on any
    // error (the caller opens the releases page as a fallback).
    static func downloadAndInstall(_ dmgURL: URL, version: String,
                                   onStatus: @escaping (String) -> Void,
                                   onFailure: @escaping () -> Void) {
        Task {
            onStatus("Downloading…")
            do {
                let (tmp, response) = try await URLSession.shared.download(from: dmgURL)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let dmgDest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("01haka-\(version).dmg")
                try? FileManager.default.removeItem(at: dmgDest)
                try FileManager.default.moveItem(at: tmp, to: dmgDest)

                onStatus("Installing…")
                guard let mountPoint = await attachDMG(at: dmgDest.path) else {
                    throw UpdateError.mountFailed
                }
                let appSource = (mountPoint as NSString).appendingPathComponent("01haka.app")
                guard FileManager.default.fileExists(atPath: appSource) else {
                    _ = await runProcessData("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
                    throw UpdateError.mountFailed
                }

                installAndRelaunch(appSource: appSource,
                                   mountPoint: mountPoint,
                                   dmgPath: dmgDest.path,
                                   version: version)
            } catch {
                onFailure()
            }
        }
    }

    // Writes a detached bash helper that waits for THIS app to quit, replaces
    // the installed bundle with the mounted build, unmounts, deletes the dmg,
    // and relaunches (passing -updatedTo / -updateFailed so the fresh instance
    // can confirm the outcome). A process can't atomically replace and relaunch
    // itself, so this must live in a separate process. The replace is staged
    // (ditto → backup old → move new, restoring on failure) so a mid-copy error
    // can't leave the app missing.
    private static func installAndRelaunch(appSource: String, mountPoint: String,
                                           dmgPath: String, version: String) {
        let dest = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = """
        #!/bin/bash
        APP_PID="$1"; SRC="$2"; DEST="$3"; MOUNT="$4"; DMG="$5"; VERSION="$6"
        for i in $(seq 1 150); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.1; done
        OK=0
        STAGE="${DEST}.update-$$"; BACKUP="${DEST}.old-$$"
        rm -rf "$STAGE" "$BACKUP"
        if ditto "$SRC" "$STAGE"; then
          xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null
          if mv "$DEST" "$BACKUP" 2>/dev/null; then
            if mv "$STAGE" "$DEST" 2>/dev/null; then
              OK=1; rm -rf "$BACKUP"
            else
              mv "$BACKUP" "$DEST" 2>/dev/null
            fi
          fi
        fi
        rm -rf "$STAGE" 2>/dev/null
        hdiutil detach "$MOUNT" -quiet 2>/dev/null
        rm -f "$DMG" 2>/dev/null
        if [ "$OK" = "1" ]; then
          open -a "$DEST" --args -updatedTo "$VERSION"
        else
          open -a "$DEST" --args -updateFailed 1
        fi
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("01haka-install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, pid, appSource, dest, mountPoint, dmgPath, version]
        do { try task.run() } catch { return }
        NSApp.terminate(nil)
    }

    // Mounts a dmg with no Finder window and returns its mount point, parsed
    // from hdiutil's plist output.
    private static func attachDMG(at path: String) async -> String? {
        let data = await runProcessData(
            "/usr/bin/hdiutil",
            ["attach", path, "-nobrowse", "-noverify", "-plist"]
        )
        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    private static func runProcessData(_ launchPath: String, _ args: [String]) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.resume(returning: Data()); return
                }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: out)
            }
        }
    }

    private struct LatestRelease {
        let tag: String
        let dmgURL: URL?
    }

    // Latest (non-draft) release: its tag_name plus the first .dmg asset's
    // download URL, or nil on any failure. Unauthenticated (60 calls/hour/IP).
    private static func fetchLatestRelease() async -> LatestRelease? {
        var request = URLRequest(url: latestAPIURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { return nil }
        let assets = object["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        let dmgURL = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return LatestRelease(tag: tag, dmgURL: dmgURL)
    }

    // Numeric component-wise semver compare ("1.1.10" > "1.1.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
