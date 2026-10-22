import ArgumentParser
import Foundation
import SwiftPersonaje

/// `personaje cast-discover`: builds or extends `CAST.md` from the screenplays
/// `PROJECT.md` lists (REQUIREMENTS §2, §7.1). Replaces `echada generate cast`
/// (SwiftEchada EC-P11).
public struct CastDiscoverCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "cast-discover",
    abstract: "Add the characters who speak in the project's screenplays to CAST.md.",
    discussion: """
      Reads every screenplay under PROJECT.md's episodesDir (default: episodes) \
      matching its filePattern (default: *.fountain; a comma-separated string \
      names episode files one by one), and adds each speaking character to \
      CAST.md beside PROJECT.md. Only the character name is written.

      Members are only ever added: nothing already in CAST.md is changed, \
      reordered or removed, and two different names are never joined (review \
      them after --dry-run). Running once over every episode, or once per \
      episode in any order, gives the same CAST.md.

      --dry-run prints the members it would add and writes nothing.
      """
  )

  @OptionGroup public var options: ProjectOptions

  @Flag(name: .long, help: "Print the members that would be added; write nothing.")
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

    // A legacy `cast:` roster is `cast-import`'s to move; discovering first
    // would create a CAST.md without it.
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
      report = try await CastDiscovery.discover(
        screenplays: screenplays, castFile: project.castFile, dryRun: dryRun)
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
    if report.added.isEmpty {
      lines.append("Nothing to add; \(castName) unchanged (\(report.totalCount) members).")
      return lines.joined(separator: "\n") + "\n"
    }

    lines.append(
      report.dryRun
        ? "Would add \(report.added.count) to \(castName):"
        : "Added \(report.added.count) to \(castName):")
    for name in report.added {
      lines.append("  + \(name)")
    }
    if report.dryRun {
      lines.append("Dry run: nothing written.")
    } else {
      lines.append(
        "\(report.castFileWasMissing ? "Created" : "Wrote") \(castName) (\(report.totalCount) members)."
      )
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
