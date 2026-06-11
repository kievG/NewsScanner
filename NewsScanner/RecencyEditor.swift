import SwiftUI

/// Lightweight custom recency-window editor for a single topic: a value stepper
/// plus a unit picker (hours / days / weeks / months). Reachable from the topic's
/// recency pill → "Custom…".
struct RecencyEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let topic: Topic
    @State private var value: Int
    @State private var unit: RecencyUnit

    init(topic: Topic) {
        self.topic = topic
        _value = State(initialValue: topic.window?.value ?? 1)
        _unit = State(initialValue: topic.window?.unit ?? .days)
    }

    private var window: RecencyWindow { RecencyWindow(value: value, unit: unit) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Show articles from the past") {
                    Stepper(value: $value, in: 1...99) {
                        Text("\(value) \(value == 1 ? unit.singular : unit.plural)")
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(RecencyUnit.allCases) { unit in
                            Text(unit.plural.capitalized).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("“\(topic.query)” will show only matches published in the \(window.longLabel.lowercased()).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recency filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setWindow(window, for: topic)
                        dismiss()
                    }
                }
            }
        }
    }
}
