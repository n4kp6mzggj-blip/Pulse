import SwiftUI

struct DetailPage: View {
    @EnvironmentObject var monitor: Monitor
    let page: Page
    private var frame: Frame { monitor.frame }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch page {
            case .cpu: cpu
            case .memory: memory
            case .network: network
            case .disk: disk
            case .power: power
            case .overview: EmptyView()
            }
        }
    }

    private var cpu: some View {
        VStack(alignment: .leading, spacing: 22) {
            chart(title: "系统 CPU 占用", value: Format.percent(frame.cpu), color: Palette.blue, points: monitor.visibleHistory.map { ($0.date, $0.cpu) }, max: 1)
            VStack(alignment: .leading, spacing: 20) {
                Text("每核心负载").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 18)], spacing: 22) {
                    ForEach(Array(frame.cores.enumerated()), id: \.offset) { index, load in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("CORE \(index + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted); Spacer(); Text(Format.percent(load)).font(.system(size: 11, design: .monospaced)) }
                            ProgressView(value: load).tint(Palette.blue)
                        }
                    }
                }
                Text("按 macOS 返回的逻辑核心顺序显示；总占用以全机 100% 归一化。").font(.caption).foregroundStyle(Palette.muted)
            }.padding(23).cardSurface()
            ProcessCard()
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 22) {
            chart(title: "物理内存占用", value: frame.memory.map(Format.bytes) ?? "—", color: Palette.purple, points: monitor.visibleHistory.map { ($0.date, $0.memory) }, max: frame.totalMemory)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                stat("物理内存", Format.bytes(frame.totalMemory), "已安装容量", Palette.purple)
                stat("内存压力", monitor.pressureText, "macOS 压力等级", frame.pressure == 1 ? Palette.mint : Palette.amber)
                stat("交换空间", Format.bytes(frame.swap), "磁盘上的交换使用量", Palette.amber)
                stat("固定内存", Format.bytes(frame.wired), "Wired · 不可换出", Palette.blue)
                stat("压缩内存", Format.bytes(frame.compressed), "压缩后的物理占用", Palette.purple)
                stat("文件缓存", Format.bytes(frame.cache), "可回收及文件支持页面", Palette.mint)
            }
            Text("判断内存是否够用，优先看“内存压力”和交换空间；较高的内存使用比例不一定表示异常。这里的已用内存扣除了可回收缓存。").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(6)
            ProcessCard()
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 22) {
            chart(title: "下载速率 · 所有 en* 物理接口", value: Format.rate(frame.download), color: Palette.mint, points: monitor.visibleHistory.map { ($0.date, $0.download) })
            chart(title: "上传速率 · 所有 en* 物理接口", value: Format.rate(frame.upload), color: Palette.blue, points: monitor.visibleHistory.map { ($0.date, $0.upload) })
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                stat("主物理接口", frame.interface, "局域网地址 \(frame.address)", Palette.mint)
                stat("本次监控流量", "↓ \(Format.bytes(frame.sessionDown))", "↑ \(Format.bytes(frame.sessionUp)) · 启动后累计", Palette.blue)
            }
            Text("流量在本机接口层统计，包含所有应用。VPN 虚拟隧道不重复累计；如果设备只使用非 en* 接口，该接口不会包含在总速率中。暂停期间的流量会在恢复后计入累计，恢复首个速率为暂停期间平均值。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
        }
    }

    private var disk: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 25) {
                CardHeading(title: "启动磁盘", tag: "APFS DATA VOLUME", icon: "internaldrive", color: Palette.amber)
                HStack(alignment: .firstTextBaseline) {
                    Text(frame.diskTotal > 0 ? Format.bytes(frame.diskFree) : "—").font(.system(size: 48, weight: .medium, design: .rounded))
                    Text("可用").foregroundStyle(Palette.muted)
                    Spacer()
                }
                ProgressView(value: frame.diskTotal > 0 ? 1 - frame.diskFree / frame.diskTotal : 0).tint(Palette.amber)
                HStack { Text("已用 \(Format.bytes(frame.diskTotal - frame.diskFree))"); Spacer(); Text("总计 \(Format.bytes(frame.diskTotal))") }.font(.caption).foregroundStyle(Palette.muted)
            }.padding(25).cardSurface()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                stat("可用比例", frame.diskTotal > 0 ? Format.percent(frame.diskFree / frame.diskTotal) : "—", "每 15 秒刷新容量", Palette.amber)
                stat("数据卷", "Macintosh Data", "/System/Volumes/Data", Palette.blue)
            }
            Text("显示 APFS 数据卷的总容量与当前可用空间。共享容器、快照和可清理空间会让数值与 Finder 的“可用”略有不同。此版本尚未提供磁盘读写速率和外置磁盘列表。").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(6)
        }
    }

    private var power: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                stat("电池电量", frame.battery.map { Format.percent($0) } ?? "无内置电池", frame.battery == nil ? "这台 Mac 使用外接电源" : frame.charging ? "正在充电" : frame.pluggedIn ? "已连接电源" : "使用电池供电", Palette.mint)
                stat("系统热状态", monitor.thermalText, "由 macOS 报告的热压力", frame.thermal == .nominal ? Palette.mint : Palette.amber)
                stat("电源估计时间", frame.batteryMinutes.map { Format.duration(Double($0) * 60) } ?? "暂无估计", frame.charging ? "距离充满" : "电池剩余使用时间", Palette.blue)
                stat("系统运行时间", Format.duration(ProcessInfo.processInfo.systemUptime), "自上次启动以来", Palette.purple)
            }
            if frame.battery != nil {
                chart(title: "电池电量趋势", value: Format.percent(frame.battery), color: Palette.mint, points: monitor.visibleHistory.map { ($0.date, $0.battery) }, max: 1)
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("关于温度与风扇", systemImage: "thermometer.medium").font(.headline)
                Text("当前显示 macOS 的热压力等级，并非摄氏温度。温度传感器、风扇转速和 GPU 负载尚未接入；这些指标需要针对芯片与机型分别验证。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(6)
            }.padding(24).cardSurface()
        }
    }

    private func stat(_ title: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).cardSurface()
    }

    private func chart(title: String, value: String, color: Color, points: [(Date, Double?)], max: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 13) {
                    Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(value).font(.system(size: 37, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Spacer()
                Picker("时间范围", selection: $monitor.historyMinutes) {
                    Text("1 分").tag(1.0); Text("5 分").tag(5.0); Text("15 分").tag(15.0)
                }.pickerStyle(.segmented).frame(width: 180)
            }
            Sparkline(points: points, color: color, maximum: max, window: monitor.historyMinutes * 60, end: frame.date).frame(height: 150)
            HStack { Text("\(Int(monitor.historyMinutes)) 分钟前"); Spacer(); Text(monitor.paused ? "已暂停" : "现在") }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(24).cardSurface()
    }
}
