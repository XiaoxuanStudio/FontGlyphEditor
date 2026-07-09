import SwiftUI

struct ColorPanel: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("颜色")
                .font(.title3.bold())
            ScopePicker(scope: $model.colorScope, selectedChars: $model.colorSelectedChars)
            Picker("颜色模式", selection: $model.colorMode) {
                ForEach(ColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if model.colorMode == .solid {
                TextField("十六进制颜色，例如 #E8836B", text: $model.solidHex)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
            }

            if model.colorMode == .paletteRandom {
                TextField("多个颜色用英文逗号分隔", text: $model.paletteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            if model.colorMode == .random || model.colorMode == .paletteRandom {
                ParameterSlider(title: "随机种子", value: $model.randomSeed, range: 1...999, step: 1, valueText: "\(Int(model.randomSeed))")
            }

            Text("说明：颜色会通过 SVG 彩色字形表写入字体。不同 App 对彩色字体表的支持不同，iOS 自带文本渲染通常对 sbix 更友好。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}
