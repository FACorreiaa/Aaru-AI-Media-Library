import AaruAPI

/// The models behind Settings' pages, one per page so a failure on one page never follows you
/// to the next (UX-029). Shared by the iPhone sheet, the iPad sidebar row and the Mac Settings
/// scene, and cleared on sign-out. Import is `ImportsModel`, which Home also reads.
@MainActor
final class SettingsServices {
    let account: AccountModel
    /// The name and handle (Account) and friends (Friends & privacy).
    let social: SocialModel
    let notifications: NotificationsModel
    let connections: ConnectionsModel
    let data: DataModel
    let history: HistoryModel

    init(api: Client?) {
        account = AccountModel(api: api)
        social = SocialModel(api: api)
        notifications = NotificationsModel(api: api)
        connections = ConnectionsModel(api: api)
        data = DataModel(api: api)
        history = HistoryModel(api: api)
    }

    func reset() {
        account.reset()
        social.reset()
        notifications.reset()
        connections.reset()
        data.reset()
        history.reset()
    }
}

/// What every Settings page may need, handed down as one value.
@MainActor
struct SettingsContext {
    let api: Client?
    let imports: ImportsModel
    let models: SettingsServices
    let library: LibraryModel
    let lists: ListsModel
    var onSignOut: () -> Void
    /// Deletes the account; a message when it failed.
    var onDeleteAccount: () async -> String?

    /// After an undo or an applied import: the library and lists catch up.
    func refreshLibrary() async {
        await library.sync(api: api)
        await lists.load()
    }
}
