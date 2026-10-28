import SwiftUI
import UIKit

// MARK: - 平台角标

struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 15

    var body: some View {
        Text(platform.shortMark)
            .font(.system(size: size * 0.56, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(platform.tint))
            .accessibilityLabel(platform.displayName)
    }
}

// MARK: - 筛选胶囊

struct FilterChip: View {
    let title: String
    var platform: Platform?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let platform {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.9) : platform.tint)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 33)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Theme.ink : Theme.fill.opacity(0.75))
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

// MARK: - 圆形图标按钮

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 34
    var emphasized = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(emphasized ? Theme.onAccent : Theme.ink)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(emphasized ? Theme.ink : Theme.fill.opacity(0.75))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 图片（本地优先）

struct MediaThumb: View {
    let local: URL?
    let remote: URL?
    var contentMode: ContentMode = .fill

    @State private var localImage: UIImage?

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let remote {
                AsyncImage(url: remote, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay(ProgressView().tint(Theme.inkTertiary))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: local) {
            guard localImage == nil, let local else { return }
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: local.path)
            }.value
            await MainActor.run { localImage = image }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Theme.fill)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.inkTertiary)
            )
    }
}

// MARK: - 头像

struct AuthorAvatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(rgb: 0xF6B26B), Color(rgb: 0xE8734A)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - 分区标题

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// MARK: - 主按钮

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(Theme.onAccent)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? Theme.ink : Theme.ink.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.fill))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 80)
    }
}

// MARK: - 格式化

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func ago(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: .now)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
