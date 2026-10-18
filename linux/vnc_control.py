#!/usr/bin/env python3
"""VNC Control sessions: add, list and remove VNC servers that the noVNC viewer can open.

websockify runs in token mode (--token-plugin TokenFile --token-source TOKENS_DIR): a browser connects to
/websockify?token=<name> and websockify forwards it to the host:port written in TOKENS_DIR/<name>. This service writes
those files plus the public list the viewer page reads (WEB_DIR/vnc-sessions.json).

API (X-Token header required on every call):
  GET    /sessions                      -> [{"name", "host", "port", "has_password"}]
  POST   /sessions  {"name", "host", "port"=5900, "password"="", "width"=1024, "height"=600}
  DELETE /sessions/<name>
Config: /etc/vnc-control/config.json {"token": "...", "port": 8093, "tokens_dir": "...", "web_dir": "..."}
"""
import ipaddress, json, os, re, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CFG = json.load(open(os.environ.get("VNC_CONTROL_CONFIG", "/etc/vnc-control/config.json")))
TOKENS = CFG.get("tokens_dir", "/etc/vnc-control/tokens")
WEB = CFG.get("web_dir", "/usr/share/novnc")
STORE = os.path.join(TOKENS, "..", "sessions.json")  # full records (passwords included), not served
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,39}$")
HOST_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]{0,252})$")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def load():
    try:
        return json.load(open(STORE))
    except (OSError, ValueError):
        return []


def save(sessions):
    """Write the store, one token file per session, and the viewer's list (passwords only if given)."""
    for s in sessions:  # the token is always derived from the name (hand-edited stores included)
        s["token"] = slug(s["name"])
    tmp = STORE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(sessions, f, indent=1)
    os.chmod(tmp, 0o600); os.replace(tmp, STORE)
    wanted = {s["token"] for s in sessions}
    for fn in os.listdir(TOKENS):
        if fn not in wanted:
            os.remove(os.path.join(TOKENS, fn))
    for s in sessions:
        with open(os.path.join(TOKENS, s["token"]), "w") as f:
            f.write(f'{s["token"]}: {s["host"]}:{s["port"]}\n')
    public = [{k: s[k] for k in ("name", "token", "width", "height", "password")} for s in sessions]
    tmp = os.path.join(WEB, "vnc-sessions.json.tmp")
    with open(tmp, "w") as f:
        json.dump(public, f)
    os.replace(tmp, os.path.join(WEB, "vnc-sessions.json"))


def validate(d):
    name = str(d.get("name", "")).strip()
    host = str(d.get("host", "")).strip()
    if not NAME_RE.match(name):
        raise ValueError("name: letters, digits, spaces, _ . - (max 40)")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        if not HOST_RE.match(host):
            raise ValueError("host: IP address or hostname")
    port = int(d.get("port") or 5900)
    if not 1 <= port <= 65535:
        raise ValueError("port: 1-65535")
    w, h = int(d.get("width") or 1024), int(d.get("height") or 600)
    if not (100 <= w <= 8000 and 100 <= h <= 8000):
        raise ValueError("width/height: 100-8000")
    return {"name": name, "token": slug(name), "host": host, "port": port, "width": w, "height": h,
            "password": str(d.get("password") or "")}


class H(BaseHTTPRequestHandler):
    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def authed(self):
        if self.headers.get("X-Token") != CFG["token"]:
            self.reply(401, {"error": "bad token"}); return False
        return True

    def do_GET(self):
        if self.authed() and self.path == "/sessions":
            self.reply(200, [{"name": s["name"], "host": s["host"], "port": s["port"], "has_password": bool(s["password"])}
                             for s in load()])
        elif self.path != "/sessions":
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        if not self.authed():
            return
        if self.path != "/sessions":
            return self.reply(404, {"error": "not found"})
        try:
            d = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            s = validate(d)
        except (ValueError, TypeError) as e:
            return self.reply(400, {"error": str(e)})
        sessions = [x for x in load() if x["token"] != s["token"]] + [s]  # same name = update
        save(sessions); self.reply(200, {"ok": True, "token": s["token"], "sessions": len(sessions)})

    def do_DELETE(self):
        if not self.authed():
            return
        m = re.match(r"^/sessions/(.+)$", self.path)
        if not m:
            return self.reply(404, {"error": "not found"})
        tok = slug(m.group(1).replace("%20", " "))
        sessions = load()
        left = [x for x in sessions if x["token"] != tok]
        if len(left) == len(sessions):
            return self.reply(404, {"error": "no such session"})
        save(left); self.reply(200, {"ok": True, "sessions": len(left)})

    def log_message(self, *a):
        sys.stderr.write("vnc-control: " + (a[0] % a[1:]) + "\n")


if __name__ == "__main__":
    os.makedirs(TOKENS, exist_ok=True)
    save(load())  # make token files and the viewer list match the store at start
    ThreadingHTTPServer(("0.0.0.0", int(CFG.get("port", 8093))), H).serve_forever()
