import SwiftUI

/// Shown whenever the vault is locked. Asks for Face ID straight away.
struct LockView: View {
    @Environment(Vault.self) private var vault

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.sage)
            Text("Fallow is locked")
                .font(.notebookTitle(.title))
            if let message = errorMessage {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 32)
            }
            Button {
                Task { await unlock() }
            } label: {
                Label { Text("Unlock") } icon: { Image(systemName: "faceid") }
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .task { await unlock() }
    }

    private var errorMessage: LocalizedStringResource? {
        guard let error = vault.lastError else { return nil }
        switch error {
        case .cancelled:
            return nil
        case .wrongKey, .corrupted:
            return "Your journal could not be opened. Your data is still on this iPhone."
        case .noKey:
            return "The key for this journal is missing on this iPhone."
        case .keychain:
            return "Face ID did not work. Try again."
        }
    }

    private func unlock() async {
        await vault.unlock(reason: String(localized: "Open your journal"))
    }
}
