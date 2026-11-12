import SwiftUI

/// Me → Claude: a gentle coach to talk to. The conversation and the note stay in the vault.
struct CoachView: View {
    @Environment(Vault.self) private var vault
    @Environment(\.locale) private var locale
    let client: CoachClient

    @State private var email: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var problem: LocalizedStringResource?
    @State private var showingNote = false
    @State private var proposal: String?
    @State private var confirmClear = false

    init(client: CoachClient = .live()) {
        self.client = client
        _email = State(initialValue: client.signedInEmail)
    }

    private var english: Bool { AppLanguage.current(locale) == .english }
    private var coach: CoachState { vault.contents?.coach ?? CoachState() }

    var body: some View {
        Group {
            if !client.isConfigured {
                ComingSoon(text: "Claude will be here once the connection to Kitchen Tales is set up.")
            } else if email == nil {
                CoachSignIn(client: client) { email = client.signedInEmail }
            } else if !coach.consent {
                consent
            } else {
                conversation
            }
        }
        .navigationTitle(Text(verbatim: "Claude"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if email != nil && coach.consent {
                ToolbarItem(placement: .primaryAction) { menu }
            }
        }
        .sheet(isPresented: $showingNote) {
            CoachNoteEditor(note: coach.note) { text in update { $0.note = text } }
        }
        .sheet(item: Binding(get: { proposal.map { Proposal(text: $0) } }, set: { proposal = $0?.text })) { item in
            CoachNoteEditor(note: coach.note.isEmpty ? item.text : coach.note + "\n" + item.text, proposed: true) { text in
                update { $0.note = text }
            }
        }
        .confirmationDialog(Text("Clear the conversation?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(role: .destructive) { update { $0.messages = [] } } label: { Text("Clear") }
        } message: {
            Text("The note stays. Only the messages on this iPhone are deleted.")
        }
    }

    private struct Proposal: Identifiable {
        let text: String
        var id: String { text }
    }

    private func update(_ change: (inout CoachState) -> Void) {
        try? vault.update { contents in
            var state = contents.coach ?? CoachState()
            change(&state)
            contents.coach = state
        }
    }

    // MARK: Consent

    private var consent: some View {
        NotebookPage {
            SpecimenLabel(text: "Before you start")
            Text("Talk with Claude")
                .font(.notebookTitle())
            Text("Claude answers like a gentle coach: short, practical, without judging. It is not therapy and not a doctor.")
                .foregroundStyle(Theme.inkMuted)
            NotebookCard {
                SpecimenLabel(text: "What is sent")
                Text("Only what you write here, the recent messages, your note \"What Claude knows about me\" and what you allow below. Never your journal. Nothing is kept on the server; the conversation stays encrypted on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                levelPicker
            }
            Button {
                update { $0.consent = true }
            } label: {
                Text("Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var levelPicker: some View {
        Picker(selection: Binding(get: { coach.level }, set: { level in update { $0.level = level } })) {
            Text("Only the conversation").tag(CoachState.Level.chat)
            Text("The month's intention").tag(CoachState.Level.intention)
            Text("The intention and the month's Fridays").tag(CoachState.Level.month)
        } label: {
            Text("Claude also sees")
        }
        .pickerStyle(.inline)
    }

    // MARK: Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if coach.messages.isEmpty {
                            Text("What is on your mind today?")
                                .font(.notebookTitle(.title3).italic())
                                .foregroundStyle(Theme.moss)
                                .padding(.vertical, 24)
                        }
                        ForEach(coach.messages) { message in
                            Bubble(message: message).id(message.id)
                        }
                        if sending {
                            ProgressView().padding(.leading, 8).id("typing")
                        }
                        if let problem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: coach.messages.count) {
                    guard let last = coach.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onAppear {
                    if let last = coach.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(text: $draft, axis: .vertical) { Text("Write to Claude") }
                    .lineLimit(1...6)
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Text("Send"))
            }
            .padding(12)
            .background(Theme.paper)
        }
        .background(Theme.paper)
    }

    private var menu: some View {
        Menu {
            Button { showingNote = true } label: { Label { Text("What Claude knows about me") } icon: { Image(systemName: "note.text") } }
            Button(action: remember) { Label { Text("Remember from this conversation") } icon: { Image(systemName: "sparkles") } }
                .disabled(coach.messages.isEmpty || sending)
            Menu {
                levelPicker
            } label: {
                Label { Text("What Claude sees") } icon: { Image(systemName: "eye") }
            }
            Divider()
            Button(role: .destructive) { confirmClear = true } label: { Label { Text("Clear the conversation") } icon: { Image(systemName: "trash") } }
            Button {
                client.signOut()
                email = nil
            } label: {
                Label { Text("Sign out of Kitchen Tales") } icon: { Image(systemName: "rectangle.portrait.and.arrow.right") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let contents = vault.contents else { return }
        draft = ""
        problem = nil
        update { $0.append(.init(role: .user, text: text)) }
        let state = vault.contents?.coach ?? CoachState()
        let context = contents.coachContext(state.level, english: english)
        sending = true
        Task {
            defer { sending = false }
            do {
                let answer = try await client.chat(state.messages, note: state.note, context: context, english: english)
                update { $0.append(.init(role: .assistant, text: answer)) }
            } catch {
                show(error)
            }
        }
    }

    private func remember() {
        let state = coach
        sending = true
        Task {
            defer { sending = false }
            do {
                let text = try await client.proposeMemory(state.messages, note: state.note, english: english)
                if text.isEmpty {
                    problem = "Nothing new to add to the note."
                } else {
                    proposal = text
                }
            } catch {
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        switch error as? CoachError {
        case .signedOut:
            email = nil
        case .offline:
            problem = "No connection. Your message is saved; send another when you are online."
        case .server(let message) where !message.isEmpty:
            problem = "\(message)"
        default:
            problem = "Claude cannot answer right now. Try again in a moment."
        }
    }
}

private struct Bubble: View {
    let message: CoachState.Message

    var body: some View {
        let mine = message.role == .user
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(mine ? Theme.moss.opacity(0.14) : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(mine ? .clear : Theme.cardBorder))
            if !mine { Spacer(minLength: 40) }
        }
    }
}

/// Signing in with the Kitchen Tales account, once per iPhone.
private struct CoachSignIn: View {
    let client: CoachClient
    let onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                TextField(text: $email) { Text("Email") }
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(text: $password) { Text("Password") }
                    .textContentType(.password)
            } header: {
                Text("Your Kitchen Tales account")
            } footer: {
                Text("For now, Claude in Fallow runs through Kitchen Tales. Sign in once; only a sign-in token stays on this iPhone, in the Keychain.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            Section {
                Button(action: signIn) {
                    if working { ProgressView() } else { Text("Sign in") }
                }
                .disabled(working || email.isEmpty || password.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private func signIn() {
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                try await client.signIn(email: email, password: password)
                password = ""
                onDone()
            } catch CoachError.wrongPassword {
                problem = "That email and password do not match a Kitchen Tales account."
            } catch CoachError.newPasswordRequired {
                problem = "This account still has its temporary password. Sign in to Kitchen Tales once to choose your own, then come back."
            } catch CoachError.offline {
                problem = "No connection. Try again when you are online."
            } catch {
                problem = "Signing in did not work. Try again in a moment."
            }
        }
    }
}

/// "What Claude knows about me": written and approved by the person, sent with every message.
private struct CoachNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let proposed: Bool
    let onSave: (String) -> Void

    init(note: String, proposed: Bool = false, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: note)
        self.proposed = proposed
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $text, axis: .vertical) { Text("What helps you, what you avoid, where you left off…") }
                        .lineLimit(6...20)
                } footer: {
                    if proposed {
                        Text("Claude proposed the last lines. Change or delete anything before saving.")
                    } else {
                        Text("Claude reads this with every message. Keep only what you are happy to share.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(Text("What Claude knows about me"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(String(text.prefix(CoachState.maxNote)))
                        dismiss()
                    } label: { Text("Save") }
                }
            }
        }
    }
}
