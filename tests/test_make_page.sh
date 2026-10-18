#!/bin/sh
# make_page.sh adds the black-background style once, right before </head>, and keeps the rest of the page.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '<html><head>\n<link rel="stylesheet" href="app/styles/base.css">\n</head><body>x</body></html>\n' > "$tmp/vnc.html"
sh "$here/../linux/make_page.sh" "$tmp/vnc.html" "$tmp/out.html"
[ "$(grep -c '#noVNC_container > div { background: #000 !important; }' "$tmp/out.html")" = 1 ]
awk '/noVNC_container > div/{s=NR} /<\/head>/{h=NR} END{exit !(s && h && s < h)}' "$tmp/out.html"
grep -q 'app/styles/base.css' "$tmp/out.html"
grep -q '<body>x</body>' "$tmp/out.html"
printf '<html><body>no head</body></html>\n' > "$tmp/bad.html"
if sh "$here/../linux/make_page.sh" "$tmp/bad.html" "$tmp/bad_out.html" 2>/dev/null; then echo "should fail"; exit 1; fi
echo "ok"
