import Foundation
import SwiftCompartido
import SwiftData
import SwiftReparto

/// The discovery writer (REQUIREMENTS §7.1, RP-P9..RP-P14): builds or extends
/// `CAST.md` from the characters who speak in a project's screenplays.
///
/// It reads screenplays through SwiftCompartido's store-wide character query
/// (`DocumentModelActor.extractAllCharacters()`, CP-P2), names each character
/// with SwiftReparto's `CastMember.canonicalName(_:)`, merges into the current
/// roster with `[CastMember].merging(_:)`, and writes with
/// `CastMarkdownParser.write`. No `CAST.md` byte is produced anywhere else
/// (SP-1).
///
/// What it promises:
///
/// - **Only `character` is set** on a new member. Counts are never written
///   (RP-P13); `role` and `manifest` come later from `personaje new`.
/// - **Additive** (RP-P10): members are added, missing fields are filled by
///   `merging(_:)`, and nothing a person wrote is changed, reordered or
///   removed.
/// - **Exact names** (RP-P14): two different names are two members, even when
///   they are one person. Joining them is a review step.
/// - **Order-independent** (RP-P11): discovering every episode at once, or one
///   episode per run in any order, gives a byte-identical `CAST.md`. See
///   ``merge(_:into:)`` for the ordering rule.
public enum CastDiscovery {

  // MARK: - Results

  /// A character name `canonicalName(_:)` refused (for example a cue
  /// containing `/`). It is reported and left out, never rewritten.
  public struct Rejection: Sendable, Equatable, Codable {
    /// The name as the screenplay store reported it.
    public let name: String
    /// Why `canonicalName(_:)` refused it.
    public let reason: String

    public init(name: String, reason: String) {
      self.name = name
      self.reason = reason
    }
  }

  /// Members discovered in a character collection, before any merge.
  public struct Discovered: Sendable, Equatable {
    /// One member per distinct canonical name, `character` only, sorted by
    /// name.
    public let members: [CastMember]
    /// Names that could not be canonicalized, sorted by name.
    public let rejected: [Rejection]

    public init(members: [CastMember], rejected: [Rejection]) {
      self.members = members
      self.rejected = rejected
    }
  }

  /// What a discovery run found and did.
  public struct Report: Sendable, Equatable, Codable {
    /// The `CAST.md` that was (or, under dry run, would be) written.
    public let castFile: String
    /// The screenplays read, in the order they were loaded. Empty when the
    /// run was given a character collection directly.
    public let screenplays: [String]
    /// Every canonical name discovered, sorted.
    public let discovered: [String]
    /// The names added to the roster, in roster order.
    public let added: [String]
    /// Names `canonicalName(_:)` refused.
    public let rejected: [Rejection]
    /// Members in `CAST.md` before the run (0 when it did not exist).
    public let existingCount: Int
    /// Members after the run.
    public let totalCount: Int
    /// `true` when `CAST.md` did not exist before the run.
    public let castFileWasMissing: Bool
    /// `true` when this run wrote `CAST.md`. Never `true` under dry run, and
    /// `false` when there was nothing to add.
    public let wrote: Bool
    /// `true` when the run was a dry run.
    public let dryRun: Bool
  }

  // MARK: - Reading screenplays

  /// Loads `screenplays` into a fresh in-memory SwiftCompartido store and
  /// returns its store-wide character collection (CP-P2).
  ///
  /// Each file is parsed by extension (`.fountain`, `.fdx`, `.highland`,
  /// `.md`, …) by SwiftCompartido. Glosa annotation is skipped; discovery
  /// needs only speakers.
  ///
  /// - Throws: ``CastDiscoveryError/unreadableScreenplay(path:reason:)`` for
  ///   the first file that fails to parse. Nothing is written on failure.
  public static func characters(inScreenplays screenplays: [URL]) async throws
    -> CharacterCollectionResult
  {
    let container = try makeContainer()
    let actor = DocumentModelActor(modelContainer: container)
    for url in screenplays {
      do {
        _ = try await actor.parseAndSaveDocument(from: url, parseGlosa: false)
      } catch {
        throw CastDiscoveryError.unreadableScreenplay(
          path: url.path, reason: String(describing: error))
      }
    }
    return try await actor.extractAllCharacters()
  }

  /// An in-memory container holding every SwiftCompartido model the parser
  /// writes.
  static func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      GuionDocumentModel.self,
      GuionElementModel.self,
      TypedDataStorage.self,
      TitlePageEntryModel.self,
      CustomPageModel.self,
      CharacterVoiceMapping.self,
      CustomOutlineElement.self,
    ])
    return try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }

  // MARK: - Mapping (RP-P9, RP-P13)

  /// Turns a character collection into members (RP-P9).
  ///
  /// Each name goes through `CastMember.canonicalName(_:)`. Names that
  /// canonicalize to the same string become one member. Only `character` is
  /// set: line, word and scene counts stay in SwiftCompartido (RP-P13).
  /// `characters` is a dictionary, so the result is sorted (RP-P11).
  public static func discoveredMembers(from collection: CharacterCollectionResult) -> Discovered {
    var names = Set<String>()
    var rejected: [Rejection] = []
    for rawName in collection.characters.keys {
      do {
        names.insert(try CastMember.canonicalName(rawName))
      } catch {
        rejected.append(Rejection(name: rawName, reason: error.localizedDescription))
      }
    }
    return Discovered(
      members: names.sorted().map { CastMember(character: $0) },
      rejected: rejected.sorted { $0.name < $1.name }
    )
  }

  // MARK: - Merging (RP-P10, RP-P11, RP-P14)

  /// Merges `discovered` into `roster` and places the new members.
  ///
  /// Matching, gap-filling and de-duplication are `[CastMember].merging(_:)`'s,
  /// unchanged (RP-P10). Members already in `roster` keep their position and
  /// every field. No name is ever matched to a different name (RP-P14).
  ///
  /// `merging(_:)` appends new members at the end, which would make the
  /// result depend on the order episodes were discovered in. So each new
  /// member is instead inserted before the first member whose name sorts
  /// after it (comparing canonical names; a name that can't be canonicalized
  /// compares as written), or at the end when none does. A roster built by
  /// this rule is the same whatever order the names arrive in, which is what
  /// RP-P11 needs; a sorted roster stays sorted, and a hand-ordered one keeps
  /// its order with new names slotted in.
  ///
  /// - Returns: The merged roster and the names added, in roster order.
  public static func merge(_ discovered: [CastMember], into roster: [CastMember]) -> (
    cast: [CastMember], added: [String]
  ) {
    let merged = roster.merging(discovered)
    var result = Array(merged.prefix(roster.count))
    let newMembers = merged.dropFirst(roster.count).sorted {
      sortKey($0.character) < sortKey($1.character)
    }
    for member in newMembers {
      let key = sortKey(member.character)
      if let index = result.firstIndex(where: { sortKey($0.character) > key }) {
        result.insert(member, at: index)
      } else {
        result.append(member)
      }
    }
    let addedNames = Set(newMembers.map(\.character))
    return (result, result.map(\.character).filter { addedNames.contains($0) })
  }

  static func sortKey(_ character: String) -> String {
    (try? CastMember.canonicalName(character)) ?? character
  }

  // MARK: - The writer

  /// Discovers the characters in `screenplays` and merges them into
  /// `castFile` (REQUIREMENTS §7.1).
  ///
  /// - Parameters:
  ///   - screenplays: The screenplay files to read. All are loaded into one
  ///     store, so this is the "every episode at once" path.
  ///   - castFile: The `CAST.md` to extend. Created when missing and there is
  ///     something to add.
  ///   - dryRun: When `true`, nothing is written (SP-7); the report says what
  ///     would be added.
  public static func discover(
    screenplays: [URL],
    castFile: URL,
    dryRun: Bool = false
  ) async throws -> Report {
    let collection = try await characters(inScreenplays: screenplays)
    return try discover(
      from: collection, castFile: castFile, dryRun: dryRun,
      screenplayPaths: screenplays.map(\.path))
  }

  /// Merges an already-built character collection into `castFile`. The
  /// Personaje app uses this with its own SwiftCompartido store.
  public static func discover(
    from collection: CharacterCollectionResult,
    castFile: URL,
    dryRun: Bool = false
  ) throws -> Report {
    try discover(from: collection, castFile: castFile, dryRun: dryRun, screenplayPaths: [])
  }

  private static func discover(
    from collection: CharacterCollectionResult,
    castFile: URL,
    dryRun: Bool,
    screenplayPaths: [String]
  ) throws -> Report {
    let found = discoveredMembers(from: collection)
    let parser = CastMarkdownParser()

    let fileExists = FileManager.default.fileExists(atPath: castFile.path)
    var document = fileExists ? try parser.parse(fileURL: castFile) : CastDocument()
    let existingCount = document.cast.count

    let (cast, added) = merge(found.members, into: document.cast)

    // Write only when there is a member to add: a run that finds nothing new
    // leaves an existing CAST.md byte for byte as it was, and doesn't create
    // an empty one.
    let shouldWrite = !dryRun && !added.isEmpty
    if shouldWrite {
      document.cast = cast
      try parser.write(document: document, to: castFile)
    }

    return Report(
      castFile: castFile.path,
      screenplays: screenplayPaths,
      discovered: found.members.map(\.character),
      added: added,
      rejected: found.rejected,
      existingCount: existingCount,
      totalCount: cast.count,
      castFileWasMissing: !fileExists,
      wrote: shouldWrite,
      dryRun: dryRun
    )
  }
}

/// Why discovery stopped.
public enum CastDiscoveryError: Error, Equatable, Sendable, CustomStringConvertible {
  /// SwiftCompartido could not parse this screenplay.
  case unreadableScreenplay(path: String, reason: String)

  public var description: String {
    switch self {
    case .unreadableScreenplay(let path, let reason):
      return "Could not read screenplay \(path): \(reason)"
    }
  }
}
