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
- **Survives reboots**: systemd services restart x11vnc until the desktop session is up.

## How it works

```
HA dashboard iframe ──▶ noVNC page :6080 (websockify) ──▶ x11vnc 127.0.0.1:5900 ──▶ X display :0 (the real screen)
                         └─ optional: Cloudflare tunnel ─▶ https://desktop.example.com/<path-key>/vnc-control.html
```

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

1. Copy [`examples/themes/vnc_control.yaml`](examples/themes/vnc_control.yaml) to `/config/themes/` and call
   `frontend.reload_themes`.
2. Add the view from [`examples/dashboard-view.yaml`](examples/dashboard-view.yaml) with your URL. Notes:
   - Sections views ignore the iframe's `aspect_ratio`; the frame's height is `rows`. Pick the largest value that
     does not make the page scroll (15 fits a 1024×600 screen on a 1080p monitor).
   - `password=` in the URL connects without asking. Leave it out to type the password, or use a VNC password you do
     not use anywhere else, since the URL is stored in the dashboard configuration.
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
