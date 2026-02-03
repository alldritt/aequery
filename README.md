# aequery

A macOS command-line tool that queries scriptable applications using XPath-like expressions, translating them into Apple Events.

## Build

```
swift build
```

## Usage

```
aequery [--json | --text] [--verbose] [--dry-run] '<expression>'
```

### Flags

| Flag | Description |
|------|-------------|
| `--json` | Output as JSON (default) |
| `--text` | Output as plain text |
| `--verbose` | Show tokens, AST, and resolved steps on stderr |
| `--dry-run` | Parse and resolve only, do not send Apple Events |

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

### Predicates

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[n]` | By index (1-based) | `/TextEdit/documents[1]/name` |
| `[-1]` | Last element | `/Finder/windows[-1]/name` |
| `[n:m]` | Range | `/TextEdit/documents[1]/paragraphs[1:5]` |
| `[@name="x"]` | By name | `/Finder/windows[@name="Desktop"]` |
| `[#id=n]` | By unique ID | `/Finder/windows[#id=42]` |
| `[prop op val]` | Whose clause | `/Finder/files[size > 1000]/name` |

### Whose clauses

Comparison operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `contains`

Compound expressions with `and` / `or`:

```bash
aequery '/Finder/files[size > 1000 and name contains "test"]'
```

### Multiple predicates

Predicates can be chained:

```bash
aequery '/Finder/windows[1][@name="Desktop"]'
```

## Examples

```bash
# JSON list of Finder window names
aequery '/Finder/windows/name'
# ["AICanvas", "Documents"]

# Plain text output
aequery --text '/Finder/desktop/name'
# Desktop

# Inspect parsing without sending
aequery --verbose --dry-run '/TextEdit/documents[1]/paragraphs'

# First window name
aequery --text '/Finder/windows[1]/name'
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

88 tests across 8 suites covering the lexer, parser, SDEF parsing, resolver, specifier building, descriptor decoding, output formatting, and live integration tests against Finder.

## Requirements

- macOS 13+
- Swift 5.9+
