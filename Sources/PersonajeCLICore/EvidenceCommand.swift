import ArgumentParser
import Foundation
import SwiftPersonaje
import SwiftReparto

/// `personaje evidence <CHARACTER>`: everything the project's screenplays say
/// about one CAST.md member, each item with its source (REQUIREMENTS VE-9).
///
/// Read only. The character is matched against CAST.md members' `character`
/// names ignoring case and surrounding whitespace; the output always uses the
/// name as CAST.md spells it.
public struct EvidenceCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "evidence",
    abstract: "Show the screenplay evidence for one CAST.md member.",
    discussion: """
      Prints the member's tier (the CAST.md `role` when set, otherwise computed \
      from dialogue and scene share), the accent and where it came from, and \
      the evidence items grouped by kind (dialogue, introduction, group \
      statement), each quoted with `<episode> sc <n>`.

      CHARACTER must be a CAST.md member; the match ignores case. An unknown \
      name prints `unknown character: <NAME>` to stderr and exits non-zero.

      --json prints only JSON on stdout: {"member", "role", "tier", \
      "evidence"}, where "evidence" is the CharacterEvidence Codable form \
      (member, items, windows, accent). "role" is omitted when CAST.md has \
      none. Context windows are emitted whole; the whole output is held \
      under 12,000 characters for the fixture members (tested).
      """
  )

  @Argument(help: "The CAST.md member's name (case-insensitive).")
  public var character: String

  @OptionGroup public var options: ProjectOptions

  public init() {}

  public func run() async throws {
    let result = try await execute()
    if !result.output.isEmpty {
      print(result.output, terminator: result.output.hasSuffix("\n") ? "" : "\n")
    }
    if !result.errorOutput.isEmpty {
      FileHandle.standardError.write(Data((result.errorOutput + "\n").utf8))
    }
    if result.failed { throw ExitCode.failure }
  }

  /// What a run printed to stdout and stderr, and whether it failed.
  public struct RunResult: Sendable {
    public let output: String
    public let errorOutput: String
    public let failed: Bool
  }

  /// The JSON shape: the evidence plus the tier (not a stored property of
  /// ``CharacterEvidence``) and the CAST.md role it came from.
  struct Report: Codable, Equatable {
    var member: String
    var role: String?
    var tier: CharacterTier
    var evidence: CharacterEvidence
  }

  /// Runs the command and returns what it prints. Separate from ``run()`` so
  /// tests can drive it in-process.
  public func execute(
    workingDirectory: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) async throws -> RunResult {
    let project: PersonajeProject
    do {
      project = try PersonajeProject.locate(
        project: options.project, workingDirectory: workingDirectory)
    } catch let error as PersonajeProjectError {
      throw ValidationError(error.description)
    }

    guard FileManager.default.fileExists(atPath: project.castFile.path) else {
      throw ValidationError("No CAST.md in \(project.directory.path).")
    }
    let document = try CastMarkdownParser().parse(fileURL: project.castFile)
    let wanted = character.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let member = document.cast.first(where: {
        $0.character.caseInsensitiveCompare(wanted) == .orderedSame
      })
    else {
      return RunResult(output: "", errorOutput: "unknown character: \(character)", failed: true)
    }

    let screenplays = project.screenplayFiles()
    guard !screenplays.isEmpty else {
      throw ValidationError(
        "No screenplays under \(project.episodesDirName)/ match "
          + "\(project.screenplayPatterns.joined(separator: ", ")). "
          + "Set episodesDir and filePattern in PROJECT.md.")
    }

    let context = try ProjectContext(project: project)
    let corpus = try await EvidenceCorpus.load(screenplays: screenplays)
    let evidence = try await corpus.evidence(for: member.character, context: context)
    let tier = evidence.tier(in: corpus, castRole: member.role)
    let report = Report(
      member: member.character, role: member.role?.rawValue, tier: tier, evidence: evidence)

    let output = options.json ? try Self.json(report) : Self.text(report)
    return RunResult(output: output, errorOutput: "", failed: false)
  }

  // MARK: Output

  static func json(_ report: Report) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
  }

  static func text(_ report: Report) -> String {
    let evidence = report.evidence
    var lines = ["\(report.member)"]
    lines.append(
      "Tier: \(report.tier.rawValue)"
        + (report.role.map { " (CAST.md role: \($0))" } ?? " (computed)"))
    if let accent = evidence.accent {
      switch accent.source {
      case .project:
        lines.append("Accent: \(accent.accent) (from PROJECT.md setting.accent)")
      case .evidence(let item):
        lines.append("Accent: \(accent.accent) (from \(source(of: item)))")
      }
    } else {
      lines.append("Accent: none")
    }

    let sections: [(String, EvidenceItem.Kind)] = [
      ("Dialogue", .dialogue), ("Introductions", .introduction),
      ("Group statements", .groupStatement),
    ]
    for (title, kind) in sections {
      let items = evidence.items.filter { $0.kind == kind }
      lines.append("")
      lines.append("\(title) (\(items.count))")
      for item in items {
        var head = "  \(source(of: item)), line \(item.line)"
        if let cue = item.cue { head += ": \(cue)" }
        if let name = item.matchedName { head += ": \(name)" }
        lines.append(head)
        for textLine in item.text.split(separator: "\n", omittingEmptySubsequences: false) {
          lines.append("    \"\(textLine)\"")
        }
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// `<episode> sc <n>` (`sc -` before the first heading).
  static func source(of item: EvidenceItem) -> String {
    "\(item.episode) sc \(item.sceneNumber ?? "-")"
  }
}
