import SwiftUI

/// 高级设置：为需要登录态的平台补充 Cookie。
/// 不做账号登录，只接受用户从浏览器复制的 Cookie 字符串。
struct AdvancedSettingsView: View {
    @AppStorage("cookie.bilibili") private var bilibiliCookie = ""
    @AppStorage("cookie.weibo") private var weiboCookie = ""

    var body: some View {
        Form {
            Section {
                TextField("SESSDATA=...", text: $bilibiliCookie, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
            } header: {
                Text("B 站 Cookie")
            } footer: {
                Text("在浏览器登录 bilibili.com，开发者工具 → Network → 任意请求 → 复制请求头里的 Cookie。填入后可解锁 1080P；留空则使用游客清晰度（通常 480P）。")
            }

            Section {
                TextField("SUB=...; _T_WM=...", text: $weiboCookie, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
            } header: {
                Text("微博 Cookie")
            } footer: {
                Text("部分网络下微博会返回 432 风控，填入 m.weibo.cn 的 Cookie 可提高成功率。")
            }

            Section {
                Text("Cookie 只保存在本机，不会上传。换账号或过期后重新粘贴即可。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("登录态")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum PlatformCookie {
    static func header(for platform: Platform) -> String? {
        let key: String?
        switch platform {
        case .bilibili: key = "cookie.bilibili"
        case .weibo: key = "cookie.weibo"
        default: key = nil
        }
        guard let key, let value = UserDefaults.standard.string(forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
