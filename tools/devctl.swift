// devctl: drive the test copy (.build/Daylog Test.app, built by scripts/test-copy.sh) through its private test channel.
// Nothing goes through the real keyboard and nothing takes focus, so a test can never
// type into whatever app you're using.
//
//   devctl start | stop          start the test copy + its server headless (off-screen, silent) / stop both
//   devctl open | close
//   devctl snap [name]           save a PNG of the bar to ~/Library/Logs/daylog/snapshots/<name>.png
//   devctl key <keycode> [cmd,shift,opt,ctrl]     e.g. devctl key 40 cmd   (⌘K)
//   devctl type <text>
// After each command the test copy writes a `test-state …` line to ~/Library/Logs/daylog/app-dev.log.
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: devctl start|stop|open|close|snap [name]|key <code> [mods]|type <text>"); exit(1)
}
func run(_ path: String, _ arguments: [String], quiet: Bool = false) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
    if quiet { p.standardError = FileHandle.nullDevice }
    try? p.run(); p.waitUntilExit()
}
// Everything lives next to devctl in the repo's .build/ (one Day Log on his Mac; the test copy and its
// :7879 server exist only between `start` and `stop`).
let build = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
let devApp = build.appendingPathComponent("Daylog Test.app").path
let devAgent = build.appendingPathComponent("com.rithvik.daylog.dev.plist").path
let gui = "gui/\(getuid())"
if cmd == "start" {  // headless by default (his testing preference, Oct 13): never on his screens
    run("/bin/launchctl", ["bootstrap", gui, devAgent], quiet: true)  // fails quietly if already running
    run("/usr/bin/pkill", ["-f", "Daylog Test.app"])
    run("/usr/bin/open", ["-g", "-n", "--env", "DAYLOG_HEADLESS=1", devApp])
    print("test copy started headless"); exit(0)
}
if cmd == "stop" {
    run("/usr/bin/pkill", ["-f", "Daylog Test.app"])
    run("/bin/launchctl", ["bootout", "\(gui)/com.rithvik.daylog.dev"])
    print("test copy and its server stopped"); exit(0)
}
var info: [String: String] = ["cmd": cmd]
if cmd == "key" { info["code"] = args.count > 1 ? args[1] : "0"; info["mods"] = args.count > 2 ? args[2] : "" }
if cmd == "type" { info["text"] = args.dropFirst().joined(separator: " ") }
if cmd == "snap" { info["name"] = args.count > 1 ? args[1] : "latest" }
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.rithvik.daylog.dev.test"), object: nil, userInfo: info, deliverImmediately: true)
