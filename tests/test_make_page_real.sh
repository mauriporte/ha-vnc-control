#!/bin/sh
# Against the real vnc.html shipped by Debian/Ubuntu's novnc package (CI runner).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
command -v apt-get >/dev/null || { echo "skip: no apt"; exit 0; }
[ -f /usr/share/novnc/vnc.html ] || sudo apt-get install -y -qq novnc >/dev/null
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sh "$here/../linux/make_page.sh" /usr/share/novnc/vnc.html "$tmp/vnc-control.html"
grep -q '#noVNC_container > div { background: #000 !important; }' "$tmp/vnc-control.html"
[ "$(wc -l < "$tmp/vnc-control.html")" -gt "$(wc -l < /usr/share/novnc/vnc.html)" ]
echo "ok"
