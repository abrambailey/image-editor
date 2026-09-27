import AppKit
import SwiftUI

struct LayerExpansionSheet: View {
    @ObservedObject var model: EditorModel
    let target: LayerExpansionTarget
    @State private var unit = LayerExpansionUnit.pixels
    @State private var individualSides = false
    @State private var all = "20"
    @State private var top = "20"
    @State private var right = "20"
    @State private var bottom = "20"
    @State private var left = "20"
    private enum Fill: String, CaseIterable { case white = "White", color = "Color", transparent = "Transparent" }
    @State private var fill = Fill.white
    @State private var customColor = Color.white
    @State private var applyError: String?
    @FocusState private var focusedField: String?

    private var expansion: LayerExpansion? {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if individualSides {
            guard let t = number(top), let r = number(right), let b = number(bottom), let l = number(left) else { return nil }
            return LayerExpansion(unit: unit, top: t, right: r, bottom: b, left: l)
        }
        guard let amount = number(all) else { return nil }
        return LayerExpansion(unit: unit, top: amount, right: amount, bottom: amount, left: amount)
    }

    private var validation: Result<LayerExpansion.Insets, Error> {
        Result {
            guard let expansion else { throw EditorError.message("Enter a number of 0 or more for each side.") }
            return try expansion.pixelInsets(for: target.size)
        }
    }

    private var canApply: Bool {
        guard case .success(let insets) = validation else { return false }
        return !insets.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Expand Layer").font(.headline)
                Text(target.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Picker("Units", selection: $unit) {
                ForEach(LayerExpansionUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Sides", selection: $individualSides) {
                Text("All sides").tag(false)
                Text("Individual sides").tag(true)
            }.pickerStyle(.segmented)
                .onChange(of: individualSides) { _, individual in
                    if individual { top = all; right = all; bottom = all; left = all }
                }
            if individualSides {
                HStack(spacing: 12) {
                    amountField("Top", text: $top)
                    amountField("Bottom", text: $bottom)
                }
                HStack(spacing: 12) {
                    amountField("Left", text: $left)
                    amountField("Right", text: $right)
                }
            } else {
                amountField("Each side", text: $all)
            }
            Text(unit == .percent
                 ? "Each left/right amount is a percentage of the current width; top/bottom use the current height. Rounded to whole pixels."
                 : "Add this many source pixels to each side. The existing image keeps its size and position.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker("Fill new area", selection: $fill) {
                ForEach(Fill.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if fill == .color {
                ColorPicker("Border color", selection: $customColor, supportsOpacity: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                switch validation {
                case .success(let insets):
                    let size = insets.expandedSize(target.size)
                    Text("\(target.image.width) × \(target.image.height) → \(Int(size.width)) × \(Int(size.height)) px")
                        .font(.system(size: 13, weight: .medium)).monospacedDigit()
                    Text("Canvas size stays the same. Fit & Center includes the new border.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .failure(let error):
                    Text(error.localizedDescription).font(.system(size: 11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let applyError {
                    Text(applyError).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: model.cancelLayerExpansion).keyboardShortcut(.cancelAction)
                Button("Expand Layer", action: apply).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(!canApply)
            }
        }
        .padding(24).frame(width: 400)
        .onAppear { focusedField = "Each side" }
    }

    private func amountField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField(label, text: text).textFieldStyle(.plain).monospacedDigit()
                    .focused($focusedField, equals: label)
                    .accessibilityLabel("\(label), \(unit.suffix)")
                Text(unit.suffix).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                focusedField == label ? Color.accentColor : Color.primary.opacity(0.18),
                lineWidth: focusedField == label ? 2 : 0.5))
        }
    }

    private func apply() {
        guard canApply, let expansion else { return }
        let color: CGColor?
        switch fill {
        case .white: color = CGColor(gray: 1, alpha: 1)
        case .transparent: color = nil
        case .color: color = NSColor(customColor).usingColorSpace(.sRGB)?.cgColor
        }
        do { try model.applyLayerExpansion(expansion, fill: color) }
        catch { applyError = error.localizedDescription }
    }
}
