import Foundation

/// 首页分类维度
enum FilterDimension: String, CaseIterable, Identifiable {
    case all
    case platform
    case topic
    case tag
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .platform: return "平台"
        case .topic: return "话题"
        case .tag: return "标签"
        case .time: return "时间段"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "circle.grid.2x2"
        case .platform: return "square.stack.3d.up"
        case .topic: return "number"
        case .tag: return "tag"
        case .time: return "clock"
        }
    }
}

/// 时间段按哪个日期筛
enum TimeField: String, CaseIterable, Identifiable {
    case saved
    case edited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved: return "添加时间"
        case .edited: return "修改时间"
        }
    }
}

/// 列表排序
enum SortOrder: String, CaseIterable, Identifiable {
    case saved
    case edited
    case viewed
    case views

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved: return "最近收藏"
        case .edited: return "最近编辑"
        case .viewed: return "最近浏览"
        case .views: return "浏览次数"
        }
    }
}

/// 多选筛选状态；不同维度之间取交集
struct FilterState {
    var dimension: FilterDimension = .all
    var platforms: Set<Platform> = []
    var topics: Set<String> = []
    var tags: Set<String> = []
    var timeField: TimeField = .saved
    var from: Date?
    var to: Date?

    var activeCount: Int {
        platforms.count + topics.count + tags.count + ((from != nil || to != nil) ? 1 : 0)
    }

    var hasTimeFilter: Bool { from != nil || to != nil }

    mutating func clear() {
        platforms.removeAll()
        topics.removeAll()
        tags.removeAll()
        from = nil
        to = nil
    }

    mutating func clearDimension() {
        switch dimension {
        case .all:
            clear()
        case .platform:
            platforms.removeAll()
        case .topic:
            topics.removeAll()
        case .tag:
            tags.removeAll()
        case .time:
            from = nil
            to = nil
        }
    }

    func matches(_ item: Item) -> Bool {
        if !platforms.isEmpty, !platforms.contains(item.platform) { return false }
        if !topics.isEmpty, Set(item.topics).isDisjoint(with: topics) { return false }
        if !tags.isEmpty, Set(item.tags).isDisjoint(with: tags) { return false }

        if hasTimeFilter {
            let date: Date?
            switch timeField {
            case .saved: date = item.savedAt
            case .edited: date = item.lastEditedAt ?? item.savedAt
            }
            if let date {
                let day = Calendar.current.startOfDay(for: date)
                if let from, day < Calendar.current.startOfDay(for: from) { return false }
                if let to, day > Calendar.current.startOfDay(for: to) { return false }
            } else {
                return false
            }
        }
        return true
    }
}

enum ItemSorter {
    static func sorted(_ items: [Item], by order: SortOrder) -> [Item] {
        switch order {
        case .saved:
            return items.sorted { $0.savedAt > $1.savedAt }
        case .edited:
            return items.sorted { ($0.lastEditedAt ?? $0.savedAt) > ($1.lastEditedAt ?? $1.savedAt) }
        case .viewed:
            return items.sorted { ($0.lastViewedAt ?? $0.savedAt) > ($1.lastViewedAt ?? $1.savedAt) }
        case .views:
            return items.sorted { $0.viewCount > $1.viewCount }
        }
    }
}
