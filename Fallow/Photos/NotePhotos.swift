import PhotosUI
import SwiftUI

/// The photos of a note being written: pick up to four, see them small, remove one, open one.
struct NotePhotosSection: View {
    @Environment(Vault.self) private var vault
    @Binding var photos: [String]?
    @State private var picked: [PhotosPickerItem] = []
    @State private var adding = false
    @State private var failed = false
    @State private var showing: String?

    static let limit = 4

    private var ids: [String] { photos ?? [] }

    var body: some View {
        Section {
            if !ids.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ids, id: \.self) { id in
                            NotePhoto(id: id)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture { showing = id }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation { photos = ids.filter { $0 != id } }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                    .accessibilityLabel(Text("Remove photo"))
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if ids.count < Self.limit {
                PhotosPicker(selection: $picked, maxSelectionCount: Self.limit - ids.count, matching: .images) {
                    HStack {
                        Label { Text("Add photos") } icon: { Image(systemName: "photo.on.rectangle") }
                        if adding {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(adding)
            }
            if failed {
                Text("A photo could not be added.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Kept encrypted with your journal, without location or camera details.")
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await add(items) }
        }
        .fullScreenCover(item: Binding(get: { showing.map(PhotoID.init) }, set: { showing = $0?.id })) { photo in
            PhotoViewer(id: photo.id)
        }
    }

    private func add(_ items: [PhotosPickerItem]) async {
        adding = true
        failed = false
        defer {
            adding = false
            picked = []
        }
        var added = ids
        for item in items where added.count < Self.limit {
            guard let original = try? await item.loadTransferable(type: Data.self),
                  let jpeg = PhotoPrep.jpeg(from: original),
                  let id = try? vault.addPhoto(jpeg) else {
                failed = true
                continue
            }
            added.append(id)
        }
        photos = added.isEmpty ? nil : added
    }
}

private struct PhotoID: Identifiable {
    let id: String
}

/// One photo from the vault, filled to its frame. A soft placeholder while it opens,
/// or when the photo is not on this iPhone (a note brought from a .fallow file).
struct NotePhoto: View {
    @Environment(Vault.self) private var vault
    let id: String
    var fit: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.card
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.sage)
            }
        }
        .task(id: id) {
            image = vault.photo(id).flatMap(UIImage.init(data:))
        }
        .accessibilityLabel(Text("Photo"))
    }
}

/// A photo full screen.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            NotePhoto(id: id, fit: .fit)
                .background(Color.black)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding()
            .accessibilityLabel(Text("Close"))
        }
    }
}
