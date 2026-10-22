import Foundation
import SwiftProyecto

/// A podcast or screenplay project: the directory holding `PROJECT.md`.
///
/// `PROJECT.md` is SwiftProyecto's file and is only ever read here (Q3).
/// `CAST.md` always sits beside it and belongs to SwiftReparto (SP-1).
public struct PersonajeProject: Sendable {

  /// The file name every project's settings live in.
  public static let projectFileName = "PROJECT.md"

  /// The file name of the cast roster, beside `PROJECT.md`.
  public static let castFileName = "CAST.md"

  /// The directory holding `PROJECT.md`.
  public let directory: URL

  /// The parsed `PROJECT.md` front matter.
  public let frontMatter: ProjectFrontMatter

  /// `<directory>/PROJECT.md`.
  public var projectFile: URL {
    directory.appendingPathComponent(Self.projectFileName, isDirectory: false)
  }

  /// `<directory>/CAST.md`. It may not exist yet.
  public var castFile: URL {
    directory.appendingPathComponent(Self.castFileName, isDirectory: false)
  }

  /// `episodesDir` as written in `PROJECT.md` (default `episodes`).
  public var episodesDirName: String { frontMatter.resolvedEpisodesDir }

  /// `true` when `PROJECT.md` still carries a legacy `cast:` roster, which
  /// `cast-import` (not discovery) moves into `CAST.md`.
  public var hasLegacyCastBlock: Bool { frontMatter.hasLegacyCastKey }

  /// The episodes directory from `episodesDir` (default `episodes`),
  /// relative to the project directory.
  public var episodesDirectory: URL {
    let dir = frontMatter.resolvedEpisodesDir
    if dir.hasPrefix("/") {
      return URL(fileURLWithPath: dir, isDirectory: true)
    }
    return directory.appendingPathComponent(dir, isDirectory: true)
  }

  /// The screenplay patterns from `filePattern` (default `*.fountain`).
  ///
  /// A pattern written as one comma-separated string
  /// (`"ep01.fountain, ep02.fountain"`) names those episode files one by one
  /// (REQUIREMENTS §7), so it is split on commas and trimmed. Empty pieces are
  /// dropped.
  public var screenplayPatterns: [String] {
    Self.splitPatterns(frontMatter.resolvedFilePatterns)
  }

  /// Opens the project in `directory`, which must hold `PROJECT.md`.
  ///
  /// - Throws: ``PersonajeProjectError/projectFileMissing(_:)`` when there is
  ///   no `PROJECT.md`, or SwiftProyecto's parse error.
  public init(directory: URL) throws {
    let dir = directory.standardizedFileURL
    let file = dir.appendingPathComponent(Self.projectFileName, isDirectory: false)
    guard FileManager.default.fileExists(atPath: file.path) else {
      throw PersonajeProjectError.projectFileMissing(dir.path)
    }
    let (frontMatter, _) = try ProjectMarkdownParser().parse(fileURL: file)
    self.directory = dir
    self.frontMatter = frontMatter
  }

  /// Finds the project for a command (SP-8).
  ///
  /// With an explicit `project` path, that directory is used (a path to a
  /// `PROJECT.md` file is accepted and means its directory). Without one, the
  /// nearest directory at or above `workingDirectory` holding `PROJECT.md`.
  ///
  /// - Throws: ``PersonajeProjectError/projectNotFound(_:)`` when no directory
  ///   at or above `workingDirectory` holds `PROJECT.md`.
  public static func locate(
    project: String?,
    workingDirectory: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) throws -> PersonajeProject {
    if let project {
      var url = URL(
        fileURLWithPath: (project as NSString).expandingTildeInPath,
        relativeTo: workingDirectory
      ).standardizedFileURL
      if url.lastPathComponent == projectFileName, !isDirectory(url) {
        url = url.deletingLastPathComponent()
      }
      return try PersonajeProject(directory: url)
    }

    var candidate = workingDirectory.standardizedFileURL
    while true {
      let file = candidate.appendingPathComponent(projectFileName, isDirectory: false)
      if FileManager.default.fileExists(atPath: file.path) {
        return try PersonajeProject(directory: candidate)
      }
      let parent = candidate.deletingLastPathComponent().standardizedFileURL
      if parent.path == candidate.path { break }
      candidate = parent
    }
    throw PersonajeProjectError.projectNotFound(workingDirectory.standardizedFileURL.path)
  }

  /// Every screenplay the project lists: files under ``episodesDirectory``
  /// (recursively, hidden files skipped) whose name, or path relative to the
  /// episodes directory, matches one of ``screenplayPatterns``. Sorted by
  /// relative path, so the order never depends on the file system.
  public func screenplayFiles() -> [URL] {
    let root = episodesDirectory.standardizedFileURL
    guard isDirectory(root),
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    let patterns = screenplayPatterns
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    var matches: [(relative: String, url: URL)] = []
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
      // A `.highland` or `.textbundle` screenplay is a package directory.
      let isBundle = ["highland", "textbundle"].contains(url.pathExtension.lowercased())
      if values?.isDirectory == true {
        if isBundle {
          enumerator.skipDescendants()
        } else {
          continue
        }
      } else if values?.isRegularFile != true {
        continue
      }
      let standardized = url.standardizedFileURL
      let relative =
        standardized.path.hasPrefix(rootPath)
        ? String(standardized.path.dropFirst(rootPath.count))
        : standardized.lastPathComponent
      if Self.matches(
        name: standardized.lastPathComponent, relativePath: relative, patterns: patterns)
      {
        matches.append((relative, standardized))
      }
    }
    return matches.sorted { $0.relative < $1.relative }.map(\.url)
  }

  // MARK: - Helpers

  static func splitPatterns(_ patterns: [String]) -> [String] {
    patterns.flatMap { $0.split(separator: ",") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  static func matches(name: String, relativePath: String, patterns: [String]) -> Bool {
    patterns.contains { pattern in
      pattern == name || pattern == relativePath || fnmatch(pattern, name, 0) == 0
        || fnmatch(pattern, relativePath, 0) == 0
    }
  }
}

private func isDirectory(_ url: URL) -> Bool {
  var isDir: ObjCBool = false
  return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
}

/// Why a project could not be opened.
public enum PersonajeProjectError: Error, Equatable, Sendable, CustomStringConvertible {
  /// No directory at or above this path holds `PROJECT.md`.
  case projectNotFound(String)
  /// This directory has no `PROJECT.md`.
  case projectFileMissing(String)

  public var description: String {
    switch self {
    case .projectNotFound(let path):
      return
        "No PROJECT.md found in \(path) or any directory above it. Pass --project <dir>."
    case .projectFileMissing(let path):
      return "No PROJECT.md in \(path)."
    }
  }
}
