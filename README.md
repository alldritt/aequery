# aequery

A macOS command-line tool that queries scriptable applications using XPath-like expressions, translating them into Apple Events.

## Install

```
brew tap alldritt/tools
brew install aequery
```

A companion tool, `aelint`, validates and tests an application's scripting interface. See [aelint](#aelint) below.

```
brew install aelint
```

## Build

```
swift build
```

## Usage

```
aequery [--json | --text | --applescript | --chevron] [--flatten] [--unique] [--verbose] [--dry-run] [--sdef] [--find-paths] [--sdef-file <path>] '<expression>'
```

### Flags

| Flag | Description |
|------|-------------|
| `--json` | Output as JSON (default) |
| `--text` | Output as plain text |
| `--applescript` | Output as AppleScript using SDEF terminology |
| `--chevron` | Output as AppleScript using `«class xxxx»` chevron syntax |
| `--flatten` | Flatten nested lists into a single list |
| `--unique` | Remove duplicate values from the result list (use with `--flatten`) |
| `--verbose` | Show tokens, AST, and resolved steps on stderr |
| `--dry-run` | Parse and resolve only, do not send Apple Events |
| `--sdef` | Print the SDEF definition for the resolved element or property |
| `--find-paths` | Find all valid paths from the application root to the target |
| `--sdef-file <path>` | Load SDEF from a file path instead of from the application bundle |

## Expression Syntax

Expressions follow an XPath-like path starting with `/AppName`:

```
/AppName/element_or_property[predicate]/...
```

### Basic paths

```bash
# Get names of all Finder windows
aequery '/Finder/windows/name'

# Get the desktop name
aequery --text '/Finder/desktop/name'

# App names with spaces use quotes
aequery '/"Script Debugger"/windows'
```

### Multi-word names

SDEF class and property names with multiple words (e.g., `disk item`, `file type`) are handled automatically — the lexer greedily consumes spaces between words when followed by another letter. No quoting is needed:

```bash
aequery '/Finder/disk items/name'
aequery '/Finder/files[file type = "txt"]/name'
```

Reserved keywords (`and`, `or`, `contains`, `begins`, `ends`, `middle`, `some`) act as word boundaries. If a keyword appears as a word within a multi-word name, the lexer splits at that point. For example, `file type contains "txt"` is parsed as the name `file type`, the keyword `contains`, and the value `"txt"`. App names that contain reserved words can be quoted to avoid ambiguity:

```bash
aequery '/"Some App"/windows'
```

### Predicates

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[n]` | By index (1-based) | `/TextEdit/documents[1]/name` |
| `[-1]` | Last element | `/Finder/windows[-1]/name` |
| `[middle]` | Middle element | `/Finder/windows[middle]/name` |
| `[some]` | Random element | `/Finder/windows[some]/name` |
| `[n:m]` | Range | `/TextEdit/documents[1]/paragraphs[1:5]` |
| `[@name="x"]` | By name | `/Finder/windows[@name="Desktop"]` |
| `[#id=n]` | By unique ID | `/Finder/windows[#id=42]` |
| `[prop op val]` | Whose clause | `/Finder/files[size > 1000]/name` |

### Whose clauses

Comparison operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `contains`, `begins`, `ends`

Compound expressions with `and` / `or`:

```bash
aequery '/Finder/files[size > 1000 and name contains "test"]'
```

## Examples

```bash
# JSON list of Finder window names
aequery '/Finder/windows/name'
# ["AICanvas", "Documents"]

# JSON list of all email addresses in Contacts, flattened to a unique list
aequery '/Contacts/people/emails/value' --flatten --unique
# ["address1@domain.com", "address2@domain.com", ...]

# JSON list of all Mail messages received from "apple.com", flattened to a list
aequery '/Mail/account/mailboxes/message[sender ends "apple.com"]' --flatten
# ["address1@domain.com", "address2@domain.com", ...]

# JSON list of subjects of all emails from a sender, flattened to a list
aequery '/Mail/account/mailboxes/message[sender = "sender@domain.com"]/subject' --flatten
# ["subject string", ...]

# Plain text output
aequery --text '/Finder/desktop/name'
# Desktop

# Inspect parsing without sending
aequery --verbose --dry-run '/TextEdit/documents[1]/paragraphs'

# First window name
aequery --text '/Finder/windows[1]/name'

# Last window name
aequery --text '/Finder/windows[-1]/name'

# Show SDEF definition for the window class
aequery --sdef '/Finder/windows'

# Show SDEF definition for the name property
aequery --sdef '/Finder/windows/name'

# Flatten nested lists (e.g. name of every file in every folder)
aequery --flatten '/Finder/folders/files/name'

# Flatten and remove duplicates
aequery --flatten --unique '/Finder/folders/files/name'

# AppleScript terminology output
aequery --applescript '/Finder/windows'
# tell application "Finder"
#     every window
# end tell

# AppleScript chevron output
aequery --chevron '/Finder/windows'
# every «class cwin» of application "Finder"

# Find all paths to a class
aequery --find-paths '/Finder/file'
# /Finder/files
# /Finder/Finder windows/files
# /Finder/folders/files

# Find all paths to a property
aequery --find-paths '/Finder/name'
# /Finder/name
# /Finder/files/name
# /Finder/windows/name
# ...

# Load SDEF from a file (app doesn't need to be installed)
/usr/bin/sdef /System/Applications/Contacts.app > /tmp/contacts.sdef
aequery --sdef-file /tmp/contacts.sdef --dry-run '/Contacts/people'
aequery --sdef-file /tmp/contacts.sdef --sdef '/Contacts/people'
aequery --sdef-file /tmp/contacts.sdef --find-paths '/Contacts/people'
```

## Application Resolution

When you use an expression like `/Finder/...`, aequery locates the application in the following order:

1. **Running applications** — checks `NSWorkspace.shared.runningApplications` for a matching name, so the SDEF is loaded from the same bundle that is actually running.
2. **Common locations** — searches these directories in order:
   - `/Applications/`
   - `/System/Applications/`
   - `/System/Applications/Utilities/`
   - `/Applications/Utilities/`
   - `/System/Library/CoreServices/`
3. **Spotlight (`mdfind`)** — queries Spotlight for apps matching the display name, which finds apps installed in non-standard locations (e.g., `~/Applications`).

If none of these find the app, an error is returned. You can bypass resolution entirely with `--sdef-file` to load a scripting dictionary from a file. Use `--verbose` to see which app path was resolved.


## aelint

`aelint` is a companion tool that validates and tests a scriptable application's scripting interface. It reads the same SDEF that `aequery` uses, runs a set of static checks against the dictionary, and can optionally exercise the running application with live Apple Events to confirm the interface behaves as it's described.

```
aelint <AppName> [--dynamic] [--json | --html] [--summary] [--sdef-file <path>] [options]
```

### What it checks

The static checks read the SDEF alone and need only the dictionary:

- Undefined classes, property types, and command parameter/result types
- Inheritance cycles and classes that aren't reachable from the application root
- Duplicate four-character codes across classes, commands, and parameters
- Missing or non-standard plural element names
- Reserved-word and Standard Suite term clashes
- Empty classes, unused enumerations, and missing documentation

### Dynamic testing

With `--dynamic`, aelint connects to the running application and exercises the interface the dictionary describes, one phase at a time. It's designed to be non-destructive — anything a phase touches is restored before it moves on.

- **Reading and counting.** Reads every application and element property, counts the elements of each type, and retrieves properties in bulk with `get <property> of every <element>`.
- **Element access.** Reaches elements by index, by negative index, by ordinal (`first`, `middle`, `last`), and by range, then confirms the results.
- **Filtering.** Runs `whose` clauses with the textual operators (`contains`, `begins with`, `=`) and the numeric ones (`>`, `<`, `≥`, `≤`), and checks `exists`.
- **Type validation.** Compares the runtime descriptor type of each value against the type declared in the SDEF and reports mismatches.
- **Setting properties.** For each writable property it reads the current value and sets it straight back to the same value — enough to prove the property is settable without changing it. A property declared read-write that rejects the set is reported.
- **Creating and deleting.** Where the app declares `make` and `delete`, it creates a new element — limited to `document`, `window`, and `tab` — verifies the count went up, deletes it, and verifies the count returns to where it started.
- **Commands.** Probes each command (skipping destructive verbs like `quit`, `close`, `save`, `print`, `move`, and `duplicate`) to confirm the application actually handles the event its dictionary advertises.
- **Enumerations.** Round-trips enumerated values to confirm they're accepted.

Events slower than `--slow-threshold` (default 1s) are flagged, a per-event `--timeout` (default 10s) guards against an unresponsive app, and a coverage summary reports how much of the interface was exercised.

**NOTE:** Even though the tests restore what they touch, `--dynamic` sends real Apple Events — including `make`, `delete`, and `set` — to the live application. A bug in the app's own handlers could still lose data. Run it against an application you don't mind poking at, not one holding unsaved work.

### What the findings mean

Every finding names a category. The static checks and why each one matters:

| Category | Severity | Meaning and consequence |
|----------|----------|-------------------------|
| `duplicate-code` | error / warning | Two classes, or two properties of one class, share a four-character code (error); two commands or two enumerators share one (warning). Apple Events identify everything by its 4CC, not its name, so a duplicated code makes the term ambiguous — AppleScript can resolve a name to the wrong object, or send a code that means something else. |
| `invalid-code` | error | A class or property code isn't exactly four bytes, or a command code isn't eight. The code can't be packed into an Apple Event correctly. |
| `duplicate-param-code` | error | Two parameters of one command share a code. An Apple Event is a record keyed by code, so the second parameter overwrites the first and one becomes unreachable. |
| `duplicate-command-code` | warning | Two commands share an event code. The application can't tell which one was invoked. |
| `inheritance-cycle` | error | A class inherits from itself through a loop. Inherited properties and elements can't be resolved, and tools that walk the inheritance chain will hang. |
| `undefined-class` | error / warning | An element's type (error) or a class's parent (warning) names a class that isn't in the dictionary. Scripts can't resolve that element, and inherited members are lost. |
| `undefined-type`, `undefined-command-type` | info | A property, or a command parameter/result, names a type that isn't defined in the SDEF. Usually a system type, but worth checking for a typo or a missing definition — tooling can't validate or display it. |
| `name-clash` | warning | A name is both an element and a property of the same class. `window of x` is then ambiguous, so object specifier construction may target the wrong one. |
| `missing-plural` | info / warning | A class used as an element has no explicit plural, which AppleScript needs for `every window` / `windows`. Info when appending "s" yields the right word; warning when it doesn't (e.g. `shelf` → `shelfs`), in which case the plural users expect won't work. |
| `non-standard-term` | warning | A well-known code such as `pnam` carries a non-standard name. Standard idioms like `name of` won't behave the way scripters expect. |
| `reserved-word` | warning / info | A class (warning) or property (info) name collides with an AppleScript keyword. Scripts using the bare term won't compile; `of` syntax or quoting is needed to disambiguate. |
| `standard-suite` | warning / info | The application class is missing — or uses non-standard codes for — expected Standard Suite properties, elements, or commands. Generic clients and standard idioms that assume the Standard Suite may not work. |
| `unreachable` | warning | No containment path reaches the class from the application root within `--max-depth`. Scripts can't navigate to it; it may be dead or missing an accessor. |
| `inferred-reachable` | info | The class is reached only through a parent's accessor that can return subclass instances at runtime. Noted in case the app never actually returns that subclass. |
| `unused-enum` | info | An enumeration isn't referenced by any property or command — either dead weight, or a sign that a property's type is missing. |
| `empty-class` | info | A class has no visible properties or elements. Likely incomplete, or only a placeholder type. |
| `documentation` | info | Some classes or commands have no description, so dictionary viewers show no help for them. |
| `hidden-items` | info | Counts the classes, properties, and commands marked hidden. Informational. |

Dynamic findings are prefixed `dynamic-` and describe runtime behaviour rather than dictionary defects: a property declared read-write that rejects a `set`, a command the dictionary lists but the app doesn't handle, a value whose runtime type doesn't match its declared type, or an event slower than the threshold. Each message spells out the specific mismatch and the command that produced it.

### Example

```
$ aelint TextEdit
aelint report for TextEdit
========================================
Bundle ID: com.apple.TextEdit
Version: 1.20
Path: /System/Applications/TextEdit.app
Classes: 12, Commands: 13, Enumerations: 2
Findings: 0 errors, 1 warnings, 3 info

! WARNING (1)
----------------------------------------
  undefined-class: Class 'attachment' inherits from undefined class 'text.ctxt'

i INFO (3)
----------------------------------------
  undefined-type: Property 'text' in class 'document' has type 'text.ctxt' which is not defined in the SDEF
  missing-plural: Class 'attachment' has no explicit plural (defaults to 'attachments')
  documentation: 1 of 12 classes (8%) have no description

========================================
Quality Score: 99/100 (A)
========================================
```

### Flags

| Flag | Description |
|------|-------------|
| `--dynamic` | Run dynamic tests (sends Apple Events to the running application) |
| `--json` | Output the report as JSON |
| `--html` | Output the report as HTML |
| `--summary` | Print the SDEF dictionary outline and exit |
| `--severity <level>` | Minimum severity to display: `error`, `warning`, or `info` (default: `info`) |
| `--log` | Log each Apple Event sent and its result to stderr |
| `--timeout <sec>` | Per-event timeout for dynamic tests (default: 10) |
| `--slow-threshold <sec>` | Events above this are flagged as slow (default: 1.0) |
| `--max-depth <n>` | Maximum containment depth for path enumeration (default: 6) |
| `--sdef-file <path>` | Load SDEF from a file instead of from the application bundle |

Reports are plain text by default; `--json` gives machine-readable output and `--html` a formatted report for the browser. aelint exits with a non-zero status when any errors are found, so it can gate a build.

## Architecture

The tool is split into a library (`AEQueryLib`) and a CLI (`aequery`):

```
Sources/
├── aequery/main.swift              # aequery CLI entry point
├── aelint/                         # aelint CLI (static checks + dynamic tests)
└── AEQueryLib/
    ├── Lexer/                      # Tokenizer
    ├── Parser/                     # Recursive descent parser → AST
    ├── SDEF/                       # SDEF XML parsing and name resolution
    ├── AEBuild/                    # Object specifier construction and event sending
    └── Formatter/                  # Reply decoding and output formatting
```

**Pipeline:** Expression → Tokens → AST → SDEF Resolution → Object Specifier → Apple Event → Decode Reply → Format Output

## Tests

```
swift test
```

191 tests across 12 suites covering the lexer, parser, SDEF parsing, resolver, path finder, specifier building, descriptor decoding, output formatting, composite type name resolution, and live integration tests against Finder.

## Requirements

- macOS 13+
- Swift 5.9+
