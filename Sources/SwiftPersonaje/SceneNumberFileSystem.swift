import Foundation

/// The file operations ``SceneNumberWriter/write(_:backupRoot:relativeTo:)``
/// performs, behind a seam so a test can inject a failing or corrupting
/// write. The default is ``DefaultSceneNumberFileSystem``.
protocol SceneNumberFileSystem: Sendable {
  /// The bytes of the file at `url`.
  func contents(of url: URL) throws -> Data
  /// `true` when anything (file or directory) exists at `url`.
  func itemExists(at url: URL) -> Bool
  /// Creates the directory at `url` and any missing parents.
  func createDirectory(at url: URL) throws
  /// Copies the file at `source` to `destination`, which must not exist.
  func copyItem(at source: URL, to destination: URL) throws
  /// Replaces the file at `url` with `data` in one atomic step: a reader sees
  /// either the old bytes or the new ones, never a mix.
  func writeAtomically(_ data: Data, to url: URL) throws
}

/// ``SceneNumberFileSystem`` on `FileManager` and `Data`.
struct DefaultSceneNumberFileSystem: SceneNumberFileSystem {

  func contents(of url: URL) throws -> Data {
    try Data(contentsOf: url)
  }

  func itemExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func copyItem(at source: URL, to destination: URL) throws {
    try FileManager.default.copyItem(at: source, to: destination)
  }

  /// `Data.write(to:options: .atomic)` writes a temporary file and renames
  /// it over `url`. The rename gives the file default permissions, so the
  /// original POSIX permissions are put back afterwards.
  func writeAtomically(_ data: Data, to url: URL) throws {
    let manager = FileManager.default
    let permissions = (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions]
    try data.write(to: url, options: .atomic)
    if let permissions {
      try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
  }
}
