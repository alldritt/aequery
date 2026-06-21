#!/bin/sh
#
# Run aelint's term <-> code bijection check against a fixed set of scriptable
# applications and report any ambiguity findings.
#
# These apps exercise real-world SDEF quirks that the SDEFValidator unit tests
# model in miniature: the Standard Suite's deliberate parameter-code reuse
# (kocl, insh, ...), cross-namespace code collisions (Finder's colr, ics8, appt;
# Numbers'/Pages' NMCT), enumerator-code collisions (Finder's flvw, elsv), and
# enumeration-name vs property-name collisions (image quality; Contacts' url).
#
# This is NOT a hermetic test — results depend on which app versions are
# installed — so run it by hand when changing the bijection logic, not as part
# of `swift test`. A change to SDEFValidator that adds or removes findings here
# should be understood before it's accepted.

set -e
cd "$(dirname "$0")/.."

swift build >/dev/null
AELINT=.build/debug/aelint

# One app per line. Add new apps here.
APPS="Finder
Numbers
Google Chrome
Pages
Keynote
TextEdit
Notes
Contacts
Photos
Messages
Music
Shortcuts
Safari
Terminal
System Events
Image Events
Database Events
Shortcuts Events"

IFS='
'
for app in $APPS; do
    echo "===== $app ====="
    "$AELINT" "$app" 2>&1 | grep -E "is used by multiple (terms|codes)" \
        || echo "  (no ambiguity findings)"
done
