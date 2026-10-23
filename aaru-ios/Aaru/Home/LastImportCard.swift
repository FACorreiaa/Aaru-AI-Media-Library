import SwiftUI

/// The Field's note of the newest import (VIEWS.md `JobLedger`, collapsed): its file or source,
/// where it stands, and while it runs, the owl and how far matching has got. Opens the import.
struct LastImportCard: View {
    let job: ImportJob

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last import").eyebrow()
                Text(job.filename ?? job.sourceLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.ink))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.stateLabel)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
                if job.isWorking, job.rowsTotal > 0 {
                    ProgressView(value: Double(min(job.rowsMatched, job.rowsTotal)), total: Double(job.rowsTotal))
                        .tint(Color(.gold))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            if job.isWorking {
                AgentPresence(label: "Aaru is matching this import")
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(true)
            }
        }
        .panel()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Previews

#Preview("Last import") {
    VStack(spacing: 16) {
        LastImportCard(job: .sampleWorking)
        LastImportCard(job: .sampleDone)
    }
    .padding(20)
    .frame(width: 360)
}
