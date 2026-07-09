import Foundation
import SwiftUI
import UIKit

@MainActor
final class FontEditorViewModel: ObservableObject {
    @Published var engineURLString: String = ""
    @Published var engineAuthToken: String?
    @Published var outputFamilyName: String = "修符字体"
    @Published var importedFontDisplayName: String?
    @Published var exportedDisplayName: String?
    @Published var previewText: String = "字体预览\n1234567890\nABCDEFGHIJK"

    @Published var fontURL: URL?
    @Published var fontPostScriptName: String?
    @Published var exportedFontURL: URL?
    @Published var exportedFontPostScriptName: String?

    @Published var selectedTab: EditorTab = .adjust

    @Published var adjustScope: ScopeMode = .all
    @Published var adjustSelectedChars: String = ""
    @Published var scale: Double = 1.0
    @Published var weight: Double = 0
    @Published var tracking: Double = 0
    @Published var baselineShift: Double = 0
    @Published var lineHeight: Double = 1.0

    @Published var colorScope: ScopeMode = .all
    @Published var colorSelectedChars: String = ""
    @Published var colorMode: ColorMode = .none
    @Published var solidHex: String = "#E8836B"
    @Published var paletteText: String = "#E8836B,#F2B705,#3DA5D9,#73B66B"
    @Published var randomSeed: Double = 42

    @Published var patches: [LocalGlyphPatch] = []
    @Published var isWorking: Bool = false
    @Published var statusText: String = "请选择字体文件"
    @Published var errorMessage: String?
    @Published var showingShare: Bool = false

    private var client: FontEngineClient {
        FontEngineClient(baseURL: URL(string: engineURLString) ?? URL(string: "https://font-line1.example.com")!, authToken: engineAuthToken)
    }

    var outputDisplayName: String {
        let trimmed = outputFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "修符字体" : trimmed
    }

    var importedFontBaseName: String? {
        guard let name = importedFontDisplayName else { return nil }
        return (name as NSString).deletingPathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
    }

    var validPatches: [LocalGlyphPatch] {
        patches.filter { !$0.character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.imageFilename.isEmpty }
    }

    var isUsingLocalhostOnPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let host = URL(string: engineURLString)?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "0.0.0.0"
        #endif
    }

    func updateEngine(urlString: String, token: String?) {
        engineURLString = urlString
        engineAuthToken = token
    }

    func importFont(url: URL) {
        do {
            let originalName = url.lastPathComponent
            let copied = try FileStore.shared.copyIntoSandbox(url, folder: "fonts")
            importedFontDisplayName = originalName
            let baseName = (originalName as NSString).deletingPathExtension
            if !baseName.isEmpty {
                previewText = "\(baseName)字体预览\n1234567890\nABCDEFGHIJK"
                if outputFamilyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outputFamilyName == "修符字体" {
                    outputFamilyName = baseName
                }
            }
            fontURL = copied
            fontPostScriptName = FontRegistrar.shared.registerFont(at: copied)
            exportedFontURL = nil
            exportedFontPostScriptName = nil
            exportedDisplayName = nil
            statusText = "已导入字体：\(originalName)。修改区会先显示本地实时预览，导出后会生成字体文件。"
        } catch {
            errorMessage = "导入字体失败：\(error.localizedDescription)"
        }
    }

    func importImageFiles(urls: [URL]) {
        Task {
            for url in urls {
                await importOnePatchSource(url: url)
            }
        }
    }

    func importPhotoImage(data: Data) {
        do {
            let name = "photo_\(Int(Date().timeIntervalSince1970)).png"
            let url = try FileStore.shared.saveData(data, filename: name, folder: "patches")
            let patch = LocalGlyphPatch(character: "", imageFilename: url.lastPathComponent, sourceURL: url, previewURL: url)
            patches.append(patch)
            selectedTab = .patch
            statusText = "已添加相册图片，请填写要替换的字符。填写后修改区会立即显示效果。"
        } catch {
            errorMessage = "导入相册图片失败：\(error.localizedDescription)"
        }
    }

    private func importOnePatchSource(url: URL) async {
        do {
            let copied = try FileStore.shared.copyIntoSandbox(url, folder: "patches")
            if copied.pathExtension.lowercased() == "zip" {
                await inferZipPatches(zipURL: copied)
            } else {
                let ch = FileStore.inferredCharacter(from: copied.lastPathComponent) ?? ""
                patches.append(LocalGlyphPatch(character: ch, imageFilename: copied.lastPathComponent, sourceURL: copied, previewURL: copied))
                if ch.isEmpty {
                    statusText = "已添加修符图片：\(copied.lastPathComponent)，请手动填写替换字符"
                } else {
                    statusText = "已添加修符图片：\(copied.lastPathComponent)，已自动识别字符：\(ch)"
                }
            }
            selectedTab = .patch
        } catch {
            errorMessage = "导入修符文件失败：\(error.localizedDescription)"
        }
    }

    private func inferZipPatches(zipURL: URL) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let items = try await client.inferImages(files: [zipURL])
            if items.isEmpty {
                patches.append(LocalGlyphPatch(character: "", imageFilename: zipURL.lastPathComponent, sourceURL: zipURL))
                statusText = "ZIP 已添加，但未识别到图片，请检查压缩包内容"
            } else {
                for item in items {
                    patches.append(LocalGlyphPatch(character: item.character ?? "", imageFilename: item.filename, sourceURL: zipURL))
                }
                statusText = "ZIP 已识别 \(items.count) 个修符项"
            }
        } catch {
            patches.append(LocalGlyphPatch(character: "", imageFilename: zipURL.lastPathComponent, sourceURL: zipURL))
            errorMessage = "ZIP 自动识别失败，可稍后手动填写：\(error.localizedDescription)"
        }
    }

    func deletePatch(_ patch: LocalGlyphPatch) {
        patches.removeAll { $0.id == patch.id }
    }

    func duplicatePatch(_ patch: LocalGlyphPatch) {
        var copy = LocalGlyphPatch(character: "", imageFilename: patch.imageFilename, sourceURL: patch.sourceURL, previewURL: patch.previewURL)
        copy.scale = patch.scale
        copy.tracking = patch.tracking
        copy.offsetX = patch.offsetX
        copy.offsetY = patch.offsetY
        copy.weight = patch.weight
        copy.pngPpem = patch.pngPpem
        patches.append(copy)
    }

    func testEngine() async {
        if isUsingLocalhostOnPhysicalDevice {
            errorMessage = ""
            statusText = ""
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let ok = try await client.health()
            statusText = ok ? "字体引擎连接成功，可以导出字体" : "字体引擎无响应"
        } catch {
            errorMessage = "字体引擎连接失败：\(error.localizedDescription)"
            statusText = "字体引擎连接失败"
        }
    }

    func exportFont() async {
        guard let fontURL else {
            errorMessage = "请先导入 .ttf / .otf / .ttc 字体文件"
            return
        }
        if isUsingLocalhostOnPhysicalDevice {
            errorMessage = ""
            statusText = "请先修改字体引擎地址"
            return
        }
        isWorking = true
        statusText = "正在生成字体文件..."
        defer { isWorking = false }
        do {
            let request = makeExportRequest(validPatches: validPatches)
            let attachments = validPatches.map { $0.sourceURL }
            let displayName = outputDisplayName
            let exported = try await client.exportFont(fontURL: fontURL, request: request, attachmentURLs: attachments, preferredName: displayName)
            exportedFontURL = exported
            exportedDisplayName = displayName
            exportedFontPostScriptName = FontRegistrar.shared.registerFont(at: exported)
            if exportedFontPostScriptName == nil {
                statusText = "字体文件已生成，但 iOS 未能注册预览。仍可分享保存：\(displayName).ttf"
            } else {
                statusText = "字体文件已生成：\(displayName).ttf"
            }
            showingShare = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)\n\n请先点“测试”确认字体引擎连接成功。"
            statusText = "导出失败"
        }
    }

    func makeExportRequest(validPatches: [LocalGlyphPatch]) -> EngineExportRequest {
        EngineExportRequest(
            outputFamilyName: outputDisplayName,
            previewText: previewText,
            adjustment: EngineGlobalAdjustment(
                scope: adjustScope,
                selectedChars: adjustSelectedChars,
                scale: scale,
                weight: weight,
                tracking: Int(tracking),
                baselineShift: Int(baselineShift),
                lineHeight: lineHeight
            ),
            color: EngineColorSettings(
                scope: colorScope,
                selectedChars: colorSelectedChars,
                mode: colorMode,
                solidHex: solidHex,
                paletteHex: paletteText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
                randomSeed: Int(randomSeed)
            ),
            patches: validPatches.map { $0.enginePatch }
        )
    }
}
