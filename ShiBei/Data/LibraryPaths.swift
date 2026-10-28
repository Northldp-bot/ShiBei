import Foundation

enum LibraryPaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ShiBei", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var libraryRoot: URL {
        let dir = appSupport.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func folder(for id: UUID) -> URL {
        let dir = libraryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func imagesFolder(for id: UUID) -> URL {
        let dir = folder(for: id).appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func videosFolder(for id: UUID) -> URL {
        let dir = folder(for: id).appendingPathComponent("videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum FileSize {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        return formatter.string(fromByteCount: bytes)
    }
}

extension URL {
    /// 去掉查询参数的稳定文件名
    var stableFileName: String {
        let ext = pathExtension.isEmpty ? "bin" : pathExtension
        let hash = absoluteString.unicodeScalars.reduce(into: UInt64(5381)) { partial, scalar in
            partial = (partial &* 33) &+ UInt64(scalar.value)
        }
        return "\(String(hash, radix: 16)).\(ext)"
    }
}
