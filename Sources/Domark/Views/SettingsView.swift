import SwiftUI

/// ⌘, — picks the two typefaces, and the reading size that goes with them.
///
/// Families are listed in two groups per picker: the ones that suit that pane (Thai coverage for
/// reading, monospaced for the editor) and then everything else installed, because someone who
/// knows what they want should not have to fight the list for it.
struct SettingsView: View {
    @AppStorage(FontSetting.proseKey) private var prose: String = FontSetting.defaultProse
    @AppStorage(FontSetting.codeKey) private var code: String = FontSetting.defaultCode
    @AppStorage(FontSize.key) private var baseFontSize: Double = Theme.defaultBase
    @AppStorage(AppearanceSetting.key) private var appearanceRaw: String = AppearanceSetting.system.rawValue

    var body: some View {
        Form {
            Section("Reading") {
                familyPicker(
                    selection: $prose,
                    preferred: FontCatalog.thaiFamilies,
                    preferredLabel: "Draws Thai"
                )
                Stepper(value: $baseFontSize, in: Double(Theme.minBase)...Double(Theme.maxBase), step: 1) {
                    Text("Size: \(Int(baseFontSize)) pt")
                }
                sample(family: prose, size: baseFontSize, mono: false)
            }

            Section("Editor & Code") {
                familyPicker(
                    selection: $code,
                    preferred: FontCatalog.monospacedFamilies,
                    preferredLabel: "Monospaced"
                )
                sample(family: code, size: baseFontSize * 0.95, mono: true)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceSetting.allCases, id: \.self) { setting in
                        Text(setting.label).tag(setting.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                HStack {
                    Spacer()
                    Button("Use Defaults") {
                        prose = FontSetting.defaultProse
                        code = FontSetting.defaultCode
                        baseFontSize = Theme.defaultBase
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func familyPicker(selection: Binding<String>, preferred: [String], preferredLabel: String) -> some View {
        let listed = Set(preferred)
        Picker("Typeface", selection: selection) {
            Text(FontCatalog.systemLabel).tag(Fonts.systemFamily)
            Section(preferredLabel) {
                ForEach(preferred, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Section("All Fonts") {
                ForEach(FontCatalog.families.filter { !listed.contains($0) }, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
        }
    }

    /// Shows the face as it will actually be drawn — including the optical scaling, which is the
    /// part people would otherwise have to discover by squinting at the page
    private func sample(family: String, size: Double, mono: Bool) -> some View {
        let scale = Fonts.opticalScale(for: family)
        let font = mono
            ? Fonts.mono(family: family, size: size)
            : Fonts.body(family: family, size: size)

        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "ทดสอบการอ่านภาษาไทย ก ข ค")
            Text(verbatim: "The quick brown fox 0123")
                .padding(.bottom, 2)
            if abs(scale - 1) > 0.01 {
                Text("Drawn at \(Int((size * scale).rounded())) pt so it reads like \(Int(size.rounded())) pt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
