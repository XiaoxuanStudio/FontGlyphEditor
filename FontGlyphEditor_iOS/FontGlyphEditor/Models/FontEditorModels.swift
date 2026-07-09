import Foundation
import SwiftUI

struct EngineExportRequest: Codable {
    var outputFamilyName: String
    var previewText: String
    var adjustment: EngineGlobalAdjustment
    var color: EngineColorSettings
    var patches: [EngineGlyphPatch]

    enum CodingKeys: String, CodingKey {
        case outputFamilyName = "output_family_name"
        case previewText = "preview_text"
        case adjustment
        case color
        case patches
    }
}

struct EngineGlobalAdjustment: Codable {
    var scope: ScopeMode
    var selectedChars: String
    var scale: Double
    var weight: Double
    var tracking: Int
    var baselineShift: Int
    var lineHeight: Double

    enum CodingKeys: String, CodingKey {
        case scope
        case selectedChars = "selected_chars"
        case scale
        case weight
        case tracking
        case baselineShift = "baseline_shift"
        case lineHeight = "line_height"
    }
}

struct EngineColorSettings: Codable {
    var scope: ScopeMode
    var selectedChars: String
    var mode: ColorMode
    var solidHex: String
    var paletteHex: [String]
    var randomSeed: Int

    enum CodingKeys: String, CodingKey {
        case scope
        case selectedChars = "selected_chars"
        case mode
        case solidHex = "solid_hex"
        case paletteHex = "palette_hex"
        case randomSeed = "random_seed"
    }
}

struct EngineGlyphPatch: Codable, Identifiable {
    var id = UUID()
    var character: String
    var imageFilename: String
    var scale: Double
    var tracking: Int
    var offsetX: Int
    var offsetY: Int
    var weight: Double
    var pngPpem: Int

    enum CodingKeys: String, CodingKey {
        case character
        case imageFilename = "image_filename"
        case scale
        case tracking
        case offsetX = "offset_x"
        case offsetY = "offset_y"
        case weight
        case pngPpem = "png_ppem"
    }
}

enum ScopeMode: String, Codable, CaseIterable, Identifiable {
    case all
    case selected

    var id: String { rawValue }
    var title: String { self == .all ? "全部字符" : "指定字符" }
}

enum ColorMode: String, Codable, CaseIterable, Identifiable {
    case none
    case solid
    case random
    case paletteRandom = "palette_random"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "不改颜色"
        case .solid: return "统一颜色"
        case .random: return "完全随机"
        case .paletteRandom: return "指定色随机"
        }
    }
}

enum EditorTab: String, CaseIterable, Identifiable {
    case adjust = "调整"
    case color = "颜色"
    case patch = "修符"
    var id: String { rawValue }
}

struct LocalGlyphPatch: Identifiable, Hashable {
    let id: UUID
    var character: String
    var imageFilename: String
    var sourceURL: URL
    var previewURL: URL?
    var scale: Double
    var tracking: Int
    var offsetX: Int
    var offsetY: Int
    var weight: Double
    var pngPpem: Int

    init(character: String, imageFilename: String, sourceURL: URL, previewURL: URL? = nil) {
        self.id = UUID()
        self.character = character
        self.imageFilename = imageFilename
        self.sourceURL = sourceURL
        self.previewURL = previewURL
        self.scale = 1.0
        self.tracking = 0
        self.offsetX = 0
        self.offsetY = 0
        self.weight = 0
        self.pngPpem = 160
    }

    var enginePatch: EngineGlyphPatch {
        EngineGlyphPatch(
            character: character,
            imageFilename: imageFilename,
            scale: scale,
            tracking: tracking,
            offsetX: offsetX,
            offsetY: offsetY,
            weight: weight,
            pngPpem: pngPpem
        )
    }
}

struct InferredImageItem: Codable, Identifiable {
    var id: String { filename }
    let filename: String
    let character: String?
}

struct InferImagesResponse: Codable {
    let items: [InferredImageItem]
}
