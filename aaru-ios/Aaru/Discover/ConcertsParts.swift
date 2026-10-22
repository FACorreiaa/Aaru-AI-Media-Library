import MapKit
import SwiftUI

// The Concerts view's map and small pieces, out of `ConcertsView.swift` to keep it under the
// file limit.

// MARK: Map

/// The searched area: its centre and the radius as a circle. Ticketmaster gives no venue
/// positions, so the concerts are listed under it rather than pinned on it.
struct ConcertsMap: View {
    let name: String
    let point: ConcertPoint
    let radiusKm: Int

    @ScaledMetric(relativeTo: .body) private var height = 240

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var region: MKCoordinateRegion {
        let span = CLLocationDistance(radiusKm) * 1000 * 2.4
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            MapCircle(center: coordinate, radius: CLLocationDistance(radiusKm) * 1000)
                .foregroundStyle(Color(.accent).opacity(0.15))
                .stroke(Color(.accent), lineWidth: 2)
            Marker(name, systemImage: "music.note", coordinate: coordinate)
                .tint(Color(.accent))
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 10))
        // A new centre or radius frames the map again.
        .id([point.latitude, point.longitude, Double(radiusKm)])
        .accessibilityElement()
        .accessibilityLabel("Map of the \(radiusKm) kilometre area around \(name)")
    }
}

// MARK: Pieces

/// A section's title, in the display serif like Home's rows.
struct ConcertsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.aaruDisplay(.title3, weight: .semibold))
            .foregroundStyle(Color(.ink))
            .accessibilityAddTraits(.isHeader)
    }
}

struct QuietNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(.muted))
    }
}

/// Still placeholder rows while concerts load: redacted, nothing shimmers.
struct PlaceholderRows: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ConcertRow.placeholders.prefix(count), id: \.id) { concert in
                ConcertRow(concert: concert)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

struct RadiusPicker: View {
    @Binding var radius: ConcertRadius

    var body: some View {
        Picker("Radius", selection: $radius) {
            ForEach(ConcertRadius.allCases, id: \.self) { radius in
                Text(radius.label)
                    .accessibilityLabel(radius.spoken)
                    .tag(radius)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct LayoutPicker: View {
    @Binding var layout: ConcertsModel.Layout

    var body: some View {
        Picker("Show as", selection: $layout) {
            ForEach(ConcertsModel.Layout.allCases) { layout in
                Label(layout.label, systemImage: layout.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
