import AaruAPI
import SwiftUI

/// "Concerts near" (MUS-003): the one city Aaru keeps to look for concerts around, chosen from a
/// search and removed here. Shown only when this server has concerts on.
struct ConcertPlaceSection: View {
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void

    @State private var model: ConcertsModel
    @State private var choosing = false

    init(api: Client?, onProblem: @escaping (String) -> Void) {
        self.onProblem = onProblem
        _model = State(initialValue: ConcertsModel(api: api))
    }

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
                    Text("Concerts")
                } footer: {
                    Text("Aaru keeps only this city. “Use my location” in Discover is used once and never saved.")
                }
            }
        }
        .task { await model.loadSetting() }
        .sheet(isPresented: $choosing) {
            ConcertPlacePicker(model: model)
        }
        .onChange(of: model.problem) { _, problem in
            // The picker shows its own; anything after it closes goes to Settings' banner.
            guard let problem, !choosing else { return }
            onProblem(problem)
            model.problem = nil
        }
    }
}
