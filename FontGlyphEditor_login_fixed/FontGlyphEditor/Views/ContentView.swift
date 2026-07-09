import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = FontEditorViewModel()
    @State private var showFontImporter = false
    @State private var showPatchImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeaderSection(model: model, showFontImporter: $showFontImporter)
                    PreviewSection(model: model)
                    ServerSection(model: model)
                    TabSelector(model: model)
                    activePanel
                    ExportSection(model: model)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("XFonts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("导入") {
                        Button("重新导入字体") { showFontImporter = true }
                        Button("从文件选 PNG / ZIP") { showPatchImporter = true }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text("从相册选图片")
                        }
                    }
                }
            }
        }
        .onAppear {
            model.updateEngine(urlString: session.engineURLString, token: session.token)
        }
        .onChange(of: session.selectedLineID) { _ in
            model.updateEngine(urlString: session.engineURLString, token: session.token)
        }
        .sheet(isPresented: $showFontImporter) {
            DocumentPicker(
                allowedContentTypes: [.truetypeFont, .opentypeFont, .fontCollection, .data],
                allowsMultipleSelection: false
            ) { urls in
                if let url = urls.first {
                    model.importFont(url: url)
                }
            }
        }
        .sheet(isPresented: $showPatchImporter) {
            DocumentPicker(
                allowedContentTypes: [.png, .jpeg, .zipArchive, .image, .data],
                allowsMultipleSelection: true
            ) { urls in
                model.importImageFiles(urls: urls)
            }
        }
        .onChange(of: photoItem) { newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run { model.importPhotoImage(data: data) }
                }
            }
        }
        .sheet(isPresented: $model.showingShare) {
            if let url = model.exportedFontURL { ShareSheet(items: [url]) }
        }
        .alert("提示", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var activePanel: some View {
        switch model.selectedTab {
        case .adjust:
            AdjustmentPanel(model: model)
        case .color:
            ColorPanel(model: model)
        case .patch:
            PatchPanel(model: model, showPatchImporter: $showPatchImporter, photoItem: $photoItem)
        }
    }
}

struct HeaderSection: View {
    @ObservedObject var model: FontEditorViewModel
    @Binding var showFontImporter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前字体")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.importedFontDisplayName ?? "未导入")
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Button("重新导入字体") { showFontImporter = true }
                    .buttonStyle(.borderedProminent)
            }
            TextField("导出字体名称", text: $model.outputFamilyName)
                .textFieldStyle(.roundedBorder)
            TextField("自定义预览文本", text: $model.previewText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PreviewSection: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            PreviewCard(title: "原始", text: model.previewText, postScriptName: model.fontPostScriptName, displayName: model.importedFontBaseName)
            ModifiedPreviewCard(model: model)
        }
    }
}

struct PreviewCard: View {
    let title: String
    let text: String
    let postScriptName: String?
    let displayName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(displayName ?? "未导入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(text)
                .font(postScriptName.map { Font.custom($0, size: 28) } ?? .system(size: 28, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ModifiedPreviewCard: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("修改后")
                    .font(.headline)
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LiveGlyphPreview(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("这里是本地实时预览，不需要先生成字体文件；底部“生成并导出字体文件”才会调用后端写出 TTF。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var status: String {
        if let name = model.exportedDisplayName { return "已生成：\(name)" }
        if model.exportedFontURL != nil { return "已生成：\(model.outputDisplayName)" }
        if model.fontURL == nil { return "未导入字体" }
        return "实时预览"
    }
}

struct LiveGlyphPreview: View {
    @ObservedObject var model: FontEditorViewModel

    private var patchMap: [String: LocalGlyphPatch] {
        var result: [String: LocalGlyphPatch] = [:]
        for patch in model.validPatches {
            if let first = patch.character.first {
                result[String(first)] = patch
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(4, CGFloat(8 * model.lineHeight))) {
            ForEach(Array(model.previewText.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: max(0, CGFloat(model.tracking / 80.0))) {
                    ForEach(Array(line.map { String($0) }.enumerated()), id: \.offset) { _, ch in
                        glyphView(ch)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func glyphView(_ ch: String) -> some View {
        if let patch = patchMap[ch], let url = patch.previewURL, let image = UIImage(contentsOfFile: url.path) {
            let size = max(8, 28 * model.scale * patch.scale)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(x: CGFloat(patch.offsetX) / 80.0, y: -CGFloat(patch.offsetY) / 80.0 - CGFloat(model.baselineShift) / 80.0)
                .padding(.horizontal, max(0, CGFloat(patch.tracking) / 160.0))
        } else {
            Text(ch)
                .font(fontForText)
                .foregroundStyle(colorForCharacter(ch))
                .baselineOffset(CGFloat(model.baselineShift) / 20.0)
                .tracking(CGFloat(model.tracking) / 80.0)
        }
    }

    private var fontForText: Font {
        let size = max(8, 28 * model.scale)
        if let ps = model.fontPostScriptName {
            return .custom(ps, size: size)
        }
        return .system(size: size, weight: .regular)
    }

    private func colorForCharacter(_ ch: String) -> Color {
        guard appliesColor(to: ch) else { return .primary }
        switch model.colorMode {
        case .none:
            return .primary
        case .solid:
            return Color(hex: model.solidHex) ?? .primary
        case .random:
            let seed = abs((ch + String(Int(model.randomSeed))).hashValue)
            let hue = Double(seed % 360) / 360.0
            return Color(hue: hue, saturation: 0.75, brightness: 0.85)
        case .paletteRandom:
            let colors = model.paletteText
                .split(separator: ",")
                .compactMap { Color(hex: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard !colors.isEmpty else { return .primary }
            let seed = abs((ch + String(Int(model.randomSeed))).hashValue)
            return colors[seed % colors.count]
        }
    }

    private func appliesColor(to ch: String) -> Bool {
        if model.colorMode == .none { return false }
        if model.colorScope == .all { return true }
        return model.colorSelectedChars.contains(ch)
    }
}

struct ServerSection: View {
    @ObservedObject var model: FontEditorViewModel
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("字体引擎线路")
                .font(.headline)
            if session.lines.isEmpty {
                Text("暂无可用线路，请确认总后端 config/lines.json 已配置并启用线路。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("选择线路", selection: Binding(
                    get: { session.selectedLineID ?? session.lines.first?.id ?? "" },
                    set: { newID in
                        session.updateSelectedLine(newID)
                        model.updateEngine(urlString: session.engineURLString, token: session.token)
                    }
                )) {
                    ForEach(session.lines) { line in
                        Text(line.name).tag(line.id)
                    }
                }
                .pickerStyle(.segmented)
                if let line = session.selectedLine {
                    Text("当前：\(line.name) · \(line.url)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("刷新线路") {
                    Task {
                        try? await session.refreshLines()
                        model.updateEngine(urlString: session.engineURLString, token: session.token)
                    }
                }
                .buttonStyle(.bordered)
                Button("测试") {
                    model.updateEngine(urlString: session.engineURLString, token: session.token)
                    Task { await model.testEngine() }
                }
                .buttonStyle(.bordered)
            }
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TabSelector: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        Picker("功能", selection: $model.selectedTab) {
            ForEach(EditorTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct ExportSection: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task { await model.exportFont() }
            } label: {
                HStack {
                    if model.isWorking { ProgressView().tint(.white) }
                    Text(model.isWorking ? "正在生成..." : "生成并导出字体文件")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isWorking || model.fontURL == nil)

            if model.fontURL == nil {
                Text("请先导入字体文件，才能生成导出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.validPatches.isEmpty && model.colorMode == .none && model.scale == 1.0 && model.tracking == 0 && model.baselineShift == 0 && model.lineHeight == 1.0 {
                Text("当前没有修符或参数变化，仍可导出一个重命名字体。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let url = model.exportedFontURL {
                Button("保存 / 分享最近生成的字体：\(model.exportedDisplayName ?? model.outputDisplayName).ttf") {
                    model.showingShare = true
                }
                .font(.caption)
            }
        }
        .padding(.bottom, 20)
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt64(text, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

extension UTType {
    static let truetypeFont = UTType(filenameExtension: "ttf")!
    static let opentypeFont = UTType(filenameExtension: "otf")!
    static let fontCollection = UTType(filenameExtension: "ttc")!
    static let fontFile = UTType(filenameExtension: "font") ?? .data
    static let zipArchive = UTType(filenameExtension: "zip")!
}

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
