# VNC Control for Home Assistant

See and control the desktop of a Linux machine (a Raspberry Pi with a screen, a mini-PC, a kiosk) from a Home
Assistant dashboard, like a phone in [ADB Control](https://github.com/mauriporte/ha-adb-control). It shares the
**real** screen (what the attached monitor shows), with mouse and keyboard, in the browser, and optionally from
outside your home through a Cloudflare tunnel.

Built on [x11vnc](https://github.com/LibVNC/x11vnc) and [noVNC](https://github.com/novnc/noVNC); this repo is the
setup that makes them fit a dashboard cleanly.

## What you get

- **The desktop in a dashboard view**, full width, connecting by itself (no VNC client, no extra clicks).
- **Clean frame**: black around the screen instead of noVNC's grey bars, no card outline, small top margin.
- **Safe defaults**: the VNC port only listens on localhost; only the noVNC web port is exposed, behind the VNC
  password (and Cloudflare Access or a secret path, if you publish it).
- **Several desktops**: a connector in Home Assistant adds any VNC server on your network (name, IP, port, optional
  password); each one shows up in the viewer with its own collapse button and "open in a tab".
- **Survives reboots**: systemd services restart x11vnc until the desktop session is up.

## How it works

```
HA dashboard iframe ──▶ vnc-control-multi.html :6080 ──▶ one noVNC frame per session
                         websockify (token mode) ─────▶ token "pi"     → x11vnc 127.0.0.1:5900 (this screen)
                                                  └───▶ token "office" → any VNC server on the LAN, e.g. 10.0.0.5:5900
HA connector ──REST──▶ vnc_control.py :8093 ──▶ writes the token files + vnc-sessions.json the viewer reads
optional: Cloudflare tunnel ──▶ https://desktop.example.com/<path-key>/vnc-control-multi.html
```

websockify runs with `--token-plugin TokenFile`: the page connects to `websockify?token=<name>` and websockify
forwards to the host:port in `/etc/vnc-control/tokens/<name>`. The viewer re-reads the session list every 5 s, so
sessions added from Home Assistant appear without reloading the dashboard. An open session keeps its controls in a
narrow strip on the right, so the screen keeps the full height; a collapsed one closes its connection.

`vnc-control.html` is noVNC's own `vnc.html` with one added style. noVNC's code paints the area around a scaled
screen grey (an inline `rgb(40, 40, 40)`), which shows as bars whenever the frame's shape differs from the screen's.
It is a separate page on purpose: browsers cache `vnc.html`, so editing it in place may never reach them.

## Install

On the machine whose screen you want (Debian, Ubuntu or Raspberry Pi OS, X11 session):

```sh
git clone https://github.com/mauriporte/ha-vnc-control && cd ha-vnc-control/linux
sudo ./install.sh <desktop-user> [port] [path-key]
```

It installs x11vnc, noVNC and websockify, asks for the VNC password (only the first 8 characters count, a VNC
limit), creates the two services and the page, and prints the URL.

**Autologin.** x11vnc needs a running desktop session; on the login screen it cannot attach and keeps retrying. Turn
on autologin, for LightDM with `/etc/lightdm/lightdm.conf.d/50-autologin.conf`:

```ini
[Seat:*]
autologin-user=<desktop-user>
autologin-user-timeout=0
autologin-session=cinnamon
```

The section must be `[Seat:*]`: the same lines under `[LightDM]` are silently ignored (LightDM's log says
"unknown option"). Use your session's name from `/usr/share/xsessions/`.

## Home Assistant

1. Connector: merge [`examples/home-assistant.yaml`](examples/home-assistant.yaml) (two `rest_command`s, two scripts,
   the helpers it lists) and put the API token install.sh printed in `secrets.yaml` as `vnc_control_token`.
2. Copy [`examples/themes/vnc_control.yaml`](examples/themes/vnc_control.yaml) to `/config/themes/` and call
   `frontend.reload_themes`.
3. Add the view from [`examples/dashboard-view.yaml`](examples/dashboard-view.yaml) with your URL. Notes:
   - Sections views ignore the iframe's `aspect_ratio`; the frame's height is `rows`. Pick the largest value that
     does not make the page scroll (15 fits a 1024×600 screen on a 1080p monitor).
   - A session's VNC password (optional) is passed to noVNC, so it connects without asking. The list the viewer reads
     includes it: anyone who can open the viewer page can read it. Use VNC passwords you do not use anywhere else.
   - With `reconnect=1` noVNC reconnects by itself after a reboot of the machine.

## Outside your home (optional): Cloudflare tunnel

Add a public hostname in your tunnel pointing to `http://<machine-ip>:6080`. Put the hostname behind **Cloudflare
Access** (login with a one-time code). An Access login page cannot be shown inside a Home Assistant iframe
("refused to connect"), so for the dashboard:

1. Run `install.sh` with a `path-key` (a long random string), which serves the page under `/<path-key>/` too.
2. Create a second Access application for `desktop.example.com/<path-key>` with a **Bypass** policy. The more
   specific path wins: the root keeps asking for the code, the key path opens directly.
3. Use `https://desktop.example.com/<path-key>/vnc-control.html?autoconnect=1&resize=scale&reconnect=1&show_dot=1`
   in the view. The key works like a password: anyone who has the URL gets the noVNC page (the VNC password still
   applies unless it is in the URL).

Cloudflare caches `.css`/`.js` files: after changing noVNC files, purge them in the dashboard (Caching → Purge) or
the browser may keep the old look.

## Tips

- Grey bars on the sides: the frame's shape differs from the screen's. Use `vnc-control.html` (black instead of grey),
  match the iframe's height (`rows`) to your screen, and set the card border to black (the theme does it).
- Desktop icons on a Cinnamon/Nemo desktop keep their positions per resolution; after changing the resolution,
  check the ones near the edges.
- x11vnc only shares X11. On Wayland sessions use the desktop's own remote desktop (GNOME, KDE) instead.

## License

MIT
