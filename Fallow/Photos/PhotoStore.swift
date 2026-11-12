import CryptoKit
import Foundation
import UIKit

/// Photos in notes. Each photo is its own sealed file (AES-GCM with the photo key that lives in
/// the vault), so the vault file stays small. The same sealed bytes go to the iCloud backup,
/// which can only be opened with a vault that holds the key.
struct PhotoStore: Sendable {
    let folder: URL

    static var live: PhotoStore {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return PhotoStore(folder: base.appending(path: "Photos", directoryHint: .isDirectory))
    }

    static let fileExtension = "fphoto"

    func url(_ id: String) -> URL { folder.appending(path: "\(id).\(Self.fileExtension)") }

    func write(_ sealed: Data, id: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try sealed.write(to: url(id), options: [.atomic, .completeFileProtection])
    }

    func read(_ id: String) -> Data? {
        try? Data(contentsOf: url(id))
    }

    func ids() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter { $0.pathExtension == Self.fileExtension }.map { $0.deletingPathExtension().lastPathComponent })
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: url(id))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Drops photos no note uses any more (removed from a note, or the note deleted).
    func removeUnused(keeping used: Set<String>) {
        for id in ids().subtracting(used) { delete(id) }
    }
}

extension VaultContents {
    /// Every photo id a note (or the note being written) still uses.
    var photoIDs: Set<String> {
        Set(notes.flatMap { $0.photos ?? [] } + (draft?.photos ?? []))
    }
}

/// Makes a picked photo ready to keep: at most 1600 pixels on the long side, re-drawn as JPEG.
/// Re-drawing also drops the original's metadata (location, camera, time).
enum PhotoPrep {
    static func jpeg(from data: Data, maxSide: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let redrawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return redrawn.jpegData(compressionQuality: 0.8)
    }
}
