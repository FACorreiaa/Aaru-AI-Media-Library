import SwiftUI

/// Friends & privacy → Location (MUS-003, UX-022): the one city Aaru keeps to look for concerts
/// around, chosen from a search and removed here. Shown only when this server has concerts on.
struct ConcertPlaceSection: View {
    let model: ConcertsModel
    /// Shows a failure in the page's problem banner.
    var onProblem: (String) -> Void

    @State private var choosing = false

    var body: some View {
        Group {
            if model.available {
                Section {
                    LabeledContent("Concerts near") {
                        Button(model.savedPlace?.label ?? "Choose a city") { choosing = true }
                    }
                    if model.savedPlace != nil {
                        Button("Remove", role: .destructive) {
                            Task { await model.removePlace() }
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text(
                        "The only place Aaru stores where you are, to find concerts. “Use my location” in "
                            + "Discover is used once and never saved."
                    )
                }
            }
        }
        .task { await model.loadSetting() }
        .sheet(isPresented: $choosing) {
            ConcertPlacePicker(model: model)
        }
        .onChange(of: model.problem) { _, problem in
            // The picker shows its own; anything after it closes goes to the page's banner.
            guard let problem, !choosing else { return }
            onProblem(problem)
            model.problem = nil
        }
    }
}
