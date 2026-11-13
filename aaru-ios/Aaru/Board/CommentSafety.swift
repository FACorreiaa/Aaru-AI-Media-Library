import AaruAPI
import SwiftUI

/// Reporting a comment and blocking an author, for the post screen: the report sheet, and Block
/// asked first in the words the profile uses. Neither person is told.
struct CommentSafety: ViewModifier {
    let model: PostModel
    @Binding var reporting: BoardComment?
    @Binding var blocking: SocialUser?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { reporting != nil }, set: {
                if !$0 {
                    reporting = nil
                }
            })) {
                if let comment = reporting {
                    ReportPostSheet(
                        noun: String(localized: "comment"),
                        authorName: comment.author?.inviteName ?? String(localized: "They")
                    ) { reason, note in
                        await model.report(comment, reason: reason, note: note)
                            ? nil : (model.problem ?? String(localized: "That report was not sent."))
                    }
                }
            }
            .confirmationDialog(
                "Block \(blocking?.inviteName ?? "")?",
                isPresented: Binding(get: { blocking != nil }, set: {
                    if !$0 {
                        blocking = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: blocking
            ) { person in
                Button("Block", role: .destructive) { Task { await model.block(person) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("They are removed from your friends and can't see your library. You can unblock them in Friends.")
            }
    }
}
