import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    @StateObject private var weather = WeatherManager()
    @StateObject private var local = LocalNewsManager()
    @State private var newTopic = ""
    @State private var isScanning = false
    @State private var showSchedule = false
    @State private var recencyEditTopic: Topic?
    /// Topic ids whose results section is collapsed (default: expanded).
    @State private var collapsedTopics: Set<UUID> = []
    /// Whether the list of added topics (under the add field) is hidden.
    @State private var topicsListCollapsed = false
    /// Edit mode for the added-topics list (driven from its header, not the toolbar).
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                WeatherSection(weather: weather)
                topicsSection
                // Each topic gets its own collapsible results section, below Topics.
                ForEach(store.userTopics) { topic in
                    topicMatchesSection(for: topic)
                }
                LocalNewsSection(local: local)
                matchesSection(title: "Local news matches", matches: store.localMatches, filter: .local)
            }
            .navigationTitle("News Scanner")
            .refreshable { await weather.refresh() }
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    scheduleMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scanNow() }
                    } label: {
                        if isScanning {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isScanning)
                }
            }
            // Per-topic custom recency filter editor.
            .sheet(item: $recencyEditTopic) { topic in
                RecencyEditor(topic: topic)
            }
            // Full schedule configurator (daily time / custom interval), on demand.
            .sheet(isPresented: $showSchedule) {
                NavigationStack {
                    ScheduleView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSchedule = false }
                            }
                        }
                }
            }
            // In-app browser for tapped notifications and matches.
            .sheet(item: Binding(
                get: { router.pendingURL.map(IdentifiedURL.init) },
                set: { router.pendingURL = $0?.url }
            )) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
        // Load local weather + resolve place for local news when the view appears.
        .task { await weather.refresh() }
        .task { await local.refresh() }
        // Foreground auto-scan loop. Restarts whenever the interval changes.
        // Precise timing only holds in the foreground; background is opportunistic.
        .task(id: scanLoopToken) {
            while !Task.isCancelled {
                await ScanService.runScan()
                try? await Task.sleep(nanoseconds: UInt64(settings.interval * 1_000_000_000))
            }
        }
    }

    private var scanLoopToken: String {
        "\(settings.preset.rawValue)-\(settings.customMinutes)-\(settings.dailyHour)-\(settings.dailyMinute)"
    }

    // MARK: - Per-topic recency filter

    /// Light pill-menu on each topic row to pick its display recency window.
    private func recencyMenu(for topic: Topic) -> some View {
        Menu {
            Button {
                store.setWindow(nil, for: topic)
            } label: {
                if topic.window == nil { Label("All time", systemImage: "checkmark") }
                else { Text("All time") }
            }
            Divider()
            ForEach(RecencyWindow.presets, id: \.self) { window in
                Button {
                    store.setWindow(window, for: topic)
                } label: {
                    if topic.window == window { Label(window.longLabel, systemImage: "checkmark") }
                    else { Text(window.longLabel) }
                }
            }
            Divider()
            Button {
                recencyEditTopic = topic
            } label: {
                Label("Custom…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Text(topic.window?.shortLabel ?? "All")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .foregroundStyle(topic.window == nil ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    private var topicsSection: some View {
        Section("Topics") {
            HStack {
                TextField("Add a topic…", text: $newTopic)
                    .textInputAutocapitalization(.never)
                    .onSubmit(addTopic)
                Button("Add", action: addTopic)
                    .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if store.userTopics.isEmpty {
                Text("No topics yet. Add one to start scanning Google News.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                // Collapsible header for the added-topics list, with Edit on the right.
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            topicsListCollapsed.toggle()
                            if topicsListCollapsed { editMode = .inactive }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: topicsListCollapsed ? "chevron.right" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Added topics")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(store.userTopics.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if !topicsListCollapsed {
                        EditButton()
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                    }
                }
            }

            if !topicsListCollapsed {
                ForEach(store.userTopics) { topic in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.query)
                            if topic.needsSeeding {
                                Text("Will load current matches on next scan")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 4)
                        recencyMenu(for: topic)
                        Toggle("", isOn: Binding(
                            get: { topic.isEnabled },
                            set: { store.setEnabled($0, for: topic) }
                        ))
                        .labelsHidden()
                    }
                    // Explicit, discoverable delete (the row is otherwise controls).
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.remove(topic)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    store.removeTopics(ids: offsets.map { store.userTopics[$0].id })
                }
            }
        }
    }

    /// Schedule lives here now — a toolbar dropdown shown only when tapped, instead
    /// of an always-visible section. Quick frequency pick inline; daily/custom open
    /// the full configurator sheet.
    private var scheduleMenu: some View {
        Menu {
            Picker("Scan frequency", selection: $settings.preset) {
                ForEach(SchedulePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            Divider()
            Picker("Results shown", selection: $settings.resultsPerSection) {
                ForEach(AppSettings.minResults...AppSettings.maxResults, id: \.self) { n in
                    Text("\(n) per section").tag(n)
                }
            }
            Divider()
            Button {
                showSchedule = true
            } label: {
                Label("Schedule details…", systemImage: "slider.horizontal.3")
            }
            Section {
                Text("Last scan: \(lastScanText)")
            }
        } label: {
            Image(systemName: "clock")
        }
    }

    /// Inline matches shown directly under their owning section (per topic / local
    /// news). Hidden entirely when there are none. Caps the inline list to the
    /// user's preferred count and links to the full filtered list when there's more.
    /// A single topic's collapsible results section: a tappable header row (with a
    /// chevron and match count) that shows/hides the matches below it. Always shown
    /// for every user topic — even when the recency filter (or a pending first scan)
    /// leaves it empty — so the topic is always visible and collapsible.
    @ViewBuilder
    private func topicMatchesSection(for topic: Topic) -> some View {
        let matches = store.matches(for: topic)
        let expanded = !collapsedTopics.contains(topic.id)
        let limit = settings.resultsPerSection
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { toggleCollapsed(topic) }
            } label: {
                HStack(spacing: 8) {
                    Text(topic.query)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(matches.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if matches.isEmpty {
                    Text(emptyNote(for: topic))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches.prefix(limit)) { match in
                        MatchRow(match: match, showsTopic: false)
                    }
                    if matches.count > limit {
                        NavigationLink {
                            RecentMatchesView(filter: .topic(topic.query))
                        } label: {
                            Text("View all \(matches.count)").font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    /// Explains an empty topic section: filtered out by the recency window, or no
    /// matches scanned yet.
    private func emptyNote(for topic: Topic) -> String {
        let hasUnfiltered = store.recent.contains { $0.scope == nil && $0.topicQuery == topic.query }
        if let window = topic.window, hasUnfiltered {
            return "No matches in the \(window.longLabel.lowercased()). Tap the filter pill to widen."
        }
        return "No matches yet — they'll appear after the next scan."
    }

    private func toggleCollapsed(_ topic: Topic) {
        if collapsedTopics.contains(topic.id) { collapsedTopics.remove(topic.id) }
        else { collapsedTopics.insert(topic.id) }
    }

    @ViewBuilder
    private func matchesSection(title: String, matches: [RecentMatch], filter: MatchFilter,
                                showsTopic: Bool = true) -> some View {
        if !matches.isEmpty {
            let limit = settings.resultsPerSection
            Section(title) {
                ForEach(matches.prefix(limit)) { match in
                    MatchRow(match: match, showsTopic: showsTopic)
                }
                if matches.count > limit {
                    NavigationLink {
                        RecentMatchesView(filter: filter)
                    } label: {
                        Text("View all \(matches.count)")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var lastScanText: String {
        guard let date = settings.lastScan else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    // MARK: - Actions

    private func addTopic() {
        store.addTopic(newTopic)
        newTopic = ""
    }

    @MainActor
    private func scanNow() async {
        isScanning = true
        await ScanService.runScan()
        await weather.refresh()
        isScanning = false
    }
}

/// Wrapper so a bare URL can drive `.sheet(item:)`.
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
