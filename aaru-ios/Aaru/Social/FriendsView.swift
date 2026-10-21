import AaruAPI
import SwiftUI

/// The Settings row for friends: your handle, and the way into the friends screen.
struct FriendsSection: View {
    @State private var model: SocialModel

    init(api: Client?) {
        _model = State(initialValue: SocialModel(api: api))
    }

    var body: some View {
        Section {
            NavigationLink {
                ProfileEditor(model: model)
            } label: {
                LabeledContent("Handle", value: model.handle.map { "@\($0)" } ?? "Choose one")
            }
            if model.handle != nil {
                NavigationLink {
                    FriendsView(model: model)
                } label: {
                    LabeledContent("Friends") {
                        if model.incoming.isEmpty {
                            Text("\(model.friends.count)")
                        } else {
                            Text("\(model.incoming.count) asking").foregroundStyle(Color(.accent))
                        }
                    }
                }
            }
        } header: {
            Text("Profile and friends")
        } footer: {
            Text("Friends find you by your exact handle. Nobody can search or browse for you.")
        }
        .task { await model.load() }
    }
}

/// Claim or change the handle, and the optional display name.
struct ProfileEditor: View {
    let model: SocialModel
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted))
                    TextField("handle", text: $handle)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
            } footer: {
                Text(SocialModel.handleProblem(handle) ?? "3–20 letters, numbers or underscores.")
            }
            if let problem = model.problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle(model.handle == nil ? "Choose a handle" : "Your handle")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        saving = true
                        if await model.saveProfile(handle: handle, displayName: name) {
                            dismiss()
                        }
                        saving = false
                    }
                }
                .disabled(saving || SocialModel.handleProblem(handle) != nil)
            }
        }
        .onAppear {
            model.problem = nil
            handle = model.handle ?? ""
            name = model.displayName ?? ""
        }
    }
}

/// Requests both ways, friends, and blocks. Every act is a tap the other side is never told about,
/// except a request, which they see.
struct FriendsView: View {
    let model: SocialModel
    @State private var friendHandle = ""
    @State private var blocking: SocialUser?
    @State private var sending = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted))
                    TextField("their handle", text: $friendHandle)
                        .autocorrectionDisabled()
                        .onSubmit(send)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    Button("Send", action: send)
                        .disabled(sending || friendHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let notice = model.notice {
                    Text(notice).font(.callout)
                }
            } header: {
                Text("Add a friend")
            }

            if !model.incoming.isEmpty {
                Section("Asking you") {
                    ForEach(model.incoming, id: \.id) { request in
                        PersonRow(user: request.user) {
                            Button("Accept") { Task { await model.accept(request) } }
                                .buttonStyle(.borderedProminent)
                            Button("Decline") { Task { await model.withdraw(request) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !model.outgoing.isEmpty {
                Section("Waiting on") {
                    ForEach(model.outgoing, id: \.id) { request in
                        PersonRow(user: request.user) {
                            Button("Cancel") { Task { await model.withdraw(request) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Friends") {
                if model.friends.isEmpty {
                    Text("No friends yet. Ask someone for their handle.").foregroundStyle(Color(.muted))
                }
                ForEach(model.friends, id: \.userId) { friend in
                    PersonRow(user: friend) { EmptyView() }
                        .swipeActions {
                            Button("Block", role: .destructive) { blocking = friend }
                            Button("Remove") { Task { await model.remove(friend) } }
                        }
                        .contextMenu {
                            Button("Remove friend") { Task { await model.remove(friend) } }
                            Button("Block", role: .destructive) { blocking = friend }
                        }
                }
            }

            if !model.blocked.isEmpty {
                Section("Blocked") {
                    ForEach(model.blocked, id: \.userId) { person in
                        PersonRow(user: person) {
                            Button("Unblock") { Task { await model.unblock(person) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Friends")
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: model.problem) { model.problem = nil } }
        .confirmationDialog(
            "Block @\(blocking?.handle ?? "")?",
            isPresented: Binding(get: { blocking != nil }, set: {
                if !$0 {
                    blocking = nil
                }
            }),
            titleVisibility: .visible,
            presenting: blocking
        ) { person in
            Button("Block", role: .destructive) { Task { await model.block(person) } }
        } message: { _ in
            Text("You stop being friends, and neither of you can find the other. They aren't told.")
        }
    }

    private func send() {
        let handle = friendHandle
        Task {
            sending = true
            if await model.send(to: handle) {
                friendHandle = ""
            }
            sending = false
        }
    }
}

private struct PersonRow<Actions: View>: View {
    let user: SocialUser
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(user.monogram)
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .background(Color(.medallion).opacity(0.2), in: .circle)
                .accessibilityHidden(true)
            Text(user.label).lineLimit(1)
            Spacer(minLength: 8)
            actions()
        }
    }
}
