import SwiftUI

/// Friends & privacy → Sports (SPT-005): the country "Where to watch" lists first when a match
/// opens, chosen from a list and cleared here. Shown only when this server has Sports on.
struct SportSettingsSection: View {
    let model: SportSettingsModel
    /// Shows a failure in the page's problem banner.
    var onProblem: (String) -> Void

    @State private var choosing = false

    var body: some View {
        Group {
            if model.available {
                Section {
                    LabeledContent("Where to watch") {
                        Button(model.countryCode.map(WatchCountry.name) ?? "Choose a country") { choosing = true }
                            .disabled(model.isSaving)
                    }
                    if model.countryCode != nil {
                        Button("Clear", role: .destructive) {
                            Task { _ = await model.save(nil) }
                        }
                        .disabled(model.isSaving)
                    }
                } header: {
                    Text("Sports")
                } footer: {
                    Text("A match's channels in this country show first. Aaru keeps only the country.")
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $choosing) {
            SportCountryPicker(model: model)
        }
        .onChange(of: model.problem) { _, problem in
            // The picker shows its own; anything after it closes goes to the page's banner.
            guard let problem, !choosing else { return }
            onProblem(problem)
            model.problem = nil
        }
    }
}
