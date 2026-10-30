// Updater — Widget Bar's Update from GitHub: pulls the latest code into the checkout the
// apps were built from (build.sh writes its path into every Info.plist as SourceFolder),
// then rebuilds and reinstalls the apps already in ~/Applications with build.sh --update.
// The work runs as a detached shell script writing to a log, since the update quits and
// reopens Widget Bar itself partway through. The script posts a notification when it's
// done, and opens the log in TextEdit if anything failed.

import AppKit

@MainActor
enum Updater {
    static let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Widget Bar Update.log")
    /// Holds the running script's process id, so a second update waits for the first.
    private static let pidFile = log.deletingPathExtension().appendingPathExtension("pid")

    static func confirmAndRun() {
        // After the menu that chose it has closed, and with the app forward so the alert
        // can be answered from the keyboard.
        DispatchQueue.main.async { MainActor.assumeIsolated { run() } }
    }

    private static func run() {
        NSApp.activate()
        guard let folder = Bundle.main.object(forInfoDictionaryKey: "SourceFolder") as? String,
              FileManager.default.fileExists(atPath: folder + "/.git"),
              FileManager.default.fileExists(atPath: folder + "/desktop_widget/build.sh")
        else {
            return tell("Widget Bar doesn't know where its code is",
                        "Build it once from a checkout of the repository with desktop_widget/build.sh, and it will remember that folder.")
        }
        if isRunning {
            return tell("An update is already running", "It posts a notification when it's done.")
        }

        let alert = NSAlert()
        alert.messageText = "Update from GitHub?"
        alert.informativeText = """
            Pulls the latest code into \((folder as NSString).abbreviatingWithTildeInPath), then rebuilds \
            the apps installed in ~/Applications, which takes a minute or two. Apps that are running \
            quit and reopen: Command Bar's shell session ends, and Markdown Editor closes without \
            saving, so save your work first.
            """
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script, "update", folder, log.path, pidFile.path]
        // Nothing tied to Widget Bar, so the script carries on when build.sh restarts it.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            tell("The update couldn't start", error.localizedDescription)
        }
    }

    private static var isRunning: Bool {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0
    }

    private static func tell(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    /// $1 the checkout, $2 the log, $3 the pid file. Only fast-forwards, so local commits
    /// or a diverged branch stop it with the reason in the log rather than a merge.
    private static let script = #"""
        cd "$1" || exit 1
        echo $$ > "$3"
        trap 'rm -f "$3"' EXIT
        notify() {
          osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "Widget Bar"' \
            -e 'end run' "$1"
        }
        (
          echo "Update from GitHub, $(date)"
          before=$(git rev-parse HEAD)
          git pull --ff-only || exit 1
          if [[ $(git rev-parse HEAD) == $before ]]; then
            echo "Already up to date."
            exit 2
          fi
          git log --oneline $before..HEAD
          desktop_widget/build.sh --update
        ) > "$2" 2>&1
        case $? in
          0) notify "Updated to $(git log -1 --format=%s)" ;;
          2) notify "Already up to date." ;;
          *) notify "The update failed. The log has the details."; open -e "$2" ;;
        esac
        """#
}
