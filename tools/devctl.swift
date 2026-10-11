// devctl: drive the Dev app (Daylog Dev.app) through its private test channel.
// Nothing goes through the real keyboard and nothing takes focus, so a test can never
// type into whatever app you're using.
//
//   devctl open | close
//   devctl key <keycode> [cmd,shift,opt,ctrl]     e.g. devctl key 40 cmd   (⌘K)
//   devctl type <text>
// After each command the Dev app writes a `test-state …` line to ~/Library/Logs/daylog/app-dev.log.
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: devctl open|close|key <code> [mods]|type <text>"); exit(1)
}
var info: [String: String] = ["cmd": cmd]
if cmd == "key" { info["code"] = args.count > 1 ? args[1] : "0"; info["mods"] = args.count > 2 ? args[2] : "" }
if cmd == "type" { info["text"] = args.dropFirst().joined(separator: " ") }
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.rithvik.daylog.dev.test"), object: nil, userInfo: info, deliverImmediately: true)
