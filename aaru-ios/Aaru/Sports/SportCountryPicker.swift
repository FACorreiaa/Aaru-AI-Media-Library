import SwiftUI

/// The "Where to watch" country (SPT-005): the device's region offered first, then every
/// country by name. Nothing is saved until one is picked. Opened from Settings → Friends &
/// privacy and from an event's "Where to watch".
struct SportCountryPicker: View {
    let model: SportSettingsModel
    /// After a country is saved.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving: String?

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countries: [String] {
        guard !trimmed.isEmpty else { return WatchCountry.all }
        return WatchCountry.all.filter { code in
            WatchCountry.name(code).localizedStandardContains(trimmed)
                || code.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty, let suggested = WatchCountry.suggested {
                    Section("Suggested") {
                        row(suggested)
                    }
                }
                Section {
                    ForEach(countries, id: \.self) { code in
                        row(code)
                    }
                }
            }
            .paperPage()
            .overlay {
                if countries.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            #if os(iOS)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .searchable(text: $text, prompt: "Country")
            #endif
            .navigationTitle("Where to watch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ProblemBanner(message: model.problem) { model.problem = nil }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    private func row(_ code: String) -> some View {
        let isCurrent = code == model.countryCode
        return Button {
            Task { await choose(code) }
        } label: {
            HStack(spacing: 12) {
                Text(WatchCountry.name(code))
                    .foregroundStyle(Color(.ink))
                Spacer(minLength: 0)
                if saving == code {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color(.accent))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saving != nil)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func choose(_ code: String) async {
        saving = code
        defer { saving = nil }
        if await model.save(code) {
            onSaved()
            dismiss()
        }
    }
}
