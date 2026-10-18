#!/bin/sh
# VNC Control: share a Linux desktop (X11) in the browser with x11vnc + noVNC, ready for a Home Assistant iframe.
# Run as root on the machine whose screen you want:  sudo ./install.sh [user] [port] [path-key]
#   user      desktop user whose session is shared (default: the user who ran sudo)
#   port      noVNC web port (default 6080)
#   path-key  optional secret: also serve the page under /<path-key>/ (for a Cloudflare Access bypass, see README)
# Debian/Ubuntu/Raspberry Pi OS with LightDM or any X11 display manager. Wayland sessions are not supported by x11vnc.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
user=${1:-${SUDO_USER:-}}; port=${2:-6080}; key=${3:-}
[ -n "$user" ] || { echo "usage: sudo ./install.sh <user> [port] [path-key]" >&2; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
web=/usr/share/novnc

apt-get install -y x11vnc novnc websockify

if [ ! -s "$home/.vnc/passwd" ]; then
    echo "Choose the VNC password for $user (VNC uses only the first 8 characters):"
    su - "$user" -c 'mkdir -p ~/.vnc && chmod 700 ~/.vnc && x11vnc -storepasswd ~/.vnc/passwd'
fi

for unit in x11vnc novnc; do
    sed -e "s#__USER__#$user#g" -e "s#__HOME__#$home#g" -e "s#__PORT__#$port#g" "$here/$unit.service" \
        > "/etc/systemd/system/$unit.service"
done

sh "$here/make_page.sh" "$web/vnc.html" "$web/vnc-control.html"
cat > "$web/index.html" <<'EOF'
<!doctype html><meta charset="utf-8"><title>VNC Control</title>
<meta http-equiv="refresh" content="0; url=vnc-control.html?autoconnect=1&resize=scale&reconnect=1&show_dot=1">
<a href="vnc-control.html?autoconnect=1&resize=scale&reconnect=1&show_dot=1">Open the desktop</a>
EOF
[ -z "$key" ] || ln -sfn "$web" "$web/$key"   # /<key>/vnc-control.html serves the same files

systemctl daemon-reload
systemctl enable --now x11vnc novnc
echo "Done: http://$(hostname -I | cut -d' ' -f1):$port/${key:+$key/}vnc-control.html?autoconnect=1&resize=scale&reconnect=1&show_dot=1"
