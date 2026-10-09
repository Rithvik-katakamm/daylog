import SwiftUI

enum Theme {
    static let accent = Color(red: 0.36, green: 0.96, blue: 0.78)      // neon mint: your claims
    static let meeting = Color(red: 0.70, green: 0.55, blue: 1.0)      // violet: ground-truth meetings
    static let text = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.45)
    static let faint = Color.white.opacity(0.08)

    /// A stable, low-saturation color per app for the activity lane.
    static func app(_ name: String?) -> Color {
        let h = abs((name ?? "?").unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) })
        return Color(hue: Double(h % 360) / 360, saturation: 0.45, brightness: 0.85)
    }
}

// MARK: - The pill on the side of the screen

struct HandleView: View {
    @ObservedObject var store: Store

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(store.timer != nil ? Theme.accent.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1)
            VStack(spacing: 4) {
                Circle()
                    .fill(store.serverDown ? Color.red.opacity(0.8) : (store.timer != nil ? Theme.accent : Color.white.opacity(0.35)))
                    .frame(width: 8, height: 8)
                    .shadow(color: store.timer != nil ? Theme.accent : .clear, radius: 4)
                if let t = store.timer {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start))))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Capsule())
    }
}

// MARK: - The panel

struct PanelView: View {
    @ObservedObject var store: Store
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            timerCard
            inputArea
            Divider().overlay(Theme.faint)
            dayHeader
            DayView(store: store)
            if let msg = store.serverDown ? "Server not reachable on 127.0.0.1:7878" : store.error {
                Text(msg).font(.caption).foregroundStyle(.red.opacity(0.85))
            }
        }
        .padding(14)
        .frame(width: 360, height: 600)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .environment(\.colorScheme, .dark)
        .onChange(of: store.focusRequest) { inputFocused = true }
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack {
            Text("daylog").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            if let s = store.summary {
                Text("\(Time.minutes(s.trackedMinutes)) logged · \(Time.minutes(s.computerActiveMinutes)) on Mac")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder private var timerCard: some View {
        if let t = store.timer {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
                    Text(t.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Time.duration(ctx.date.timeIntervalSince(Time.parse(t.start)), withSeconds: true))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
                Button(action: store.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Stop timer")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.35)))
        } else {
            Text("Nothing running").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(store.timer == nil ? "What are you doing?  ⏎ starts a timer" : "Switch to…  ⏎", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                .focused($inputFocused)
                .onSubmit { store.start(input); input = "" }
            HStack(spacing: 6) {
                Text("Already did it:").font(.system(size: 11)).foregroundStyle(Theme.muted)
                ForEach([(15, "15m"), (30, "30m"), (60, "1h"), (120, "2h")], id: \.0) { m, name in
                    Button(name) { store.logPast(input, minutes: m); input = "" }
                        .buttonStyle(Chip())
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 8) {
            Button { store.shiftDay(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            Text(store.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
            Button { store.shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(store.isToday)
            Spacer()
            if !store.isToday { Button("Today") { store.goToday() }.buttonStyle(Chip()) }
            Text("drag to log").font(.system(size: 10)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.muted)
    }
}

struct Chip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .foregroundStyle(Theme.text)
    }
}

// MARK: - The day timeline

struct DayView: View {
    @ObservedObject var store: Store
    private let hourHeight: CGFloat = 44
    private let gutter: CGFloat = 40
    private let activityWidth: CGFloat = 8

    @State private var dragFrom: CGFloat?
    @State private var dragTo: CGFloat?
    @State private var pending: (Date, Date)?
    @State private var pendingLabel = ""
    @FocusState private var labelFocused: Bool

    private var dayStart: Date { store.day }
    private var totalHeight: CGFloat { hourHeight * 24 }

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    GeometryReader { geo in
                        canvas(width: geo.size.width)
                    }
                    .frame(height: totalHeight)
                    .background(alignment: .top) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { h in Color.clear.frame(height: hourHeight).id(h) }
                        }
                    }
                }
                .onAppear { scrollToNow(proxy) }
                .onChange(of: store.day) { scrollToNow(proxy) }
            }
            if let (from, to) = pending { labelBar(from, to) }
        }
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        let hour = store.isToday ? Calendar.current.component(.hour, from: Date()) : 9
        DispatchQueue.main.async { proxy.scrollTo(max(0, hour - 3), anchor: .top) }
    }

    private func y(_ d: Date) -> CGFloat {
        CGFloat(d.timeIntervalSince(dayStart) / 3600) * hourHeight
    }

    private func date(_ y: CGFloat) -> Date {
        let secs = Double(min(max(y, 0), totalHeight) / hourHeight) * 3600
        let snapped = (secs / 300).rounded() * 300  // snap to 5 minutes
        return dayStart.addingTimeInterval(snapped)
    }

    private func canvas(width: CGFloat) -> some View {
        let lane = gutter + activityWidth + 6
        let blockWidth = width - lane - 4
        return ZStack(alignment: .topLeading) {
            // hour grid
            ForEach(0..<24, id: \.self) { h in
                let label = h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p"
                Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted)
                    .frame(width: gutter - 6, alignment: .trailing)
                    .offset(y: CGFloat(h) * hourHeight - 5)
                Rectangle().fill(Theme.faint).frame(width: width - gutter, height: 1)
                    .offset(x: gutter, y: CGFloat(h) * hourHeight)
            }

            // activity lane: what the Mac saw (faint, observational)
            ForEach(store.timeline?.activity ?? [], id: \.uid) { s in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.app(s.app).opacity(0.75))
                    .frame(width: activityWidth, height: max(2, y(s.endDate) - y(s.startDate)))
                    .offset(x: gutter, y: y(s.startDate))
                    .help("\(s.app ?? "?") · \(Time.clockString(s.startDate))–\(Time.clockString(s.endDate))")
            }

            // meetings: ground truth from Wispr
            ForEach(store.timeline?.meetings ?? [], id: \.uid) { s in
                block(s, color: Theme.meeting, x: lane, width: blockWidth, deletable: false)
            }

            // claims: what you logged
            ForEach(store.timeline?.claims ?? [], id: \.uid) { s in
                block(s, color: Theme.accent, x: lane, width: blockWidth, deletable: true)
            }

            // drag selection
            if let a = dragFrom, let b = dragTo {
                let top = min(a, b), h = abs(b - a)
                RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: blockWidth, height: max(h, 2))
                    .offset(x: lane, y: top)
                Text("\(Time.clockString(date(top)))–\(Time.clockString(date(top + h)))")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                    .offset(x: lane + 6, y: top + 3)
            }

            // now line
            if store.isToday {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Rectangle().fill(Color.red.opacity(0.8)).frame(width: width - gutter, height: 1)
                        .offset(x: gutter, y: y(ctx.date))
                }
            }
        }
        .frame(width: width, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    dragFrom = v.startLocation.y
                    dragTo = min(v.location.y, store.isToday ? y(Date()) : totalHeight)
                }
                .onEnded { _ in
                    if let a = dragFrom, let b = dragTo {
                        let from = date(min(a, b)), to = date(max(a, b))
                        if to > from {
                            pending = (from, to)
                            pendingLabel = ""
                            labelFocused = true
                        }
                    }
                    dragFrom = nil; dragTo = nil
                }
        )
    }

    private func block(_ s: Segment, color: Color, x: CGFloat, width: CGFloat, deletable: Bool) -> some View {
        let top = y(s.startDate)
        let h = max(3, y(s.endDate) - top)
        let range = "\(Time.clockString(s.startDate))–\(s.running == true ? "now" : Time.clockString(s.endDate))"
        return RoundedRectangle(cornerRadius: 5)
            .fill(color.opacity(0.22))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
            .overlay(alignment: .topLeading) {
                if h >= 14 {
                    Text(s.label ?? "")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text)
                        .lineLimit(h >= 28 ? 2 : 1).padding(.leading, 6).padding(.top, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(width: width, height: h)
            .offset(x: x, y: top)
            .help("\(s.label ?? "") · \(range)")
            .contextMenu {
                if deletable {
                    Button("Delete “\(s.label ?? "")”", role: .destructive) { store.delete(s) }
                }
            }
    }

    private func labelBar(_ from: Date, _ to: Date) -> some View {
        HStack(spacing: 6) {
            Text("\(Time.clockString(from))–\(Time.clockString(to))")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            TextField("What were you doing?", text: $pendingLabel)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($labelFocused)
                .onSubmit { store.log(pendingLabel, from: from, to: to); pending = nil }
            Button("Cancel") { pending = nil }.buttonStyle(Chip())
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08)))
        .onExitCommand { pending = nil }
    }
}
