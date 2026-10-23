import AaruAPI
import SwiftUI

/// Picks lists for one title: tap to add; a new list can be made on the spot. Lists that already
/// hold the title are marked when the sheet opens (UX-079).
struct ListPickerSheet: View {
    let ref: MediaRef
    let titleName: String
    let lists: ListsModel

    @Environment(\.dismiss) private var dismiss
    @State private var added: Set<String> = []
    @State private var working: Set<String> = []
    @State private var makesNew = false

    var body: some View {
        NavigationStack {
            List {
                Button("New list…", systemImage: "plus") { makesNew = true }
                    .frame(minHeight: 44)
                ForEach(lists.lists, id: \.id) { list in
                    Button {
                        Task { await add(to: list.id) }
                    } label: {
                        HStack {
                            Text(list.name).foregroundStyle(Color(.ink))
                            Spacer()
                            if working.contains(list.id) {
                                ProgressView().controlSize(.small)
                            } else if added.contains(list.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .disabled(added.contains(list.id))
                    .accessibilityValue(added.contains(list.id) ? "On this list" : "")
                }
            }
            .paperPage()
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: lists.problem) { lists.problem = nil } }
            .navigationTitle("Add “\(titleName)” to a list")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $makesNew) {
                    NameListSheet(title: "New list", initial: "", lists: lists) { name in
                        guard let list = await lists.create(named: name) else { return false }
                        await add(to: list.id)
                        return true
                    }
                }
                .task { await markMembership() }
        }
    }

    private func markMembership() async {
        if !lists.hasLoaded {
            await lists.load()
        }
        guard let titleID = ref.titleId else { return }
        if let holding = await lists.listIDs(containing: titleID) {
            added.formUnion(holding)
        }
    }

    private func add(to id: String) async {
        guard !working.contains(id) else { return }
        working.insert(id)
        defer { working.remove(id) }
        if await lists.add(ref, to: id) != nil {
            added.insert(id)
        }
    }
}
