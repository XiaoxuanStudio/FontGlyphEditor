import SwiftUI

struct AdjustmentPanel: View {
    @ObservedObject var model: FontEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("调整")
                .font(.title3.bold())
            ScopePicker(scope: $model.adjustScope, selectedChars: $model.adjustSelectedChars)
            ParameterSlider(title: "大小", value: $model.scale, range: 0.5...2.0, step: 0.01, valueText: String(format: "%.2f", model.scale))
            ParameterSlider(title: "粗细", value: $model.weight, range: -8...8, step: 1, valueText: String(format: "%.0f", model.weight))
            ParameterSlider(title: "字间距", value: $model.tracking, range: -300...800, step: 1, valueText: "\(Int(model.tracking))")
            ParameterSlider(title: "上浮下沉", value: $model.baselineShift, range: -800...800, step: 1, valueText: "\(Int(model.baselineShift))")
            ParameterSlider(title: "行距", value: $model.lineHeight, range: 0.7...2.2, step: 0.01, valueText: String(format: "%.2f", model.lineHeight))
        }
        .panelStyle()
    }
}

struct ScopePicker: View {
    @Binding var scope: ScopeMode
    @Binding var selectedChars: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("范围", selection: $scope) {
                ForEach(ScopeMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if scope == .selected {
                TextField("输入要调整的字符，例如：测试ABC", text: $selectedChars)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

extension View {
    func panelStyle() -> some View {
        self
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
