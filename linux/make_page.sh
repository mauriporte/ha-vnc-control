#!/bin/sh
# Build vnc-control.html from noVNC's vnc.html: same page plus a black background around the scaled screen.
# Why a separate page: noVNC's rfb.js sets an inline rgb(40,40,40) background (grey bars when the frame's shape
# differs from the screen's), and browsers cache vnc.html, so editing it in place may never reach them.
# Usage: make_page.sh /usr/share/novnc/vnc.html /usr/share/novnc/vnc-control.html
set -eu
src=$1; dst=$2
grep -q '</head>' "$src" || { echo "no </head> in $src" >&2; exit 1; }
style='    <style>html, body, #noVNC_container { background: #000 !important; } #noVNC_container > div { background: #000 !important; }</style>'
awk -v s="$style" '/<\/head>/ && !done { print "    <!-- VNC Control: black around the scaled screen (rfb.js sets an inline grey) -->"; print s; done=1 } { print }' "$src" > "$dst"
