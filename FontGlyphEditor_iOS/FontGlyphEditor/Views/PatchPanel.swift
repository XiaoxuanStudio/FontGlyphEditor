import SwiftUI
import PhotosUI
import UIKit

struct PatchPanel: View {
    @ObservedObject var model: FontEditorViewModel
    @Binding var showPatchImporter: Bool
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("修符")
                    .font(.title3.bold())
                Spacer()
                Menu("添加") {
                    Button("从文件选择 PNG / JPEG / ZIP") { showPatchImporter = true }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("从相册选择图片")
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("上传图片后输入要修符的字")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if model.patches.isEmpty {
                EmptyPatchView()
            } else {
                VStack(spacing: 12) {
                    ForEach($model.patches) { $patch in
                        PatchRow(
                            patch: $patch,
                            deleteAction: { model.deletePatch(patch) },
                            duplicateAction: { model.duplicatePatch(patch) }
                        )
                    }
                }
            }
        }
        .panelStyle()
    }
}

struct EmptyPatchView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("还没有修符图片")
                .font(.headline)
            Text("导入 PNG/JPEG 或 ZIP 后，可以指定它替换哪个字符。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PatchRow: View {
    @Binding var patch: LocalGlyphPatch
    let deleteAction: () -> Void
    let duplicateAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LocalImage(url: patch.previewURL)
                    .frame(width: 58, height: 58)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(patch.imageFilename)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack {
                        Text("替换字符")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("如 字", text: $patch.character)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
                Spacer()
                Menu {
                    Button("复制一项", action: duplicateAction)
                    Button("删除", role: .destructive, action: deleteAction)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            VStack(spacing: 8) {
                CompactSlider(title: "大小", value: $patch.scale, range: 0.3...3.0, step: 0.01, display: String(format: "%.2f", patch.scale))
                CompactIntSlider(title: "字距", value: $patch.tracking, range: -300...800)
                CompactIntSlider(title: "左右", value: $patch.offsetX, range: -800...800)
                CompactIntSlider(title: "上下", value: $patch.offsetY, range: -800...800)
                CompactSlider(title: "粗细", value: $patch.weight, range: -8...8, step: 1, display: String(format: "%.0f", patch.weight))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CompactSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 44, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(display)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption)
    }
}

struct CompactIntSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    private var doubleBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(value) },
            set: { value = Int($0) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 44, alignment: .leading)
            Slider(value: doubleBinding, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption)
    }
}

struct LocalImage: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "archivebox")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
