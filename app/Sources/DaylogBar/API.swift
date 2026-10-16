import Foundation

/// HTTP client for the daylog server. The app never touches the database directly;
/// everything goes through the same API that agents use.
enum API {
    /// Real = his log. Dev = the test copy's throwaway server and database (agent tests only).
    enum Env { case real, dev }

    private static let realBase = URL(string: ProcessInfo.processInfo.environment["DAYLOG_API"] ?? "http://127.0.0.1:7878")!
    private static let devBase = URL(string: ProcessInfo.processInfo.environment["DAYLOG_DEV_API"] ?? "http://127.0.0.1:7879")!

    /// Which server the bar talks to: real, or dev inside the test copy.
    static var env: Env = .real

    static func base(_ e: Env? = nil) -> URL { (e ?? env) == .dev ? devBase : realBase }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        return URLSession(configuration: c)
    }()

    /// For the model's reading (/read): a model that was just loaded can take several seconds.
    private static let slowSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    struct Failure: Error, LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    static func get<T: Decodable>(_ path: String, query: [String: String] = [:], env: Env? = nil,
                                  slow: Bool = false) async throws -> T {
        var comps = URLComponents(url: base(env).appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        if slow {
            let (data, resp) = try await slowSession.data(for: URLRequest(url: comps.url!))
            guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw Failure(status: 500, message: "read failed") }
            return try decoder.decode(T.self, from: data)
        }
        return try await send(URLRequest(url: comps.url!))
    }

    @discardableResult
    static func post(_ path: String, _ body: [String: Any] = [:], env: Env? = nil, slow: Bool = false) async throws -> Data {
        var req = URLRequest(url: base(env).appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        if slow {   // the server may wait for the model first
            let (data, resp) = try await slowSession.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw Failure(status: 500, message: "log failed") }
            return data
        }
        return try await raw(req)
    }

    static func delete(_ path: String, env: Env? = nil) async throws {
        var req = URLRequest(url: base(env).appendingPathComponent(path))
        req.httpMethod = "DELETE"
        _ = try await raw(req)
    }

    private static func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        try decoder.decode(T.self, from: try await raw(req))
    }

    private static func raw(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"]
            throw Failure(status: code, message: "\(code): \(detail.map { "\($0)" } ?? "request failed")")
        }
        return data
    }
}

// MARK: - Models (mirror the server's JSON)

struct NowState: Decodable {
    let now: String
    let timer: TimerInfo?
    let activity: ActivityInfo?
    let meeting: Segment?
    let ghost: GhostInfo?
    var onBreak: BreakInfo? = nil
    var states: [StateInfo]? = nil
}

/// which version is running, and (owner only) what's new in it.
struct Health: Decodable {
    let version: String?
    let owner: Bool?
    let release: ReleaseInfo?
    let code: String?
    let cd: CDStatus?
}

/// CD's last result at unlock (scripts/autorelease.sh): a skip stays in the bar, with why and the fix.
struct CDStatus: Decodable, Equatable {
    let state: String
    var reason: String = ""
    var fix: String = ""
}

struct ReleaseInfo: Decodable, Equatable {
    let version: String
    var new: [String] = []
    var `try`: [String] = []
    var released_at: String? = nil
}

struct GhostInfo: Decodable, Equatable {
    let id: String
    let status: String
    let start: String
    var resume: String? = nil  // set when this ghost came from a break he didn't return from
}

/// ⌘B walk / ⌘⇧B smoke: the task is paused and resumes when he's back.
struct BreakInfo: Decodable, Equatable {
    let id: String
    let kind: String   // "walk" or "smoke"
    let label: String
    let start: String
    let resume: String?
}

/// A substance that's on (intoxicated, high, caffeinated). Global, not tied to a task.
struct StateInfo: Decodable, Equatable {
    let state: String
    let since: String
}

struct TimerInfo: Decodable, Equatable {
    let id: String
    let label: String
    let start: String
    var focus: Int? = nil  // 0 off · 1 focused · 2 deep · 3 hyperfocus
    var word: String? = nil  // the model's one word for the pill ("Building"); nil = show the title
}

struct ActivityInfo: Decodable {
    let app: String?
    let since: String?
    let awaySince: String?
}

struct Segment: Decodable {
    let id: String?
    let start: String
    let end: String?
    let label: String?
    let source: String?
    let type: String?
    let running: Bool?
    let app: String?

    /// Stable key for SwiftUI lists (activity segments have no server id).
    var uid: String { id ?? "\(start)-\(app ?? "")" }
    var startDate: Date { Time.parse(start) }
    var endDate: Date { end.map(Time.parse) ?? Date() }
}

/// What the server would do with the current line (live preview).
struct LinePreview: Decodable, Equatable {
    let action: String  // "log", "timer" or "command" (typed: "smoke break", "deep focus"…)
    let label: String
    let start: String?
    let end: String?
    let minutes: Int?
    let untilNow: Bool?
    var text: String? = nil      // the line this preview is for (to ignore a stale preview)
    var also: [String]? = nil    // substances a task line turns on/off: ["high on"]
    var by: String? = nil        // the local model that read the line (nil: the rules did)
    var why: String? = nil       // the model's one-line reason ("its thinking"), shown under the preview
}

/// One stop when scrolling back: a logged block, a meeting, or an untracked gap.
struct HistoryItem: Decodable, Equatable {
    let kind: String  // "entry", "timer", "meeting", "gap", "note"
    let id: String?
    let label: String?
    let start: String
    let end: String
    let minutes: Int
    let during: String?  // notes: the task running when it was written
    var focusPeak: Int? = nil  // deepest focus tier reached during this block

    var key: String { "\(kind)-\(start)" }
    var isGap: Bool { kind == "gap" }
    var isNote: Bool { kind == "note" }
    var startDate: Date { Time.parse(start) }
    var endDate: Date { Time.parse(end) }
    var range: String { "\(Time.clockString(startDate)) – \(Time.clockString(endDate))" }
}

struct HistoryPage: Decodable {
    let items: [HistoryItem]
}

struct Summary: Decodable {
    let trackedMinutes: Int
    let untrackedMinutes: Int
    let computerActiveMinutes: Int
}

/// How a title reads on the bar: what he typed, tidied for display only (the log keeps his words).
/// "daylog backend." → "Daylog backend"; runs of spaces collapse; trailing punctuation goes.
enum Title {
    static func display(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        while let last = t.last, ".,;:'\"…".contains(last) { t.removeLast() }
        while let first = t.first, "…'\"".contains(first) { t.removeFirst() }
        guard let f = t.first else { return raw }
        return f.uppercased() + t.dropFirst()
    }
}

enum Time {
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String) -> Date { iso.date(from: s) ?? isoFrac.date(from: s) ?? Date() }
    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func clockString(_ d: Date) -> String { clock.string(from: d) }
    static func dayString(_ d: Date) -> String { day.string(from: d) }

    static func duration(_ seconds: TimeInterval, withSeconds: Bool = false) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if withSeconds { return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec) }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func minutes(_ m: Int) -> String { duration(TimeInterval(m * 60)) }
}

extension Segment: Equatable {
    static func == (a: Segment, b: Segment) -> Bool { a.uid == b.uid && a.end == b.end }
}
