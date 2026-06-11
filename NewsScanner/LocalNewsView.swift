import SwiftUI

/// "Local news" section. The scope selectors are shown as pills inside a
/// disclosure that stays collapsed (pills hidden) until the user opens it or has a
/// scope active — so it takes no space when not used. Each enabled pill scans
/// Google News for the device's place at that level; results land in Local news
/// matches directly below.
struct LocalNewsSection: View {
    @ObservedObject var local: LocalNewsManager
    @EnvironmentObject private var settings: AppSettings

    @State private var expanded = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(LocationScope.allCases) { scope in
                        pill(for: scope)
                    }
                }
                .padding(.vertical, 4)

                if let note = statusNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack {
                    Text("Local news")
                    Spacer()
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Show the pills by default only when local news is actually in use.
        .onAppear { expanded = !settings.localScopes.isEmpty }
    }

    // MARK: - Pills

    private func pill(for scope: LocationScope) -> some View {
        let isOn = settings.localScopes.contains(scope)
        let text = (isOn ? local.place?.name(for: scope) : nil) ?? scope.label
        return Button {
            if isOn { settings.localScopes.remove(scope) }
            else { settings.localScopes.insert(scope) }
            Task { await local.applyScopeChange() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scope.symbol)
                    .font(.caption)
                Text(text)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)),
                in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(local.phase == .denied)
    }

    // MARK: - Status

    private var summary: String {
        if local.phase == .denied { return "Location off" }
        let active = LocationScope.allCases.filter { settings.localScopes.contains($0) }
        guard !active.isEmpty else { return "Off" }
        return active.map { local.place?.name(for: $0) ?? $0.label }.joined(separator: " · ")
    }

    private var statusNote: String? {
        switch local.phase {
        case .denied:      return "Enable location in Settings to use local news."
        case .loading:     return "Locating…"
        case .unavailable: return "Location unavailable right now."
        case .idle, .loaded: return nil
        }
    }
}
