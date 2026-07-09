import Foundation
import UniformTypeIdentifiers

final class FileStore {
    static let shared = FileStore()
    let root: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        root = documents.appendingPathComponent("FontGlyphEditor", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func copyIntoSandbox(_ url: URL, folder: String) throws -> URL {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sanitized = Self.safeFilename(url.lastPathComponent)
        let target = dir.appendingPathComponent(Self.uniqueName(prefix: sanitized))
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    func saveData(_ data: Data, filename: String, folder: String) throws -> URL {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(Self.uniqueName(prefix: Self.safeFilename(filename)))
        try data.write(to: target, options: [.atomic])
        return target
    }

    func saveDataExact(_ data: Data, filename: String, folder: String) throws -> URL {
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(Self.safeFilename(filename))
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try data.write(to: target, options: [.atomic])
        return target
    }

    static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let scalars = value.unicodeScalars.map { scalar -> Character in
            if forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) { return "_" }
            return Character(scalar)
        }
        let result = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "file" : result
    }

    static func uniqueName(prefix: String) -> String {
        let ext = (prefix as NSString).pathExtension
        let stem = (prefix as NSString).deletingPathExtension
        let suffix = String(UUID().uuidString.prefix(8))
        if ext.isEmpty { return "\(stem)_\(suffix)" }
        return "\(stem)_\(suffix).\(ext)"
    }

    static func inferredCharacter(from filename: String) -> String? {
        let stem = ((filename as NSString).lastPathComponent as NSString).deletingPathExtension
        if stem.count == 1 { return stem }
        if stem.lowercased().hasPrefix("u+") || stem.lowercased().hasPrefix("uni") {
            let cleaned = stem.replacingOccurrences(of: "U+", with: "")
                .replacingOccurrences(of: "u+", with: "")
                .replacingOccurrences(of: "uni", with: "")
            if let value = UInt32(cleaned, radix: 16), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
        }
        return nil
    }
}
