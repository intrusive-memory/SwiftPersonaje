import Foundation
import Testing

@testable import SwiftPersonaje

/// SN-4 and SN-6: writing a scene-number plan back, with a byte-equal backup,
/// an atomic write, a read-back check and a restore. Synthetic, invented
/// screenplays in a temp directory only.
@Suite("Scene-number write, backup and restore (SN-4, SN-6)")
struct SceneNumberWriterTests {

  // MARK: - Helpers

  private let unnumbered = """
    Title: Lamps

    INT. WORKSHOP - DAY

    MARA
    Hand me that.

    EXT. YARD - NIGHT

    Rain on the tin roof.

    """

  private let numbered = """
    Title: Lamps

    INT. WORKSHOP - DAY #1#

    MARA
    Hand me that.

    """

  /// A project folder with `text` at `episodes/<name>`, and a backup root
  /// inside it that doesn't exist yet.
  private func project(_ text: String, named name: String = "e1.fountain") throws
    -> (root: URL, file: URL, backupRoot: URL)
  {
    let root = try Synthetic.makeDirectory()
    let episodes = root.appendingPathComponent("episodes", isDirectory: true)
    try FileManager.default.createDirectory(at: episodes, withIntermediateDirectories: true)
    let file = episodes.appendingPathComponent(name)
    try Data(text.utf8).write(to: file)
    let backupRoot = root.appendingPathComponent(".personaje/backups/2026-01-01T00-00-00Z", isDirectory: true)
    return (root, file, backupRoot)
  }

  /// The default file system, except that a write of exactly `corrupting`
  /// lands with its last byte flipped. Other writes (the restore) are real.
  private struct CorruptingFileSystem: SceneNumberFileSystem {
    let corrupting: Data
    let real = DefaultSceneNumberFileSystem()

    func contents(of url: URL) throws -> Data { try real.contents(of: url) }
    func itemExists(at url: URL) -> Bool { real.itemExists(at: url) }
    func createDirectory(at url: URL) throws { try real.createDirectory(at: url) }
    func copyItem(at source: URL, to destination: URL) throws {
      try real.copyItem(at: source, to: destination)
    }
    func writeAtomically(_ data: Data, to url: URL) throws {
      guard data == corrupting, !data.isEmpty else {
        try real.writeAtomically(data, to: url)
        return
      }
      var damaged = data
      damaged[damaged.index(before: damaged.endIndex)] ^= 0xFF
      try real.writeAtomically(damaged, to: url)
    }
  }

  // MARK: - SN-4

  @Test("The backup is at the project-relative path and equals the original byte for byte")
  func backupEqualsOriginal() throws {
    let (root, file, backupRoot) = try project(unnumbered)
    let original = try Data(contentsOf: file)
    let plan = try SceneNumberWriter.plan(for: file)

    let result = try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: root)

    let expected = backupRoot.appendingPathComponent("episodes/e1.fountain")
    #expect(result.backup?.standardizedFileURL.path == expected.standardizedFileURL.path)
    let backupData = try Data(contentsOf: expected)
    #expect(backupData == original)
    #expect(backupData == plan.originalData)
  }

  @Test("Without a project root the backup is backupRoot/<file name>")
  func backupWithoutProjectRoot() throws {
    let (_, file, backupRoot) = try project(unnumbered)
    let plan = try SceneNumberWriter.plan(for: file)

    let result = try SceneNumberWriter.write(plan, backupRoot: backupRoot)

    let expected = backupRoot.appendingPathComponent("e1.fountain")
    #expect(result.backup?.standardizedFileURL.path == expected.standardizedFileURL.path)
    #expect(try Data(contentsOf: expected) == plan.originalData)
  }

  // MARK: - Write and SN-6

  @Test("The written file equals the plan's new bytes and text")
  func writtenFileEqualsPlan() throws {
    let (root, file, backupRoot) = try project(unnumbered)
    let plan = try SceneNumberWriter.plan(for: file)
    #expect(plan.changes.count == 2)

    let result = try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: root)

    #expect(result.outcome == .written)
    #expect(result.wroteFile)
    #expect(result.changes == plan.changes)
    let written = try Data(contentsOf: file)
    #expect(written == plan.newData)
    #expect(String(decoding: written, as: UTF8.self) == plan.newText)
    #expect(plan.newText.contains("INT. WORKSHOP - DAY #1#"))
    #expect(plan.newText.contains("EXT. YARD - NIGHT #2#"))
  }

  @Test("A plan with no changes, or a skipped plan, writes nothing and makes no backup")
  func emptyPlanMakesNoBackup() throws {
    let (root, file, backupRoot) = try project(numbered)
    let original = try Data(contentsOf: file)
    let plan = try SceneNumberWriter.plan(for: file)
    #expect(plan.status == .planned)
    #expect(!plan.hasChanges)

    let result = try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: root)

    #expect(result.outcome == .unchanged)
    #expect(result.backup == nil)
    #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
    #expect(try Data(contentsOf: file) == original)

    let notes = root.appendingPathComponent("notes.txt")
    try Data("INT. NOT A SCREENPLAY - DAY\n".utf8).write(to: notes)
    let skipped = try SceneNumberWriter.plan(for: notes)
    let skippedResult = try SceneNumberWriter.write(skipped, backupRoot: backupRoot, relativeTo: root)

    #expect(skippedResult.outcome == .skipped(reason: "not a .fountain file"))
    #expect(skippedResult.backup == nil)
    #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
  }

  @Test("A corrupted write is caught by the read-back and the original restored byte for byte")
  func corruptedWriteRestoresBackup() throws {
    let (root, file, backupRoot) = try project(unnumbered)
    let original = try Data(contentsOf: file)
    let plan = try SceneNumberWriter.plan(for: file)
    let fileSystem = CorruptingFileSystem(corrupting: plan.newData)

    #expect(throws: SceneNumberWriteError.verifyFailed(file: file)) {
      try SceneNumberWriter.write(
        plan, backupRoot: backupRoot, relativeTo: root, fileSystem: fileSystem)
    }

    let after = try Data(contentsOf: file)
    #expect(after == original)
    let backup = backupRoot.appendingPathComponent("episodes/e1.fountain")
    #expect(try Data(contentsOf: backup) == original)
  }

  // MARK: - Guards

  @Test("A file changed on disk since it was planned is not overwritten")
  func changedFileIsNotOverwritten() throws {
    let (root, file, backupRoot) = try project(unnumbered)
    let plan = try SceneNumberWriter.plan(for: file)
    let edited = Data((unnumbered + "Someone else's edit.\n").utf8)
    try edited.write(to: file)

    #expect(throws: SceneNumberWriteError.changedOnDisk(file: file)) {
      try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: root)
    }

    #expect(try Data(contentsOf: file) == edited)
    #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
  }

  @Test("A file outside the project root is refused before any backup")
  func fileOutsideProjectIsRefused() throws {
    let (_, file, backupRoot) = try project(unnumbered)
    let otherRoot = try Synthetic.makeDirectory()
    let plan = try SceneNumberWriter.plan(for: file)

    #expect(throws: SceneNumberWriteError.outsideProject(file: file, projectRoot: otherRoot)) {
      try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: otherRoot)
    }

    #expect(try Data(contentsOf: file) == plan.originalData)
    #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
  }

  @Test("An existing backup is never overwritten, and the file is left alone")
  func existingBackupIsNotOverwritten() throws {
    let (root, file, backupRoot) = try project(unnumbered)
    let plan = try SceneNumberWriter.plan(for: file)
    let backup = backupRoot.appendingPathComponent("episodes/e1.fountain")
    try FileManager.default.createDirectory(
      at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
    let earlier = Data("an earlier backup\n".utf8)
    try earlier.write(to: backup)

    #expect(throws: SceneNumberWriteError.self) {
      try SceneNumberWriter.write(plan, backupRoot: backupRoot, relativeTo: root)
    }

    #expect(try Data(contentsOf: backup) == earlier)
    #expect(try Data(contentsOf: file) == plan.originalData)
  }
}
