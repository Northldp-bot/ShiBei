import SwiftUI
import SwiftData

@MainActor
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(CacheManager.self) private var cache

    @AppStorage("autoCache") private var autoCache = false
    @AppStorage("downloadQuality") private var downloadQuality = "1080P"
    @AppStorage("saveLiveAsLivePhoto") private var saveLiveAsLivePhoto = true
    @AppStorage("autoTagByPlatform") private var autoTagByPlatform = true
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent = 3

    @State private var showShortcutsHelp = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("自动缓存新收藏", isOn: $autoCache)
                    Picker("默认清晰度", selection: $downloadQuality) {
                        Text("最高").tag("最高")
                        Text("1080P").tag("1080P")
                        Text("720P").tag("720P")
                    }
                    Toggle("按平台自动打标签", isOn: $autoTagByPlatform)
                    NavigationLink("标签管理") {
                        TagManagerView()
                    }
                } header: {
                    Text("收藏")
                } footer: {
                    Text("自动缓存会在解析成功后立即下载全部媒体，仅建议在 Wi-Fi 下开启。")
                }

                Section {
                    Toggle("实况图在相册中保留为实况", isOn: $saveLiveAsLivePhoto)
                    LabeledContent("B 站音视频合并", value: "自动")
                    Stepper("同时下载 \(maxConcurrent) 项", value: $maxConcurrent, in: 1...6)
                    NavigationLink("登录态 Cookie") {
                        AdvancedSettingsView()
                    }
                } header: {
                    Text("下载")
                } footer: {
                    Text("B 站高清视频的音轨与画面是分离的，保存时会自动合并为一个 MP4。")
                }

                Section {
                    Button {
                        appState.selectedTab = .cache
                    } label: {
                        HStack {
                            Text("缓存占用").foregroundStyle(Theme.ink)
                            Spacer()
                            Text(FileSize.string(cache.totalBytes))
                                .foregroundStyle(Theme.inkSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清理全部缓存")
                    }
                } header: {
                    Text("存储")
                }

                Section {
                    Button {
                        showShortcutsHelp = true
                    } label: {
                        HStack {
                            Text("添加到快捷指令").foregroundStyle(Theme.ink)
                            Spacer()
                            Text("一键收藏").foregroundStyle(Theme.inkSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                    NavigationLink("关于拾贝") { AboutView() }
                    LabeledContent("版本", value: "1.0.0 (1)")
                } header: {
                    Text("关于")
                }

                Section {
                    Text("拾贝只保存你有权访问的公开内容，用于个人离线阅读。请勿用于二次分发或商业用途。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                }

                Section {
                    Text("把喜欢的内容留在本地")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkTertiary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { cache.refreshTotals() }
            .sheet(isPresented: $showShortcutsHelp) {
                ShortcutsHelpView()
            }
            .confirmationDialog("清理全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清理全部", role: .destructive) {
                    let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.isCached })
                    let cached = (try? ShiBeiContainer.shared.context.fetch(descriptor)) ?? []
                    for item in cached { cache.deleteCache(item) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只删除本地文件，收藏记录保留。")
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.ink)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Text("拾")
                            .font(.system(size: 44, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                    )
                    .padding(.top, 30)

                Text("拾贝")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .tracking(3)

                Text("把小红书的图文、B 站的高清视频、微博的实况图，连同完整正文一起收进本地。链接失效也能继续看。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("支持平台", "小红书 / 抖音 / B 站 / 知乎 / 微博 / 小黑盒")
                    bullet("媒体类型", "图片、视频、实况图（Live Photo）")
                    bullet("离线能力", "全部媒体落地到本地，断网可浏览与播放")
                    bullet("隐私", "不登录、不上传，所有数据只存在本机")
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.surface)
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("在任意 App 里分享链接时，直接调用拾贝解析，省去复制粘贴。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(3)

                    step(1, "打开「快捷指令」App，新建快捷指令")
                    step(2, "添加操作 → 搜索「拾贝」→ 选择「收藏链接到拾贝」")
                    step(3, "在操作参数里选择「快捷指令输入」，并勾选「接收 URL、文本」")
                    step(4, "分享面板中把该快捷指令添加到收藏，之后从任何 App 分享即可一键收藏")
                    step(5, "也可以直接使用链接：shibei://parse?url=<链接地址>")

                    Text("提示：快捷指令在后台执行，不会打开 App，只负责「收藏」；需要离线缓存时再进 App 点一下缓存。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("快捷指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.ink))
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}
