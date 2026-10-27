import PhotosUI
import SwiftUI

/// Edit profile (SOC-001b): the photo, first and last name, the handle, the email and whether
/// friends see it, then the way to Favorites and to the Sports you follow. Friends find you by the
/// handle and see the two names joined.
struct ProfileEditor: View {
    let model: SocialModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var handle = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var photo: PhotosPickerItem?
    @State private var saving = false
    @State private var favorites: FavoritesModel?

    /// A name needs no handle; once claimed, a handle can change but not go.
    private var handleProblem: String? {
        handle.isEmpty && model.handle == nil ? nil : SocialModel.handleProblem(handle)
    }

    var body: some View {
        Form {
            photoSection
            Section("Name") {
                TextField("First name (optional)", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last name (optional)", text: $lastName)
                    .textContentType(.familyName)
            }
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted)).accessibilityHidden(true)
                    TextField("Handle", text: $handle)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
            } header: {
                Text("Handle")
            } footer: {
                Text(handleProblem ?? "Friends find you by your exact handle. 3–20 letters, numbers or underscores.")
            }
            emailSection
            Section {
                if let favorites {
                    NavigationLink(destination: FavoritesEditor(model: favorites)) {
                        Label("Favorites", systemImage: "star")
                    }
                }
                if router?.sportsAvailable == true {
                    Button {
                        router?.showSportsFollows()
                    } label: {
                        Label("Sports you follow", systemImage: "sportscourt")
                    }
                }
            } footer: {
                Text(
                    "Your favorite films, shows and more show on your profile. "
                        + "The leagues, teams and players you follow stay in Sports."
                )
            }
            if let problem = model.problem {
                Text(problem).foregroundStyle(Color(.danger))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Edit profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        saving = true
                        if await model.saveProfile(handle: handle, firstName: firstName, lastName: lastName) {
                            dismiss()
                        }
                        saving = false
                    }
                }
                .disabled(saving || handleProblem != nil)
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        .onAppear {
            model.problem = nil
            handle = model.handle ?? ""
            firstName = model.account?.firstName ?? ""
            lastName = model.account?.lastName ?? ""
            if favorites == nil {
                favorites = FavoritesModel(api: model.api)
            }
        }
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                ProfileMedallion(account: model.account, size: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text(model.account?.avatarUrl == nil ? "Add photo" : "Change photo")
                    }
                    .disabled(saving)
                    if model.account?.avatarUrl != nil {
                        Button("Remove photo", role: .destructive) {
                            Task {
                                saving = true
                                await model.removeAvatar()
                                saving = false
                            }
                        }
                        .disabled(saving)
                    }
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text("Friends and the people in your groups see your photo. It is cropped to a square on this device.")
        }
    }

    @ViewBuilder private var emailSection: some View {
        if let email = model.account?.email {
            Section {
                LabeledContent("Email", value: email)
                if model.account?.emailShareable == true {
                    Toggle("Friends can see my email", isOn: Binding(
                        get: { model.shareEmail },
                        set: { share in Task { await model.setShareEmail(share) } }
                    ))
                }
            } footer: {
                Text(model.account?.emailShareable == true
                    ? "On your profile, for friends only. People in your groups never see it."
                    : "This is an Apple “Hide My Email” address. It takes mail only from Aaru, "
                    + "so it can’t be shared with friends.")
            }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        saving = true
        defer {
            saving = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = AvatarImage.jpeg(data)
        else {
            model.problem = "That photo could not be read. Try another."
            return
        }
        _ = await model.uploadAvatar(jpeg)
    }
}
