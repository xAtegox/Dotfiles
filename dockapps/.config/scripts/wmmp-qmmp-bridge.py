#!/usr/bin/env python3
"""wmmp-qmmp-bridge.py -- fake MPD server that drives qmmp via MPRIS D-Bus.

WMmp is an MPD dockapp. This bridge speaks just enough of the MPD protocol
that WMmp actually uses, and translates it to qmmp's MPRIS2 D-Bus interface
(org.mpris.MediaPlayer2.qmmp), so WMmp's controls and display drive qmmp
instead of a real MPD server.  Same idea as ~/.config/doom/lisp/qmmp-mpris.el.

Usage:
  wmmp-qmmp-bridge.py [port]          (default: 6601)

Then run WMmp pointing at the bridge:
  MPD_HOST=127.0.0.1 MPD_PORT=6601 WMmp

Requires python3 with the `dbus` module and qmmp running with its MPRIS
plugin enabled.
"""

import dbus
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.parse

HOST = "127.0.0.1"
DEFAULT_PORT = int(os.environ.get("WMMP_BRIDGE_PORT", "6601"))
SERVICE = "org.mpris.MediaPlayer2.qmmp"
OBJ_PATH = "/org/mpris/MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
WELCOME = b"OK MPD 0.23.4\n"


class QmmpBackend:
    def __init__(self):
        self._lock = threading.Lock()
        self.bus = None
        self.obj = None
        self.player = None
        self.props = None
        self._key = None
        self._version = 0
        self._song = 0
        self._plen = 1
        self._last_file = ""
        self._last_known = {
            "state": "stop",
            "volume": 60,
            "loop": "None",
            "shuffle": False,
            "elapsed": 0,
            "total": 0,
            "song": 0,
            "version": 0,
            "plen": 1,
            "artist": "",
            "title": "",
            "file": "",
        }

    def _connect(self):
        self.bus = dbus.SessionBus()
        self.obj = self.bus.get_object(SERVICE, OBJ_PATH)
        self.player = dbus.Interface(self.obj, PLAYER_IFACE)
        self.props = dbus.Interface(self.obj, PROPS_IFACE)

    def available(self):
        try:
            if self.bus is None:
                self._connect()
            return SERVICE in self.bus.list_names()
        except Exception:
            return False

    @staticmethod
    def _run_cli(args, timeout=3):
        try:
            r = subprocess.run(["qmmp"] + args, capture_output=True,
                               text=True, timeout=timeout)
            return r.stdout or ""
        except Exception:
            return ""

    @staticmethod
    def _artist(md):
        a = md.get("xesam:artist")
        if not a:
            return ""
        try:
            return ", ".join(str(x) for x in a)
        except TypeError:
            return str(a)

    @staticmethod
    def _filepath(url):
        if not url:
            return ""
        if url.startswith("file://"):
            return urllib.parse.unquote(urllib.parse.urlparse(url).path)
        return url

    def _compute_song(self):
        try:
            out = self._run_cli(["--pl-list"])
            pid = None
            for line in out.splitlines():
                if line.startswith(">"):
                    m = re.match(r">\s*(\d+)", line)
                    if m:
                        pid = m.group(1)
                        break
            if pid is None:
                return 0, 1
            dump = self._run_cli(["--pl-dump", pid])
            pos, count = 0, 0
            for line in dump.splitlines():
                m = re.match(r">?\s*(\d+)\.", line)
                if not m:
                    continue
                count += 1
                if line.startswith(">"):
                    pos = int(m.group(1)) - 1
            return max(pos, 0), max(count, 1)
        except Exception:
            return 0, 1

    def snapshot(self):
        with self._lock:
            last = dict(self._last_known)
            if not self.available():
                return last
            try:
                allp = self.props.GetAll(PLAYER_IFACE)
            except Exception:
                return last
            md = allp.get("Metadata") or {}
            state = str(allp.get("PlaybackStatus") or "Stopped")
            loop = str(allp.get("LoopStatus") or "None")
            shuffle = bool(allp.get("Shuffle"))
            volume = int(round(float(allp.get("Volume") or 0) * 100))
            volume = max(0, min(100, volume))
            pos_us = int(allp.get("Position") or 0)
            length_us = int(md.get("mpris:length") or 0)
            title = str(md.get("xesam:title") or "")
            artist = self._artist(md)
            url = str(md.get("xesam:url") or "")
            fpath = self._filepath(url) or title

            key = (url, title)
            if key != self._key:
                self._key = key
                self._version += 1
                self._song, self._plen = self._compute_song()
                self._last_file = fpath

            if state == "Playing":
                st = "play"
            elif state == "Paused":
                st = "pause"
            else:
                st = "stop"
            cur = {
                "state": st,
                "volume": volume,
                "loop": loop,
                "shuffle": shuffle,
                "elapsed": pos_us // 1000000,
                "total": length_us // 1000000,
                "song": self._song,
                "version": self._version,
                "plen": max(self._plen, self._song + 1),
                "artist": artist,
                "title": title,
                "file": self._last_file,
            }
            self._last_known = cur
            return cur

    def _status_response(self):
        s = self.snapshot()
        t = "%d:%d" % (s["elapsed"], s["total"])
        return "\n".join([
            "volume: %d" % s["volume"],
            "repeat: %d" % (1 if s["loop"] in ("Track", "Playlist") else 0),
            "random: %d" % (1 if s["shuffle"] else 0),
            "playlist: %d" % s["version"],
            "playlistlength: %d" % s["plen"],
            "state: %s" % s["state"],
            "song: %d" % s["song"],
            "time: %s" % t,
        ]) + "\nOK\n"

    def _songinfo_response(self):
        s = self.snapshot()
        lines = ["file: %s" % s["file"]]
        if s["artist"]:
            lines.append("Artist: %s" % s["artist"])
        if s["title"]:
            lines.append("Title: %s" % s["title"])
        return "\n".join(lines) + "\nOK\n"

    def _ensure_running(self, wait=6.0):
        if self.available():
            return
        subprocess.Popen(["qmmp"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + wait
        while time.time() < deadline:
            time.sleep(0.2)
            if self.available():
                return

    def _seek_to(self, target_sec):
        try:
            pos = int(self.props.Get(PLAYER_IFACE, "Position") or 0)
        except Exception:
            pos = 0
        self.player.Seek(dbus.Int64(int(target_sec * 1000000 - pos)))

    def dispatch(self, line):
        parts = line.split()
        if not parts:
            return ""
        name = parts[0].lower()
        args = [a.strip('"') for a in parts[1:]]
        try:
            if name == "status":
                return self._status_response()
            if name == "playlistinfo":
                return self._songinfo_response()
            if name in ("ping", "password"):
                return "OK\n"
            if name == "play":
                self._ensure_running()
                self.player.Play()
            elif name == "pause":
                self._ensure_running()
                self.player.PlayPause()
            elif name == "stop":
                self._ensure_running()
                self.player.Stop()
            elif name == "next":
                self._ensure_running()
                self.player.Next()
            elif name == "previous":
                self._ensure_running()
                self.player.Previous()
            elif name == "seek":
                self._ensure_running()
                if len(args) >= 2 and args[1]:
                    self._seek_to(int(float(args[1])))
            elif name == "repeat":
                self._ensure_running()
                loop = "Playlist" if args and args[0] == "1" else "None"
                self.props.Set(PLAYER_IFACE, "LoopStatus", dbus.String(loop))
            elif name == "random":
                self._ensure_running()
                on = bool(args and args[0] == "1")
                self.props.Set(PLAYER_IFACE, "Shuffle", dbus.Boolean(on))
            elif name == "setvol":
                self._ensure_running()
                if args:
                    v = max(0, min(100, int(float(args[0]))))
                    self.props.Set(PLAYER_IFACE, "Volume", dbus.Double(v / 100.0))
            return "OK\n"
        except Exception:
            return "OK\n"


def handle(conn, backend):
    conn.settimeout(60)
    f = conn.makefile("rwb")
    try:
        f.write(WELCOME)
        f.flush()
        buf = None
        while True:
            raw = f.readline()
            if not raw:
                break
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            if buf is not None:
                if line == "command_list_end":
                    resp = "".join(backend.dispatch(c) for c in buf)
                    f.write(resp.encode())
                    f.flush()
                    buf = None
                else:
                    buf.append(line)
                continue
            if line == "command_list_begin":
                buf = []
                continue
            if line == "close":
                break
            resp = backend.dispatch(line)
            if resp:
                f.write(resp.encode())
                f.flush()
    except (BrokenPipeError, ConnectionError, OSError):
        pass
    finally:
        try:
            f.close()
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    backend = QmmpBackend()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, port))
    srv.listen(4)
    print("wmmp-qmmp bridge listening on %s:%d" % (HOST, port), flush=True)
    try:
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=handle, args=(conn, backend), daemon=True).start()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()