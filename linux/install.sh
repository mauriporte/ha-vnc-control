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

for unit in x11vnc novnc vnc-control; do
    sed -e "s#__USER__#$user#g" -e "s#__HOME__#$home#g" -e "s#__PORT__#$port#g" "$here/$unit.service" \
        > "/etc/systemd/system/$unit.service"
done

# Sessions: websockify runs in token mode; vnc_control.py (API :8093) writes one token file per VNC server
install -m 755 "$here/vnc_control.py" /opt/vnc_control.py
install -d -o "$user" -m 700 /etc/vnc-control /etc/vnc-control/tokens
install -d -o "$user" -m 755 /var/lib/vnc-control
if [ ! -f /etc/vnc-control/config.json ]; then
    api_token=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
    printf '{"token": "%s", "port": 8093, "tokens_dir": "/etc/vnc-control/tokens", "web_dir": "/var/lib/vnc-control"}\n' \
        "$api_token" > /etc/vnc-control/config.json
    chown "$user" /etc/vnc-control/config.json; chmod 600 /etc/vnc-control/config.json
    echo "API token for Home Assistant (secrets.yaml vnc_control_token): $api_token"
fi
# this machine's own desktop is the first session (edit or remove it later through the API)
[ -f /etc/vnc-control/sessions.json ] || printf '[{"name": "%s", "token": "%s", "host": "127.0.0.1", "port": 5900, "width": 1920, "height": 1080, "password": ""}]\n' \
    "$(hostname)" "local" > /etc/vnc-control/sessions.json  # the service derives the real token from the name
chown "$user" /etc/vnc-control/sessions.json; chmod 600 /etc/vnc-control/sessions.json

sh "$here/make_page.sh" "$web/vnc.html" "$web/vnc-control.html"
install -m 644 "$here/vnc-control-multi.html" "$web/vnc-control-multi.html"
ln -sfn /var/lib/vnc-control/vnc-sessions.json "$web/vnc-sessions.json"
cat > "$web/index.html" <<'EOF'
<!doctype html><meta charset="utf-8"><title>VNC Control</title>
<meta http-equiv="refresh" content="0; url=vnc-control-multi.html">
<a href="vnc-control-multi.html">Open the desktops</a>
EOF
[ -z "$key" ] || ln -sfn "$web" "$web/$key"   # /<key>/vnc-control.html serves the same files

systemctl daemon-reload
systemctl enable --now x11vnc vnc-control novnc
echo "Done: http://$(hostname -I | cut -d' ' -f1):$port/${key:+$key/}vnc-control-multi.html"
