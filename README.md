# aequery

A macOS command-line tool that queries scriptable applications using XPath-like expressions, translating them into Apple Events.

## Build

```
swift build
```

## Usage

```
aequery [--json | --text | --applescript | --chevron] [--flatten] [--unique] [--verbose] [--dry-run] [--sdef] [--find-paths] '<expression>'
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
aequery '/Mail/account/mailboxes/message[sender = "sender@comain.com"]/subject' --flatten
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
```

## Architecture

The tool is split into a library (`AEQueryLib`) and a CLI (`aequery`):

```
Sources/
├── aequery/main.swift              # CLI entry point
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

132 tests across 10 suites covering the lexer, parser, SDEF parsing, resolver, path finder, specifier building, descriptor decoding, output formatting, and live integration tests against Finder.

## Requirements

- macOS 13+
- Swift 5.9+
