//
//  CommandWhitelist.swift
//  JARVIS
//
//  The allowlist that governs `run_terminal_command`. Nothing is ever
//  passed through a shell: the command is tokenized, the binary must
//  match an entry here by name and absolute path, and every argument is
//  checked against the entry rules. Commands that write, delete, install,
//  download, elevate privileges, or reinterpret shell syntax are refused
//  before the user is even asked to confirm.
//

import Foundation

/// Grouping used to present the whitelist in Settings.
enum CommandCategory: String, Sendable, CaseIterable, Identifiable {
    case fileInspection
    case systemInformation
    case textOutput
    case developer
    case finder

    var id: String { rawValue }

    /// Display name for the settings list.
    var displayName: String {
        switch self {
        case .fileInspection: return "Files and folders"
        case .systemInformation: return "System information"
        case .textOutput: return "Text output"
        case .developer: return "Developer tools"
        case .finder: return "Finder"
        }
    }
}

/// One category of whitelisted binaries, used to group the settings list.
struct CommandCategoryGroup: Identifiable, Sendable {
    /// Category these binaries belong to.
    let category: CommandCategory
    /// Binaries in the category.
    let binaries: [WhitelistedBinary]

    var id: String { category.rawValue }
}

/// A binary the assistant is permitted to run, with its argument rules.
struct WhitelistedBinary: Sendable, Identifiable {
    /// Command name as the model would write it.
    let name: String
    /// Absolute path that must match exactly.
    let path: String
    /// What the command is used for.
    let summary: String
    /// Grouping for the settings screen.
    let category: CommandCategory
    /// Flags that may appear as arguments. Empty means no flags at all.
    let allowedFlags: Set<String>
    /// Subcommands permitted as the first positional argument.
    let allowedSubcommands: Set<String>
    /// Whether positional path arguments are allowed.
    let allowsPathArguments: Bool
    /// Whether bare numbers may appear as arguments.
    let allowsNumericArguments: Bool
    /// Maximum number of positional arguments.
    let maxPositionalArguments: Int
    /// Allows unrestricted arguments. Only used for harmless text echo.
    let allowsAnyArguments: Bool

    var id: String { path }

    /// Command line shown in the settings list.
    var displayName: String { name }
}

extension WhitelistedBinary {
    /// Compact initializer for the catalog below.
    init(
        name: String,
        path: String,
        summary: String,
        category: CommandCategory,
        flags: Set<String> = [],
        subcommands: Set<String> = [],
        paths: Bool = false,
        numbers: Bool = false,
        maxPositional: Int = 0,
        anyArguments: Bool = false
    ) {
        self.name = name
        self.path = path
        self.summary = summary
        self.category = category
        self.allowedFlags = flags
        self.allowedSubcommands = subcommands
        self.allowsPathArguments = paths
        self.allowsNumericArguments = numbers
        self.maxPositionalArguments = maxPositional
        self.allowsAnyArguments = anyArguments
    }
}

/// A validated command ready to be confirmed and executed.
struct ValidatedCommand: Sendable {
    /// Absolute path of the binary.
    let executableURL: URL
    /// Arguments, already checked.
    let arguments: [String]
    /// Normalized command text shown in the confirmation dialog.
    let displayCommand: String
    /// Binary name for logging and summaries.
    let binaryName: String
    /// What the whitelist says the binary is for.
    let summary: String
}

/// Validates candidate commands against the allowlist.
enum CommandWhitelist {

    /// Largest command the assistant may propose.
    private static let maximumCommandLength = 512

    /// Root folders that path arguments may point into.
    ///
    /// Shared with the Finder automation so the two can never disagree.
    static var allowedPathRoots: [String] { PathGuard.allowedRoots }

    /// Characters refused outright so a command can never be re-read by a shell.
    private static let forbiddenCharacters: Set<Character> = [
        ";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "\t", "'"
    ]

    /// Every permitted binary.
    static let binaries: [WhitelistedBinary] = [
        WhitelistedBinary(
            name: "ls",
            path: "/bin/ls",
            summary: "List folder contents. Supports common flags such as -l, -a, -h, -t.",
            category: .fileInspection,
            flags: ["-l", "-a", "-h", "-t", "-r", "-S", "-la", "-lah", "-R", "-d", "-1", "-F", "-G"],
            paths: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "cat",
            path: "/bin/cat",
            summary: "Print a text file. Supports -n to number lines.",
            category: .fileInspection,
            flags: ["-n", "-b", "-s"],
            paths: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "head",
            path: "/usr/bin/head",
            summary: "Print the first lines of a file.",
            category: .fileInspection,
            flags: ["-n"],
            paths: true,
            numbers: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "tail",
            path: "/usr/bin/tail",
            summary: "Print the last lines of a file.",
            category: .fileInspection,
            flags: ["-n"],
            paths: true,
            numbers: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "wc",
            path: "/usr/bin/wc",
            summary: "Count lines, words, and characters in a file.",
            category: .fileInspection,
            flags: ["-l", "-w", "-c", "-m"],
            paths: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "du",
            path: "/usr/bin/du",
            summary: "Report folder sizes.",
            category: .fileInspection,
            flags: ["-h", "-s", "-d", "-c", "-k", "-m"],
            paths: true,
            numbers: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "find",
            path: "/usr/bin/find",
            summary: "Locate files under a folder by name. Only read only predicates are accepted.",
            category: .fileInspection,
            flags: ["-name", "-iname", "-maxdepth", "-type", "-newer", "-mtime"],
            paths: true,
            numbers: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "grep",
            path: "/usr/bin/grep",
            summary: "Search inside text files. Recursive and case insensitive flags are allowed.",
            category: .fileInspection,
            flags: ["-i", "-n", "-r", "-l", "-c", "-w", "-v"],
            paths: true,
            maxPositional: 2
        ),
        WhitelistedBinary(
            name: "mdfind",
            path: "/usr/bin/mdfind",
            summary: "Search the Spotlight index.",
            category: .fileInspection,
            flags: ["-onlyin", "-count", "-name"],
            paths: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "df",
            path: "/bin/df",
            summary: "Report free disk space.",
            category: .systemInformation,
            flags: ["-h", "-H", "-k", "-m", "-g", "-i"],
            paths: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "uptime",
            path: "/usr/bin/uptime",
            summary: "Show how long the machine has been running.",
            category: .systemInformation
        ),
        WhitelistedBinary(
            name: "whoami",
            path: "/usr/bin/whoami",
            summary: "Show the current user name.",
            category: .systemInformation
        ),
        WhitelistedBinary(
            name: "hostname",
            path: "/bin/hostname",
            summary: "Show the computer name.",
            category: .systemInformation
        ),
        WhitelistedBinary(
            name: "uname",
            path: "/usr/bin/uname",
            summary: "Show kernel and machine details.",
            category: .systemInformation,
            flags: ["-a", "-m", "-n", "-r", "-s", "-v", "-p"]
        ),
        WhitelistedBinary(
            name: "sw_vers",
            path: "/usr/bin/sw_vers",
            summary: "Show the macOS version.",
            category: .systemInformation,
            flags: ["-productVersion", "-buildVersion", "-productName", "-all"]
        ),
        WhitelistedBinary(
            name: "system_profiler",
            path: "/usr/sbin/system_profiler",
            summary: "Read hardware, software, storage, network, and display summaries.",
            category: .systemInformation,
            flags: [
                "SPHardwareDataType", "SPSoftwareDataType", "SPStorageDataType",
                "SPNetworkDataType", "SPDisplaysDataType", "SPUSBDataType",
                "SPAudioDataType", "SPPowerDataType", "-detailLevel",
                "mini", "full", "-json"
            ]
        ),
        WhitelistedBinary(
            name: "pmset",
            path: "/usr/bin/pmset",
            summary: "Read power and battery information. Only the -g read mode is allowed.",
            category: .systemInformation,
            flags: ["-g"],
            subcommands: ["batt", "ps", "therm", "custom", "live", "rawlog"],
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "networksetup",
            path: "/usr/sbin/networksetup",
            summary: "Read network configuration. Only get style options are allowed.",
            category: .systemInformation,
            flags: ["-getinfo", "-listallhardwareports", "-listallnetworkservices", "-listnetworkserviceorder"],
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "ifconfig",
            path: "/sbin/ifconfig",
            summary: "Show network interface addresses.",
            category: .systemInformation,
            flags: ["-a", "-l", "-u", "-v"],
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "ps",
            path: "/bin/ps",
            summary: "List running processes.",
            category: .systemInformation,
            flags: ["-A", "-a", "-e", "-f", "-u", "-x", "aux", "ax", "-ax", "-aux"],
            numbers: true,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "top",
            path: "/usr/bin/top",
            summary: "Sample processor and memory load. Use -l 1 for a single snapshot.",
            category: .systemInformation,
            flags: ["-l", "-n", "-o", "-s", "-stats", "-pid"],
            numbers: true
        ),
        WhitelistedBinary(
            name: "date",
            path: "/bin/date",
            summary: "Show the current date and time.",
            category: .textOutput,
            anyArguments: true
        ),
        WhitelistedBinary(
            name: "cal",
            path: "/usr/bin/cal",
            summary: "Print a calendar for a month or year.",
            category: .textOutput,
            numbers: true,
            maxPositional: 2
        ),
        WhitelistedBinary(
            name: "echo",
            path: "/bin/echo",
            summary: "Print text. Output is captured, not sent to a shell.",
            category: .textOutput,
            anyArguments: true
        ),
        WhitelistedBinary(
            name: "which",
            path: "/usr/bin/which",
            summary: "Show where a binary lives.",
            category: .developer,
            maxPositional: 1
        ),
        WhitelistedBinary(
            name: "git",
            path: "/usr/bin/git",
            summary: "Read only git commands: status, log, diff, branch, show, remote, rev-parse.",
            category: .developer,
            subcommands: ["status", "log", "diff", "branch", "show", "remote", "rev-parse", "describe", "shortlog"],
            paths: true,
            numbers: true,
            maxPositional: 3
        ),
        WhitelistedBinary(
            name: "python3",
            path: "/usr/bin/python3",
            summary: "Show the interpreter version. Only the --version flag is allowed.",
            category: .developer,
            flags: ["--version", "-V"]
        ),
        WhitelistedBinary(
            name: "swift",
            path: "/usr/bin/swift",
            summary: "Show the toolchain version. Only the --version flag is allowed.",
            category: .developer,
            flags: ["--version"]
        ),
        WhitelistedBinary(
            name: "xcodebuild",
            path: "/usr/bin/xcodebuild",
            summary: "Show the Xcode version. Only the -version flag is allowed.",
            category: .developer,
            flags: ["-version"]
        ),
        WhitelistedBinary(
            name: "open",
            path: "/usr/bin/open",
            summary: "Open a file, folder, or address with its default handler.",
            category: .finder,
            flags: ["-a", "-R", "-n"],
            paths: true,
            maxPositional: 2
        ),
        WhitelistedBinary(
            name: "pbcopy",
            path: "/usr/bin/pbcopy",
            summary: "Not permitted for input. Listed only to explain the refusal.",
            category: .textOutput
        )
    ]

    /// Binaries grouped by category for the settings screen.
    static var groupedByCategory: [CommandCategoryGroup] {
        CommandCategory.allCases.compactMap { category in
            let matches = binaries.filter { $0.category == category }
            guard !matches.isEmpty else { return nil }
            return CommandCategoryGroup(category: category, binaries: matches)
        }
    }

    /// Looks up a binary by bare name or absolute path.
    static func lookup(_ token: String) -> WhitelistedBinary? {
        if token.contains("/") {
            let expanded = expandTilde(token)
            return binaries.first { $0.path == expanded }
        }
        return binaries.first { $0.name == token }
    }

    // MARK: - Validation

    /// Validates a full command line, returning it ready for confirmation.
    ///
    /// Throws `AutomationError.commandNotPermitted` with a specific reason
    /// for each rejection so the model can adjust, and the user can see why.
    static func validate(_ rawCommand: String) throws -> ValidatedCommand {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw AutomationError.commandNotPermitted(reason: "the command was empty.")
        }
        guard command.count <= maximumCommandLength else {
            throw AutomationError.commandNotPermitted(
                reason: "the command is longer than \(maximumCommandLength) characters."
            )
        }

        let tokens = try tokenize(command)
        guard let executableToken = tokens.first else {
            throw AutomationError.commandNotPermitted(reason: "the command was empty.")
        }

        guard let binary = lookup(executableToken) else {
            throw AutomationError.commandNotPermitted(
                reason: "\(executableToken) is not on the whitelist. Allowed commands: \(binaries.map(\.name).sorted().joined(separator: ", "))."
            )
        }

        let arguments = Array(tokens.dropFirst())
        try validate(arguments: arguments, for: binary)

        return ValidatedCommand(
            executableURL: URL(fileURLWithPath: binary.path),
            arguments: arguments,
            displayCommand: ([binary.name] + arguments).joined(separator: " "),
            binaryName: binary.name,
            summary: binary.summary
        )
    }

    /// Splits a command line into tokens.
    ///
    /// Double quotes group a value, single quotes and backslashes are refused
    /// so quoting can never hide a second command.
    static func tokenize(_ command: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasContent = false

        for character in command {
            if character == "\"" {
                inQuotes.toggle()
                hasContent = true
                continue
            }
            if forbiddenCharacters.contains(character) {
                throw AutomationError.commandNotPermitted(
                    reason: "the character \(character) is not allowed because it could be interpreted by a shell."
                )
            }
            if character == " ", !inQuotes {
                if hasContent {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
                continue
            }
            current.append(character)
            hasContent = true
        }

        guard !inQuotes else {
            throw AutomationError.commandNotPermitted(reason: "the quotes in the command are unbalanced.")
        }
        if hasContent {
            tokens.append(current)
        }
        return tokens
    }

    /// Flags whose value is a separate token, for example `-name "*.swift"`.
    private static let flagsTakingValues: Set<String> = [
        "-name", "-iname", "-type", "-maxdepth", "-onlyin", "-newer", "-mtime",
        "-n", "-o", "-s", "-d", "-a", "-pid", "-detailLevel"
    ]

    /// Characters permitted inside a flag value such as a glob or a type letter.
    private static let allowedValueCharacters: Set<Character> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/*?+@"
    )

    /// Checks every argument against the rules for a binary.
    private static func validate(arguments: [String], for binary: WhitelistedBinary) throws {
        if binary.allowsAnyArguments { return }

        if !binary.allowedSubcommands.isEmpty && arguments.isEmpty {
            throw AutomationError.commandNotPermitted(
                reason: "\(binary.name) needs one of these subcommands: \(binary.allowedSubcommands.sorted().joined(separator: ", "))."
            )
        }

        var positionalCount = 0
        var sawSubcommand = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            if argument.hasPrefix("-") {
                let flag = argument.split(separator: "=").first.map(String.init) ?? argument
                guard binary.allowedFlags.contains(flag) else {
                    throw AutomationError.commandNotPermitted(
                        reason: "\(binary.name) does not accept the option \(flag)."
                    )
                }
                // Consume the value of a flag that expects one on its own token.
                if flagsTakingValues.contains(flag) {
                    index += 1
                    if index < arguments.count {
                        try validateFlagValue(arguments[index], for: binary)
                    }
                }
                index += 1
                continue
            }

            // Some tools accept bare word arguments, for example `ps aux`.
            // The catalog lists those words explicitly, so nothing else passes.
            if binary.allowedFlags.contains(argument) {
                index += 1
                continue
            }

            if !binary.allowedSubcommands.isEmpty && !sawSubcommand {
                guard binary.allowedSubcommands.contains(argument) else {
                    throw AutomationError.commandNotPermitted(
                        reason: "\(binary.name) only supports these subcommands: \(binary.allowedSubcommands.sorted().joined(separator: ", "))."
                    )
                }
                sawSubcommand = true
                index += 1
                continue
            }

            if binary.allowsNumericArguments && isNumeric(argument) {
                index += 1
                continue
            }

            if binary.allowsPathArguments, isPathLike(argument) {
                try validatePathArgument(argument)
                positionalCount += 1
                guard positionalCount <= max(1, binary.maxPositionalArguments) else {
                    throw AutomationError.commandNotPermitted(
                        reason: "\(binary.name) accepts at most \(binary.maxPositionalArguments) path argument(s)."
                    )
                }
                index += 1
                continue
            }

            throw AutomationError.commandNotPermitted(
                reason: "\(binary.name) does not accept the argument \(argument)."
            )
        }
    }

    /// Validates the value that follows a flag expecting one.
    private static func validateFlagValue(_ value: String, for binary: WhitelistedBinary) throws {
        if isPathLike(value) {
            try validatePathArgument(value)
            return
        }
        guard !value.isEmpty, value.allSatisfy({ allowedValueCharacters.contains($0) }) else {
            throw AutomationError.commandNotPermitted(
                reason: "the value \(value) is not a plain value for an option of \(binary.name)."
            )
        }
    }

    /// Confirms a path argument points inside an allowed root.
    private static func validatePathArgument(_ argument: String) throws {
        let expanded = expandTilde(argument)
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        guard PathGuard.isAllowed(standardized) else {
            throw AutomationError.pathNotAllowed(standardized)
        }
    }

    /// Expands a leading tilde to the user home folder.
    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// Path arguments are those starting with a slash or a tilde.
    private static func isPathLike(_ argument: String) -> Bool {
        argument.hasPrefix("/") || argument.hasPrefix("~") || argument.contains("/")
    }

    private static func isNumeric(_ argument: String) -> Bool {
        !argument.isEmpty && argument.allSatisfy { $0.isNumber }
    }
}
