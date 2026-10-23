import AaruAPI
import SwiftUI

/// A list pushed from Lists in a navigation stack.
struct ListRoute: Hashable {
    let id: String
}

/// APP-006: every list, with create, rename and delete. A list is membership, not a filter. In a
/// stack (iPhone, Library) a row pushes the list; in `ListsScreen`'s split view it selects it.
struct ListsView: View {
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?
    /// The split view's selection. Nil: rows push in the surrounding stack.
    var selection: Binding<String?>?

    @Environment(AppRouter.self) private var router
    @State private var naming: ListNaming?
    @State private var deleting: ListSummary?

    init(lists: ListsModel, library: LibraryModel, api: Client?, selection: Binding<String?>? = nil) {
        self.lists = lists
        self.library = library
        self.api = api
        self.selection = selection
    }

    var body: some View {
        rows
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .overlay { state }
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: lists.problem) { lists.problem = nil } }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // ⌘N (File → New List) does the same from anywhere.
                    Button("New list", systemImage: "plus") { naming = .new }
                }
            }
            .sheet(item: $naming) { naming in
                NameListSheet(title: naming.title, initial: naming.initial, lists: lists) { name in
                    switch naming {
                    case .new: await lists.create(named: name) != nil
                    case let .rename(list): await lists.rename(list.id, to: name) != nil
                    }
                }
            }
            .confirmationDialog(
                "Delete “\(deleting?.name ?? "")”?",
                isPresented: $deleting.isPresent,
                titleVisibility: .visible,
                presenting: deleting
            ) { list in
                Button("Delete list", role: .destructive) { Task { await lists.delete(list.id) } }
            } message: { _ in
                Text("The list goes; the titles stay in your library.")
            }
            .modifier(ListRouteDestination(isEnabled: selection == nil, lists: lists, library: library, api: api))
            .onChange(of: router.pendingNewList, initial: true) { _, pending in
                guard pending else { return }
                router.pendingNewList = false
                naming = .new
            }
            .task { await lists.load() }
            .refreshable { await lists.load() }
            .refreshesOnCommand(.lists) { await lists.load() }
    }

    @ViewBuilder private var rows: some View {
        if let selection {
            List(selection: selection) {
                ForEach(lists.lists, id: \.id) { list in
                    NavigationLink(value: list.id) { ListRowLabel(list: list) }
                        .contextMenu { menu(list) }
                }
                .onDelete(perform: confirmDelete)
            }
            .listStyle(.sidebar)
        } else {
            List {
                ForEach(lists.lists, id: \.id) { list in
                    NavigationLink(value: ListRoute(id: list.id)) { ListRowLabel(list: list) }
                        .contextMenu { menu(list) }
                }
                .onDelete(perform: confirmDelete)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
        }
    }

    /// The first load failing, loading, or no lists yet.
    @ViewBuilder private var state: some View {
        if lists.lists.isEmpty {
            if let failure = lists.loadProblem {
                LoadFailedView(title: "Your lists didn't load", message: failure) { await lists.load() }
            } else if !lists.hasLoaded {
                ProgressView()
            } else {
                OwlUnavailableView(title: "No lists yet", message: "Make one for a theme, a marathon or a book club.") {
                    Button("New list") { naming = .new }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder private func menu(_ list: ListSummary) -> some View {
        Button("Rename", systemImage: "pencil") { naming = .rename(list) }
        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = list }
    }

    /// A swipe asks first, as the context menu does (UX-079).
    private func confirmDelete(_ offsets: IndexSet) {
        deleting = offsets.first.map { lists.lists[$0] }
    }
}

/// One list in the index: its name and how many titles it holds.
private struct ListRowLabel: View {
    let list: ListSummary

    var body: some View {
        LabeledContent(list.name) {
            Text(list.itemCount == 1 ? "1 title" : "\(list.itemCount) titles")
        }
    }
}

private enum ListNaming: Identifiable {
    case new
    case rename(ListSummary)

    var id: String {
        switch self {
        case .new: "new"
        case let .rename(list): list.id
        }
    }

    var title: String {
        if case .new = self {
            "New list"
        } else {
            "Rename list"
        }
    }

    var initial: String {
        if case let .rename(list) = self {
            list.name
        } else {
            ""
        }
    }
}

/// In a stack, a list row pushes its detail. A split view's sidebar has no stack to push on.
private struct ListRouteDestination: ViewModifier {
    let isEnabled: Bool
    let lists: ListsModel
    let library: LibraryModel
    let api: Client?

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: ListRoute.self) { route in
                ListDetailView(listID: route.id, lists: lists, library: library, api: api)
            }
        } else {
            content
        }
    }
}

/// A one-field sheet for naming a list. It closes only once the save worked (UX-079); a failure
/// stays in the sheet with the name kept.
struct NameListSheet: View {
    let title: String
    let initial: String
    let lists: ListsModel
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($focused)
                    .onSubmit(save)
                if let problem = lists.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Color(.danger))
                }
            }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .onAppear {
                    lists.problem = nil
                    name = initial
                    focused = true
                }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let value = name
        guard !saving, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            saving = true
            let saved = await onSave(value)
            saving = false
            if saved {
                dismiss()
            }
        }
    }
}
