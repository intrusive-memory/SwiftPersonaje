import ArgumentParser
import Foundation
import SwiftPersonaje

/// `personaje number-scenes`: appends ` #n#` to every unnumbered slugline in
/// the project's screenplays (REQUIREMENTS SN-7), through
/// ``SceneNumberWriter``: each changed file is backed up first, written
/// atomically and read back.
///
/// Write only: the command never commits (a person reviews the diff).
public struct NumberScenesCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "number-scenes",
    abstract: "Number every unnumbered scene heading in the project's screenplays.",
    discussion: """
      Appends ` #n#` to each slugline that has no scene number, in every \
      screenplay PROJECT.md lists. Numbers continue from the last numbered \
      heading in the file; every other byte of the file is kept as read.

      Each file that changes is first copied to \
      <project>/.personaje/backups/<UTC timestamp, e.g. 20261118T120000Z>/\
      <path relative to the project>. One timestamp per run; nothing is \
      pruned. The first time it has something to number, it appends \
      `.personaje/` to the project's .gitignore (creating it if needed).

      --dry-run prints, per file, how many headings would be numbered and the \
      new heading lines. It writes nothing: no file, no backup, no .gitignore.

      If a file fails (it changed on disk, the backup failed, the read-back \
      didn't match), that file is left as it was (restored from its backup if \
      the write had started), the remaining files are still processed, and \
      the command exits non-zero. It never commits.
      """
  )

  @OptionGroup public var options: ProjectOptions

  @Flag(name: .long, help: "Report what would be numbered; write nothing.")
  public var dryRun: Bool = false

  public init() {}

  public func run() async throws {
    let result = try execute()
    print(result.output, terminator: result.output.hasSuffix("\n") ? "" : "\n")
    if result.failureCount > 0 {
      throw ExitCode.failure
    }
  }

  /// What a run printed, and how many files failed.
  public struct RunResult: Sendable {
    public let output: String
    public let failureCount: Int
  }

  /// One heading a file got, or would get.
  struct HeadingReport: Codable, Equatable {
    var line: Int
    var number: String
    var text: String
  }

  /// One file's outcome. `status`: `numbered`, `would-number`, `unchanged`
  /// (every heading already numbered), `skipped` or `failed`.
  struct FileReport: Codable, Equatable {
    var file: String
    var status: String
    var count: Int
    var headings: [HeadingReport]
    var backup: String?
    var reason: String?
  }

  struct Report: Codable, Equatable {
    var project: String
    var dryRun: Bool
    /// The backup directory of this run; `nil` when nothing was (or would be) written.
    var backupDirectory: String?
    /// `added` or `would-add` when `.gitignore` needed `.personaje/`; otherwise `nil`.
    var gitignore: String?
    var files: [FileReport]
    var failed: Int
  }

  /// Runs the command and returns what it prints. Separate from ``run()`` so
  /// tests can drive it in-process. `now` names the backup directory.
  public func execute(
    workingDirectory: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
    now: Date = Date()
  ) throws -> RunResult {
    let project: PersonajeProject
    do {
      project = try PersonajeProject.locate(
        project: options.project, workingDirectory: workingDirectory)
    } catch let error as PersonajeProjectError {
      throw ValidationError(error.description)
    }

    let screenplays = project.screenplayFiles()
    guard !screenplays.isEmpty else {
      throw ValidationError(
        "No screenplays under \(project.episodesDirName)/ match "
          + "\(project.screenplayPatterns.joined(separator: ", ")). "
          + "Set episodesDir and filePattern in PROJECT.md.")
    }

    let root = project.directory
    let relative = { (url: URL) -> String in
      let base = root.path + "/"
      return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    // Plan everything first: a dry run and a real run see the same plans.
    var plans: [(file: URL, plan: SceneNumberPlan?, error: String?)] = []
    for file in screenplays {
      do {
        plans.append((file, try SceneNumberWriter.plan(for: file), nil))
      } catch {
        plans.append((file, nil, Self.describe(error)))
      }
    }
    let needsNumbering = plans.contains { $0.plan?.hasChanges == true }

    var report = Report(
      project: root.path, dryRun: dryRun, backupDirectory: nil, gitignore: nil, files: [],
      failed: 0)

    let backupRoot = root.appendingPathComponent(".personaje", isDirectory: true)
      .appendingPathComponent("backups", isDirectory: true)
      .appendingPathComponent(Self.timestamp(now), isDirectory: true)

    if needsNumbering {
      report.backupDirectory = backupRoot.path
      if !Self.gitignoreCoversPersonaje(in: root) {
        if dryRun {
          report.gitignore = "would-add"
        } else {
          do {
            try Self.appendPersonajeToGitignore(in: root)
          } catch {
            throw ValidationError(
              "Can't update \(root.path)/.gitignore: \(error.localizedDescription). Nothing was written."
            )
          }
          report.gitignore = "added"
        }
      }
    }

    for entry in plans {
      let name = relative(entry.file)
      guard let plan = entry.plan else {
        report.files.append(
          FileReport(
            file: name, status: "failed", count: 0, headings: [], backup: nil,
            reason: entry.error))
        report.failed += 1
        continue
      }
      let headings = plan.changes.map {
        HeadingReport(line: $0.lineIndex + 1, number: $0.number, text: $0.newLine)
      }
      if let reason = plan.skipReason {
        report.files.append(
          FileReport(
            file: name, status: "skipped", count: 0, headings: [], backup: nil, reason: reason))
        continue
      }
      guard plan.hasChanges else {
        report.files.append(
          FileReport(
            file: name, status: "unchanged", count: 0, headings: [], backup: nil, reason: nil))
        continue
      }
      if dryRun {
        report.files.append(
          FileReport(
            file: name, status: "would-number", count: headings.count, headings: headings,
            backup: nil, reason: nil))
        continue
      }
      do {
        let result = try SceneNumberWriter.write(
          plan, backupRoot: backupRoot, relativeTo: root)
        report.files.append(
          FileReport(
            file: name, status: result.wroteFile ? "numbered" : "unchanged",
            count: result.changes.count, headings: headings,
            backup: result.backup?.path, reason: nil))
      } catch {
        report.files.append(
          FileReport(
            file: name, status: "failed", count: 0, headings: [], backup: nil,
            reason: Self.describe(error)))
        report.failed += 1
      }
    }

    let output = options.json ? try Self.json(report) : Self.text(report)
    return RunResult(output: output, failureCount: report.failed)
  }

  // MARK: Output

  static func json(_ report: Report) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
  }

  static func text(_ report: Report) -> String {
    var lines = ["Project: \(report.project)"]
    for file in report.files {
      let headings = "\(file.count) \(file.count == 1 ? "heading" : "headings")"
      switch file.status {
      case "would-number":
        lines.append("\(file.file): would number \(headings)")
      case "numbered":
        lines.append("\(file.file): numbered \(headings)")
      case "unchanged":
        lines.append("\(file.file): already numbered")
      case "skipped":
        lines.append("\(file.file): skipped: \(file.reason ?? "")")
      default:
        lines.append("\(file.file): FAILED: \(file.reason ?? "")")
      }
      if file.status == "would-number" || file.status == "numbered" {
        for heading in file.headings {
          lines.append("  + \(heading.text)")
        }
      }
    }
    let total = report.files.reduce(0) { $0 + $1.count }
    if let gitignore = report.gitignore {
      lines.append(
        gitignore == "added"
          ? "Added .personaje/ to .gitignore."
          : "Would add .personaje/ to .gitignore.")
    }
    if report.dryRun {
      lines.append(
        total == 0
          ? "Nothing to number."
          : "Dry run: \(total) \(total == 1 ? "heading" : "headings") would be numbered; nothing written."
      )
    } else if total == 0 && report.failed == 0 {
      lines.append("Nothing to number.")
    } else if total > 0 {
      if let backup = report.backupDirectory {
        lines.append("Numbered \(total) \(total == 1 ? "heading" : "headings"). Backups: \(backup)")
      }
    }
    if report.failed > 0 {
      lines.append(
        "\(report.failed) \(report.failed == 1 ? "file" : "files") failed; each was left as it was."
      )
    }
    return lines.joined(separator: "\n") + "\n"
  }

  // MARK: Helpers

  /// UTC, filesystem-safe ISO 8601 basic form without colons: `20261118T120000Z`.
  static func timestamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d%02d%02dT%02d%02d%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
      c.minute ?? 0, c.second ?? 0)
  }

  static func describe(_ error: Error) -> String {
    if let error = error as? CustomStringConvertible { return error.description }
    return error.localizedDescription
  }

  private static let ignoredForms: Set<String> = [
    ".personaje", ".personaje/", "/.personaje", "/.personaje/", ".personaje/*", "/.personaje/*",
  ]

  static func gitignoreCoversPersonaje(in project: URL) -> Bool {
    let url = project.appendingPathComponent(".gitignore")
    guard let data = try? Data(contentsOf: url) else { return false }
    let text = String(decoding: data, as: UTF8.self)
    return text.split(whereSeparator: \.isNewline).contains {
      ignoredForms.contains($0.trimmingCharacters(in: .whitespaces))
    }
  }

  static func appendPersonajeToGitignore(in project: URL) throws {
    let url = project.appendingPathComponent(".gitignore")
    var text = ""
    if let data = try? Data(contentsOf: url) {
      text = String(decoding: data, as: UTF8.self)
    }
    if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
    text += ".personaje/\n"
    try Data(text.utf8).write(to: url, options: .atomic)
  }
}
