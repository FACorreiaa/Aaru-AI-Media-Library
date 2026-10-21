import AaruAPI
import SwiftUI

/// APP-006: every list, with create, rename and delete. A list is membership, not a filter.
struct ListsView: View {
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?

    @State private var naming: Naming?

    private enum Naming: Identifiable {
        case new
        case rename(ListSummary)

        var id: String {
            switch self {
            case .new: "new"
            case let .rename(list): list.id
            }
        }
    }

    var body: some View {
        List {
            ForEach(lists.lists, id: \.id) { list in
                NavigationLink {
                    ListDetailView(listID: list.id, lists: lists, library: library, api: api)
                } label: {
                    LabeledContent(list.name) {
                        Text(list.itemCount == 1 ? "1 title" : "\(list.itemCount) titles")
                    }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { naming = .rename(list) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await lists.delete(list.id) }
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { lists.lists[$0].id }
                Task { for id in ids {
                    await lists.delete(id)
                } }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .overlay {
            if lists.hasLoaded, lists.lists.isEmpty {
                ContentUnavailableView {
                    Label("No lists yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Make one for a theme, a marathon or a book club.")
                } actions: {
                    Button("New list") { naming = .new }.buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: lists.problem) { lists.problem = nil } }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New list", systemImage: "plus") { naming = .new }
            }
        }
        .sheet(item: $naming) { naming in
            NameListSheet(
                title: {
                    if case .new = naming {
                        "New list"
                    } else {
                        "Rename list"
                    }
                }(),
                initial: {
                    if case let .rename(list) = naming {
                        list.name
                    } else {
                        ""
                    }
                }()
            ) { name in
                switch naming {
                case .new: await lists.create(named: name)
                case let .rename(list): await lists.rename(list.id, to: name)
                }
            }
        }
        .task { await lists.load() }
        .refreshable { await lists.load() }
    }
}

/// One list: its titles in order, swipe to remove, drag to reorder, "Add titles" to search into
/// it. Rows carry status, progress and the next airing (LST-003).
struct ListDetailView: View {
    let listID: String
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?

    @State private var detail: ListDetail?
    @State private var showsSearch = false

    var body: some View {
        List {
            ForEach(detail?.items ?? [], id: \.title.id) { item in
                row(for: item)
                    .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                guard let detail else { return }
                let ids = offsets.map { detail.items[$0].title.id }
                Task {
                    for id in ids {
                        if let updated = await lists.remove(titleID: id, from: listID) {
                            self.detail = updated
                        }
                    }
                }
            }
            .onMove { source, destination in
                guard var items = detail?.items else { return }
                let before = detail
                items.move(fromOffsets: source, toOffset: destination)
                detail?.items = items
                Task {
                    if let saved = await lists.reorder(listID, titleIDs: items.map(\.title.id)) {
                        detail = saved
                    } else {
                        detail = before
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .overlay {
            if let detail, detail.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on this list", systemImage: "text.badge.plus")
                } actions: {
                    Button("Add titles") { showsSearch = true }.buttonStyle(.borderedProminent)
                }
            } else if detail == nil {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: lists.problem) { lists.problem = nil } }
        .navigationTitle(detail?.name ?? "List")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add titles", systemImage: "plus") { showsSearch = true }
                    .disabled(detail == nil)
            }
            #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
            #endif
        }
        .sheet(isPresented: $showsSearch) {
            if let list = Binding($detail) {
                SearchView(api: api, library: library, lists: lists, intoList: list)
            }
        }
        .task { detail = await lists.detail(listID) }
    }

    @ViewBuilder private func row(for item: ListItem) -> some View {
        // A title on the shelf opens its Title room; one that is only on the list does not. The
        // local library wins over the row's entry: it is the copy Title detail edits.
        if let entry = library.entry(forTitle: item.title.id) ?? item.entry {
            NavigationLink {
                TitleDetailView(entry: entry, api: api, library: library, lists: lists)
            } label: { ListItemRow(item: item) }
        } else {
            ListItemRow(item: item)
        }
    }
}

/// Picks lists for one title: tap to add; a new list can be made on the spot.
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
                                    .accessibilityLabel("Added")
                            }
                        }
                    }
                    .disabled(added.contains(list.id))
                }
            }
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: lists.problem) { lists.problem = nil } }
            .navigationTitle("Add “\(titleName)”")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $makesNew) {
                    NameListSheet(title: "New list", initial: "") { name in
                        if let list = await lists.create(named: name) {
                            await add(to: list.id)
                        }
                    }
                }
                .task {
                    if !lists.hasLoaded {
                        await lists.load()
                    }
                }
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

/// A one-field sheet for naming a list.
private struct NameListSheet: View {
    let title: String
    let initial: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .onSubmit(save)
            }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .onAppear {
                    name = initial
                    focused = true
                }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let value = name
        Task {
            await onSave(value)
            dismiss()
        }
    }
}

/// The bottom message for a write that failed. Tap to dismiss.
struct ProblemBanner: View {
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.arrow.circlepath")
                .font(.callout)
                .foregroundStyle(Color(.paper))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.danger), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onTapGesture(perform: onDismiss)
        }
    }
}
