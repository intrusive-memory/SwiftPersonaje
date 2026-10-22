import ArgumentParser

/// The current `personaje` version.
public enum PersonajeVersion {
  public static let current = "0.1.0-dev"
}

/// `personaje`: one command per step from a name in the screenplay to a
/// finished `.dossier` character bundle (REQUIREMENTS §2, §3).
public struct PersonajeCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "personaje",
    abstract: "Build .dossier character bundles, one step per command.",
    discussion: """
      Every command takes --project <dir> (default: the nearest directory at or \
      above the working directory holding PROJECT.md) and --json.
      """,
    version: PersonajeVersion.current,
    subcommands: [
      CastDiscoverCommand.self
    ]
  )

  public init() {}
}

/// Options every command shares (SP-8).
public struct ProjectOptions: ParsableArguments {
  @Option(
    name: .long,
    help: ArgumentHelp(
      "The project directory. Default: the nearest directory at or above the working directory holding PROJECT.md.",
      valueName: "dir"))
  public var project: String?

  @Flag(name: .long, help: "Print the result as JSON.")
  public var json: Bool = false

  public init() {}
}
