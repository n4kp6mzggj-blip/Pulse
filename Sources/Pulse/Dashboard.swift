import SwiftUI
import AppKit

// Explicit alias keeps property-wrapper State unambiguous with SDKs that also
// expose a SwiftUI @State macro requiring the full Xcode macro plugin.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let background = Color(red: 0.045, green: 0.059, blue: 0.085)
    static let sidebar = Color(red: 0.062, green: 0.078, blue: 0.11)
    static let card = Color(red: 0.085, green: 0.105, blue: 0.143)
    static let line = Color.white.opacity(0.07)
    static let muted = Color(red: 0.53, green: 0.59, blue: 0.68)
    static let blue = Color(red: 0.37, green: 0.65, blue: 1)
    static let mint = Color(red: 0.36, green: 0.86, blue: 0.72)
    static let purple = Color(red: 0.7, green: 0.58, blue: 1)
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.4)
}

enum Page: String, CaseIterable, Identifiable {
    case overview = "总览", cpu = "处理器", memory = "内存", network = "网络", disk = "存储", power = "电源"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .cpu: return "cpu"; case .memory: return "memorychip"; case .network: return "network"; case .disk: return "internaldrive"; case .power: return "bolt" }
    }
    var english: String {
        switch self { case .overview: return "SYSTEM OVERVIEW"; case .cpu: return "PROCESSOR"; case .memory: return "MEMORY"; case .network: return "NETWORK"; case .disk: return "STORAGE"; case .power: return "POWER & THERMALS" }
    }
}

struct Dashboard: View {
    @EnvironmentObject var monitor: Monitor
    @ViewState private var page: Page = .overview
    @ViewState private var settings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 196)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if page == .overview { overview }
                        else { DetailPage(page: page) }
                    }.padding(24)
                }
                footer
            }
        }
        .background(Palette.background)
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(minWidth: 1020, minHeight: 740)
        .sheet(isPresented: $settings) { settingsPanel }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.mint)
                    .frame(width: 36, height: 36).background(Palette.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                Text("pulse").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.top, 48).padding(.horizontal, 22).padding(.bottom, 37)
            Text("工作空间").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Palette.muted)
                .padding(.horizontal, 25).padding(.bottom, 14)
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.system(size: 15)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        Spacer()
                        if page == item { Capsule().fill(Palette.mint).frame(width: 4, height: 14) }
                    }.foregroundStyle(page == item ? .white : Palette.muted)
                        .padding(.horizontal, 13).frame(height: 42)
                        .background(page == item ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 5)
            }
            Spacer(minLength: 25)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "desktopcomputer"); Text("这台 Mac").fontWeight(.medium) }.font(.system(size: 12))
                Text(monitor.chip).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                Text("\(ProcessInfo.processInfo.activeProcessorCount) 核 · \(Format.bytes(monitor.frame.totalMemory)) 内存")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                HStack(spacing: 5) { Circle().fill(Palette.mint).frame(width: 5, height: 5); Text("本机采集 · 数据不离开设备") }
                    .font(.system(size: 9)).foregroundStyle(Palette.mint.opacity(0.85)).padding(.top, 4)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).padding(12)
            Button { settings = true } label: {
                Label("偏好设置", systemImage: "slider.horizontal.3").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }.buttonStyle(.plain)
        }.background(Palette.sidebar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.english).font(.system(size: 9, weight: .medium)).tracking(2.4).foregroundStyle(Palette.muted)
                HStack(spacing: 10) {
                    Text(page.rawValue).font(.system(size: 25, weight: .semibold))
                    Text("BETA 01").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                        .foregroundStyle(Palette.muted).padding(.horizontal, 6).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line))
                }
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(monitor.paused ? Palette.amber : Palette.mint).frame(width: 6, height: 6)
                Text(monitor.paused ? "已暂停" : "实时监控").font(.system(size: 11))
            }.foregroundStyle(Palette.muted).padding(.trailing, 14)
            Button { monitor.togglePause() } label: {
                Image(systemName: monitor.paused ? "play.fill" : "pause.fill").font(.system(size: 11))
                    .frame(width: 32, height: 32).background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help(monitor.paused ? "继续采集" : "暂停采集")
            Button { exportHistory(monitor.history) } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                    .frame(width: 32, height: 32).background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help("导出最近 15 分钟的 CSV")
        }.padding(.horizontal, 24).padding(.top, 25).padding(.bottom, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                Image(systemName: statusWarning ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 23, weight: .light)).foregroundStyle(statusWarning ? Palette.amber : Palette.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusWarning ? "有指标需要留意" : "一切尽在掌握").font(.system(size: 14, weight: .medium))
                    Text("内存压力\(monitor.pressureText) · 热状态\(monitor.thermalText) · 已运行 \(Format.duration(ProcessInfo.processInfo.systemUptime))")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("LOCAL / LIVE").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            }.padding(14).background(Palette.mint.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.mint.opacity(0.1)))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                metricCard(title: "处理器", tag: "CPU", icon: "cpu", color: Palette.blue, value: Format.percent(monitor.frame.cpu), subtitle: "\(monitor.frame.cores.count) 个逻辑核心", values: monitor.visibleHistory.map { ($0.date, $0.cpu) }, maximum: 1, target: .cpu) {
                    Label("系统总占用", systemImage: "circle.dotted")
                    Spacer()
                    Text("\(Int((1 - (monitor.frame.cpu ?? 0)) * 100))% 空闲")
                }
                metricCard(title: "内存", tag: "MEMORY", icon: "memorychip", color: Palette.purple, value: monitor.frame.memory.map(Format.bytes) ?? "—", subtitle: "/ \(Format.bytes(monitor.frame.totalMemory))", values: monitor.visibleHistory.map { frame in (frame.date, frame.memory.map { $0 / max(1, frame.totalMemory) }) }, maximum: 1, target: .memory) {
                    HStack(spacing: 5) { Circle().fill(pressureColor).frame(width: 5, height: 5); Text("压力\(monitor.pressureText)") }
                    Spacer()
                    Text("交换 \(Format.bytes(monitor.frame.swap))")
                }
                metricCard(title: "网络", tag: "NETWORK", icon: "arrow.up.arrow.down", color: Palette.mint, value: Format.rate(monitor.frame.download), subtitle: "↓ 下载", values: monitor.visibleHistory.map { ($0.date, $0.download) }, maximum: nil, target: .network) {
                    Text("↑ \(Format.rate(monitor.frame.upload))")
                    Spacer()
                    Text(monitor.frame.interface)
                }
                storageCard
            }
            HStack(alignment: .top, spacing: 16) {
                ProcessCard().frame(maxWidth: .infinity)
                powerCard.frame(width: 258)
            }
        }
    }

    private var pressureColor: Color { monitor.frame.pressure == 1 ? Palette.mint : Palette.amber }
    private var statusWarning: Bool {
        monitor.frame.pressure == 2 || monitor.frame.pressure == 4 || monitor.frame.thermal == .serious || monitor.frame.thermal == .critical
    }

    private func metricCard<Bottom: View>(title: String, tag: String, icon: String, color: Color, value: String, subtitle: String, values: [(Date, Double?)], maximum: Double?, target: Page, @ViewBuilder bottom: () -> Bottom) -> some View {
        Button { page = target } label: {
            VStack(alignment: .leading, spacing: 0) {
                CardHeading(title: title, tag: tag, icon: icon, color: color)
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(value).font(.system(size: 31, weight: .medium, design: .rounded)).tracking(-0.8).monospacedDigit()
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                }.padding(.top, 16).lineLimit(1).minimumScaleFactor(0.7)
                Sparkline(points: values, color: color, maximum: maximum, window: monitor.historyMinutes * 60, end: monitor.frame.date)
                    .frame(height: 30).padding(.top, 9)
                HStack { bottom() }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 13)
            }.padding(16).cardSurface()
        }.buttonStyle(.plain).help("查看\(title)详情")
    }

    private var storageCard: some View {
        Button { page = .disk } label: {
            VStack(alignment: .leading, spacing: 0) {
                CardHeading(title: "存储", tag: "STORAGE", icon: "internaldrive", color: Palette.amber)
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(monitor.frame.diskTotal > 0 ? Format.bytes(monitor.frame.diskFree) : "—").font(.system(size: 31, weight: .medium, design: .rounded)).tracking(-0.8)
                    Text("可用空间").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                }.padding(.top, 16).lineLimit(1).minimumScaleFactor(0.7)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.amber.opacity(0.09))
                        Capsule().fill(LinearGradient(colors: [Palette.amber.opacity(0.45), Palette.amber], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * diskRatio)
                    }
                }.frame(height: 9).padding(.top, 20).padding(.bottom, 10)
                HStack { Text("启动磁盘 · APFS"); Spacer(); Text("\(Int(diskRatio * 100))% 已用") }
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 13)
            }.padding(16).cardSurface()
        }.buttonStyle(.plain).help("查看存储详情")
    }
    private var diskRatio: Double { monitor.frame.diskTotal > 0 ? min(1, max(0, 1 - monitor.frame.diskFree / monitor.frame.diskTotal)) : 0 }

    private var powerCard: some View {
        Button { page = .power } label: {
            VStack(alignment: .leading, spacing: 16) {
                CardHeading(title: "电源与热状态", tag: "", icon: "bolt", color: Palette.mint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(monitor.frame.battery == nil ? "交流电" : Format.percent(monitor.frame.battery))
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                    Spacer()
                    Image(systemName: monitor.frame.battery == nil || monitor.frame.pluggedIn ? "powerplug" : "battery.75percent")
                        .font(.system(size: 24, weight: .light)).foregroundStyle(Palette.mint)
                }
                Text(monitor.frame.battery == nil ? "未检测到内置电池" : monitor.frame.charging ? "正在充电" : monitor.frame.pluggedIn ? "电源已连接" : "使用电池供电")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack {
                    Text("系统热状态").foregroundStyle(Palette.muted)
                    Spacer()
                    Text(monitor.thermalText).foregroundStyle(Palette.mint)
                }.font(.system(size: 11))
                Text("来自 macOS 的热压力等级").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(19).cardSurface()
        }.buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(monitor.paused ? "采集已暂停" : "每 \(Int(monitor.interval)) 秒更新")
            Text("·")
            Text("趋势保留 15 分钟")
            Spacer()
            Text("最近采集 \(monitor.frame.date.formatted(date: .omitted, time: .standard))").monospacedDigit()
        }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(.horizontal, 28).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("偏好设置").font(.title2.weight(.semibold))
            Text("按你的节奏查看这台 Mac。").font(.subheadline).foregroundStyle(Palette.muted)
            Picker("采集间隔", selection: $monitor.interval) {
                Text("1 秒").tag(1.0); Text("2 秒").tag(2.0); Text("5 秒").tag(5.0)
            }.pickerStyle(.segmented).onChange(of: monitor.interval) { _, _ in monitor.start() }
            Picker("图表时间范围", selection: $monitor.historyMinutes) {
                Text("1 分钟").tag(1.0); Text("5 分钟").tag(5.0); Text("15 分钟").tag(15.0)
            }.pickerStyle(.segmented)
            Text("历史只保存在内存中，退出后清空。进程列表每 8 秒更新；磁盘容量每 15 秒更新。网络统计汇总 en* 物理接口，不重复计入 VPN 隧道。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
            HStack { Text("Pulse 0.1.0 · MIT 开源").font(.caption).foregroundStyle(Palette.muted); Spacer(); Button("完成") { settings = false }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 430).background(Palette.background).preferredColorScheme(.dark)
    }
}

struct CardHeading: View {
    let title: String
    let tag: String
    let icon: String
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(tag).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
            Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(Palette.muted)
        }
    }
}

extension View {
    func cardSurface() -> some View {
        self.background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line))
    }
}

struct Sparkline: View {
    let points: [(Date, Double?)]
    let color: Color
    var maximum: Double? = nil
    let window: TimeInterval
    let end: Date
    var body: some View {
        Canvas { context, size in
            for fraction in [0.0, 0.5, 1.0] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * fraction))
                line.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(line, with: .color(.white.opacity(0.045)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            let available = points.compactMap { date, value -> (Date, Double)? in value.map { (date, $0) } }
            guard !available.isEmpty else { return }
            let maxValue = maximum ?? max(1024, (available.map(\.1).max() ?? 0) * 1.2)
            let start = end.addingTimeInterval(-window)
            var path = Path()
            var area = Path()
            var lastPoint: CGPoint?
            for (index, item) in available.enumerated() {
                let x = max(0, min(size.width, item.0.timeIntervalSince(start) / window * size.width))
                let y = size.height - min(1, max(0, item.1 / maxValue)) * (size.height - 4) - 2
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point); area.move(to: CGPoint(x: x, y: size.height)); area.addLine(to: point) }
                else { path.addLine(to: point); area.addLine(to: point) }
                lastPoint = point
            }
            if let lastPoint {
                area.addLine(to: CGPoint(x: lastPoint.x, y: size.height)); area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.23), color.opacity(0.01)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: lastPoint.x - 2.5, y: lastPoint.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }.accessibilityLabel("实时趋势图，范围 \(Int(window / 60)) 分钟")
    }
}

struct ProcessCard: View {
    @EnvironmentObject var monitor: Monitor
    @ViewState private var sortCPU = false
    var apps: [AppUsage] { Array((sortCPU ? monitor.processes.sorted { ($0.cpu ?? -1) > ($1.cpu ?? -1) } : monitor.processes).prefix(4)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("资源占用").font(.system(size: 12, weight: .medium))
                Spacer()
                Button { sortCPU.toggle() } label: {
                    HStack(spacing: 4) { Text(sortCPU ? "按 CPU" : "按内存"); Image(systemName: "arrow.up.arrow.down") }.font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.buttonStyle(.plain)
            }.padding(.bottom, 16)
            HStack { Text("进程"); Spacer(); Text(sortCPU ? "CPU¹" : "驻留内存") }
                .font(.system(size: 9)).foregroundStyle(Palette.muted).padding(.bottom, 8)
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(Palette.blue.opacity(0.1)).frame(width: 23, height: 23)
                        .overlay(Text(String(app.name.prefix(1)).uppercased()).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.blue))
                    Text(app.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 10)
                    Text(sortCPU ? Format.percent(app.cpu) : Format.bytes(app.bytes)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }.padding(.vertical, 5)
            }
            if apps.isEmpty { Text("正在读取可访问的进程…").font(.caption).foregroundStyle(Palette.muted).padding(.vertical, 40) }
            Text(sortCPU ? "¹ 单核 = 100%，多线程可超过 100%" : "按单个进程统计，未合并应用辅助进程")
                .font(.system(size: 9)).foregroundStyle(Palette.muted).padding(.top, 9)
        }.padding(19).cardSurface()
    }
}
