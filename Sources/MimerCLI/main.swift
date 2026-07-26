import Foundation

// `mimer` — a tiny command-line front-end to Mimer's ⌘K transform engine.
// It shares ClipTransform.swift verbatim with the app (same code, no duplication)
// and does the Unix thing: read text from an argument or stdin, write the result
// to stdout. It touches no clipboard history and needs no running app — it is a
// pure function over text, so it is safe for any script or AI agent to call.
//
// Usage:
//   mimer <transform> [text]     apply a transform to [text], or to stdin if omitted
//   echo '{"a":1}' | mimer json-to-ts
//   mimer list                   list available transforms (id + kebab alias)
//   mimer help | version

let cliVersion = "0.2.2"

/// Maps friendly kebab aliases to ClipTransform ids, so an agent can call the
/// obvious name (`json-to-ts`, `decode-jwt`) instead of the terse internal id.
let aliases: [String: String] = [
    "uppercase": "upper", "lowercase": "lower", "title-case": "title",
    "trim": "trim", "slugify": "slug",
    "base64-encode": "b64enc", "base64-decode": "b64dec",
    "url-encode": "urlenc", "url-decode": "urldec",
    "json-pretty": "jsonpretty", "json-minify": "jsonmin",
    "decode-jwt": "jwt", "strip-tracking": "urlstrip", "decode-query": "urlquery",
    "unix-to-iso": "epoch2iso", "iso-to-unix": "iso2epoch",
    "json-to-ts": "json2ts",
    "sort-lines": "sortlines", "dedupe-lines": "dedupelines", "reverse-lines": "reverselines",
    "camel-case": "camel", "snake-case": "snake",
]

/// Reverse map (id -> preferred alias) for display in `list`.
let preferredAlias: [String: String] = Dictionary(
    aliases.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a }
)

func transform(named key: String) -> ClipTransform? {
    let id = aliases[key] ?? key
    return ClipTransform.all.first { $0.id == id }
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("mimer: " + message + "\n").utf8))
    exit(code)
}

func readStdin() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func printUsage(to handle: FileHandle) {
    let text = """
    mimer \(cliVersion) — text transforms from Mimer, the macOS clipboard manager.

    Usage:
      mimer <transform> [text]     transform [text], or stdin if omitted
      mimer list                   list available transforms
      mimer help | version

    Examples:
      echo '{"id":1,"name":"a"}' | mimer json-to-ts
      mimer decode-jwt "$TOKEN"
      pbpaste | mimer slugify | pbcopy

    Run `mimer list` to see every transform.

    """
    handle.write(Data(text.utf8))
}

func printList() {
    var lines = ["Available transforms (name — description):"]
    for t in ClipTransform.all {
        let name = preferredAlias[t.id] ?? t.id
        lines.append("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(t.name)")
    }
    lines.append("")
    print(lines.joined(separator: "\n"))
}

// MARK: - Entry point

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case nil, "help", "-h", "--help":
    printUsage(to: args.isEmpty ? FileHandle.standardError : FileHandle.standardOutput)
    exit(args.isEmpty ? 64 : 0)   // 64 = EX_USAGE when invoked with no command

case "version", "--version", "-v":
    print("mimer \(cliVersion)")

case "list", "ls":
    printList()

default:
    // Treat the first argument as a transform name; allow an explicit `transform` verb too.
    var rest = args
    if rest.first == "transform" { rest.removeFirst() }
    guard let name = rest.first else { printUsage(to: FileHandle.standardError); exit(64) }
    guard let t = transform(named: name) else {
        fail("unknown transform '\(name)'. Run `mimer list` to see the options.", code: 2)
    }
    let input = rest.count > 1 ? rest.dropFirst().joined(separator: " ") : readStdin()
    guard let out = t.apply(input), !out.isEmpty else {
        fail("transform '\(name)' did not apply to the input.", code: 1)
    }
    print(out)
}
