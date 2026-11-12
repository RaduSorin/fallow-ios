import Foundation
import Testing
import UIKit
@testable import Fallow

@MainActor
struct PhotoTests {
    let folder = URL.temporaryDirectory.appending(path: "photos-\(UUID().uuidString)", directoryHint: .isDirectory)

    func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.jpegData(compressionQuality: 0.9)!
    }

    func unlockedVault() throws -> Vault {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
        try vault.setUp(settings: VaultSettings())
        return vault
    }

    @Test func bigPhotosAreMadeSmaller() throws {
        let prepared = try #require(PhotoPrep.jpeg(from: jpeg(width: 4000, height: 3000)))
        let image = try #require(UIImage(data: prepared))
        #expect(image.size.width == 1600)
        #expect(image.size.height == 1200)
        let small = try #require(PhotoPrep.jpeg(from: jpeg(width: 300, height: 200)))
        #expect(UIImage(data: small)?.size == CGSize(width: 300, height: 200))
        #expect(PhotoPrep.jpeg(from: Data("not a photo".utf8)) == nil)
    }

    @Test func photosAreSealedAndOpenOnlyWithTheVault() throws {
        let vault = try unlockedVault()
        let original = jpeg(width: 50, height: 50)
        let id = try vault.addPhoto(original)
        #expect(vault.contents?.photoKey?.count == 32)
        let sealed = try #require(vault.photos.read(id))
        #expect(sealed != original)
        #expect(vault.photo(id) == original)
        vault.lock()
        #expect(vault.photo(id) == nil)
    }

    @Test func unusedPhotosAreRemoved() throws {
        let vault = try unlockedVault()
        let kept = try vault.addPhoto(jpeg(width: 10, height: 10))
        let dropped = try vault.addPhoto(jpeg(width: 10, height: 10))
        var note = Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .free, text: "Snow")
        note.photos = [kept]
        try vault.update { $0.save(note) }
        vault.removeUnusedPhotos()
        #expect(vault.photos.ids() == [kept])
        _ = dropped
        try vault.eraseEverything()
        #expect(vault.photos.ids().isEmpty)
    }

    @Test func photosTravelWithTheBackup() async throws {
        let vault = try unlockedVault()
        let original = jpeg(width: 20, height: 20)
        let id = try vault.addPhoto(original)
        var note = Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .free)
        note.photos = [id]
        try vault.update { $0.save(note) }

        let store = FolderBackupStore(url: folder.appending(path: "vault.fallowbackup"))
        let keys = InMemoryBackupKey()
        let backup = Backup(store: store, keys: keys, defaults: UserDefaults(suiteName: "photo-\(UUID().uuidString)")!, photos: vault.photos)
        let first = try #require(vault.contents)
        await backup.backUp(first)
        #expect(try await store.photoIDs() == [id])

        // A new iPhone: an empty photo folder, the same iCloud.
        let newPhotos = PhotoStore(folder: folder.appending(path: "NewPhone", directoryHint: .isDirectory))
        let newBackup = Backup(store: store, keys: keys, defaults: UserDefaults(suiteName: "photo-\(UUID().uuidString)")!, photos: newPhotos)
        let restored = try await newBackup.restore()
        let newVault = Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "NewPhone/vault.fallow"), photos: newPhotos)
        try newVault.restore(restored)
        #expect(newVault.photo(id) == original)

        // The note loses its photo: the copy in iCloud goes at the next backup.
        try vault.update { $0.notes[0].photos = nil }
        let second = try #require(vault.contents)
        await backup.backUp(second)
        #expect(try await store.photoIDs().isEmpty)
    }
}

struct OnDeviceAITests {
    @Test func digestReadsTheMonthInOrder() {
        let month = MonthID(year: 2026, month: 11)
        var plan = MonthPlan.blank(month)
        plan.intention = "Make room for slowness"
        plan.success = "In bed before 11"
        let notes = [
            Note(date: "2026-11-20", month: month, kind: .free, text: "A long walk."),
            Note(date: "2026-11-13", month: month, kind: .friday, title: "Breathing", before: 7, after: 3, fit: .yes, text: "Calmer."),
        ]
        let digest = OnDeviceAI.digest(plan: plan, notes: notes)
        #expect(digest.hasPrefix("Intention: Make room for slowness\nSign it went well: In bed before 11"))
        let friday = digest.range(of: "2026-11-13 friday – Breathing (feeling 7 → 3 of 10) [fit: da]: Calmer.")
        let walk = digest.range(of: "2026-11-20 free: A long walk.")
        #expect(friday != nil && walk != nil)
        if let friday, let walk { #expect(friday.lowerBound < walk.lowerBound) }
    }

    @Test func longMonthsKeepTheLatestNotes() {
        let month = MonthID(year: 2026, month: 11)
        let notes = (1...200).map { Note(date: String(format: "2026-11-%02d", ($0 % 28) + 1), month: month, kind: .free, text: String(repeating: "x", count: 100) + "#\($0)") }
        let digest = OnDeviceAI.digest(plan: nil, notes: notes)
        #expect(digest.count == OnDeviceAI.maxCharacters)
    }
}
