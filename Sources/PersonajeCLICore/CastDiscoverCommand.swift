import ArgumentParser
import Foundation
import SwiftPersonaje

/// `personaje cast-discover`: reports what discovery would do to `CAST.md` from
/// the screenplays `PROJECT.md` lists (REQUIREMENTS §2, §7.1). Replaces
/// `echada generate cast` (SwiftEchada EC-P11).
///
/// Report-only since 2026-11-07: the Personaje app is the only builder of
/// `CAST.md` (Personaje APP-UI UD21; SwiftReparto RQ-27). The command always
/// runs discovery as a dry run and never writes `CAST.md`; the app calls the
/// same library writer to build it.
public struct CastDiscoverCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "cast-discover",
    abstract: "Report the characters who speak in the project's screenplays, against CAST.md.",
    discussion: """
      Reads every screenplay under PROJECT.md's episodesDir (default: episodes) \
      matching its filePattern (default: *.fountain; a comma-separated string \
      names episode files one by one), and reports what discovery would do to \
      CAST.md beside PROJECT.md: the speaking characters it would add, and each \
      member's line count (character cues across every episode), old and new.

      Report only: this command never writes CAST.md. The Personaje app is the \
      only builder of CAST.md; it runs the same discovery. --dry-run is \
      accepted and changes nothing.

      Discovery only ever adds members: nothing already in CAST.md is \
      reordered or removed, and two different names are never joined (review \
      them from this report). Only lineCount, which is derived, is refreshed.
      """
  )

  @OptionGroup public var options: ProjectOptions

  /// Kept so existing scripts still parse. The command is always a dry run.
  @Flag(name: .long, help: "Accepted for compatibility; cast-discover never writes CAST.md.")
  public var dryRun: Bool = false

  public init() {}

  public func run() async throws {
    let output = try await execute()
    print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
  }

  /// Runs the command and returns what it prints. Separate from ``run()`` so
  /// tests can drive it in-process.
  public func execute(
    workingDirectory: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) async throws -> String {
    let project: PersonajeProject
    do {
      project = try PersonajeProject.locate(
        project: options.project, workingDirectory: workingDirectory)
    } catch let error as PersonajeProjectError {
      throw ValidationError(error.description)
    }

    // A legacy `cast:` roster is `cast-import`'s to move; a report against an
    // empty roster would list every member of it as new.
    if !FileManager.default.fileExists(atPath: project.castFile.path),
      project.hasLegacyCastBlock
    {
      throw ValidationError(
        "PROJECT.md still has a legacy `cast:` block and there is no CAST.md. "
          + "Import it first (`reparto import`), then run cast-discover.")
    }

    let screenplays = project.screenplayFiles()
    guard !screenplays.isEmpty else {
      throw ValidationError(
        "No screenplays under \(project.episodesDirName)/ match "
          + "\(project.screenplayPatterns.joined(separator: ", ")). "
          + "Set episodesDir and filePattern in PROJECT.md.")
    }

    let report: CastDiscovery.Report
    do {
      // Always a dry run, whatever the flag says (§2: report-only).
      report = try await CastDiscovery.discover(
        screenplays: screenplays, castFile: project.castFile, dryRun: true)
    } catch let error as CastDiscoveryError {
      throw ValidationError(error.description)
    }

    if options.json {
      return try Self.json(report)
    }
    return Self.text(report, project: project)
  }

  static func json(_ report: CastDiscovery.Report) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
  }

  static func text(_ report: CastDiscovery.Report, project: PersonajeProject) -> String {
    var lines: [String] = []
    let relative = { (path: String) -> String in
      let base = project.directory.path + "/"
      return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
    lines.append("Project: \(project.directory.path)")
    lines.append("Screenplays: \(report.screenplays.count)")
    for path in report.screenplays {
      lines.append("  \(relative(path))")
    }
    lines.append("Speaking characters: \(report.discovered.count)")

    for rejection in report.rejected {
      lines.append("Skipped \"\(rejection.name)\": \(rejection.reason)")
    }

    let castName = relative(report.castFile)
    let countByName = Dictionary(
      report.lineCounts.map { ($0.character, $0.lineCount) },
      uniquingKeysWith: { first, _ in first })
    let updated = report.updatedLineCounts

    if report.added.isEmpty && updated.isEmpty {
      lines.append(
        report.castFileWasMissing
          ? "Nothing to add; \(castName) does not exist."
          : "Nothing to change; \(castName) is current (\(report.totalCount) members).")
    }

    if !report.added.isEmpty {
      lines.append("Would add \(report.added.count) to \(castName):")
      for name in report.added {
        let count = countByName[name].map { " (\($0) \($0 == 1 ? "line" : "lines"))" } ?? ""
        lines.append("  + \(name)\(count)")
      }
    }

    if !updated.isEmpty {
      lines.append("Would update \(updated.count) line \(updated.count == 1 ? "count" : "counts"):")
      for entry in updated {
        let old = entry.previous.map(String.init) ?? "none"
        lines.append("  ~ \(entry.character): \(old) -> \(entry.lineCount)")
      }
    }

    lines.append("Report only: \(castName) not written. The Personaje app builds it.")
    return lines.joined(separator: "\n") + "\n"
  }
}
