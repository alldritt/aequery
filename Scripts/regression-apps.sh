#!/bin/sh
#
# Run aelint's structural-correctness checks against a fixed set of scriptable
# applications and report the findings (term<->code ambiguity, malformed names,
# and bad code lengths).
#
# These apps exercise real-world SDEF quirks that the SDEFValidator unit tests
# model in miniature: the Standard Suite's deliberate parameter-code reuse
# (kocl, insh, ...), cross-namespace code collisions (Finder's colr, ics8, appt;
# Numbers'/Pages' NMCT), enumerator-code collisions (Finder's flvw, elsv),
# enumeration-name vs property-name collisions (image quality; Contacts' url),
# and malformed terminology names (Finder's desktop-object, ICN#).
#
# This is NOT a hermetic test — results depend on which app versions are
# installed — so run it by hand when changing the validation logic, not as part
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
Terminal"

IFS='
'
for app in $APPS; do
    echo "===== $app ====="
    "$AELINT" "$app" 2>&1 | grep -E "ambiguous-code|ambiguous-term|invalid-name|invalid-code|undefined-extends|undefined-responds-to|duplicate-id" \
        || echo "  (no structural findings)"
done
