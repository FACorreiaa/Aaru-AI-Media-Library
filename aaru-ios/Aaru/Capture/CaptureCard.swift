import SwiftUI

/// AG-006: a capture under "Waiting for you", beside agents' requests. While Aaru reads it, the
/// owl; once planned, what it adds and what needs a pick. Opens the review (the import's page).
struct CaptureCard: View {
    let job: ImportJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your capture").eyebrow()
                if let headline = job.captureHeadline {
                    Text(headline)
                        .font(.aaruDisplay(.title3, weight: .medium))
                        .foregroundStyle(Color(.ink))
                    Text("Nothing changes until you approve")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                } else {
                    Text(job.stateLabel)
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                }
            }
            Spacer(minLength: 0)
            if job.isWorking {
                AgentPresence(label: "Aaru is reading your capture")
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(true)
            }
        }
        .panel()
        .edgeLit()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
