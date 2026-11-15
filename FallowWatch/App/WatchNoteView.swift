import SwiftUI
import WatchKit

/// A quick note, dictated or scribbled. It is sealed for the vault and sent to the iPhone; the
/// watch keeps only the count.
struct WatchNoteView: View {
    @State private var text = ""
    @State private var sealed = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if sealed {
                    SealedNote {
                        text = ""
                        sealed = false
                    }
                } else {
                    TextField("A line is enough", text: $text, axis: .vertical)
                    Button {
                        send()
                    } label: {
                        Label("Seal and send", systemImage: "lock")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchPalette.mossDeep)
                    .handGestureShortcut(.primaryAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if failed {
                        Text("Open Fallow on your iPhone once, then try again.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.inkMuted)
                    }
                    NotesToday()
                }
            }
        }
        .navigationTitle(Text("Note"))
    }

    private func send() {
        guard let entry = ReminderActions.lineEntry(text) else { return }
        do {
            try PhoneLink.shared.send(entry)
        } catch {
            failed = true
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WatchStats.addNote()
        failed = false
        sealed = true
        WKInterfaceDevice.current().play(.success)
    }
}

private struct SealedNote: View {
    let another: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.title2)
                .foregroundStyle(WatchPalette.moss)
            Text("Sealed")
                .font(.system(.headline, design: .serif))
            Text("Read it on your iPhone, after Face ID.")
                .font(.footnote)
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
            Button("Another note", action: another)
                .handGestureShortcut(.primaryAction)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NotesToday: View {
    var body: some View {
        let count = WatchStats.notes(on: DayKey.string(.now))
        if count > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) sealed today")
                    .font(.footnote)
                if let last = WatchStats.lastNote {
                    Text("Last at \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.inkMuted)
                }
                Text("They move to the journal the next time you open Fallow on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.inkMuted)
            }
        }
    }
}
