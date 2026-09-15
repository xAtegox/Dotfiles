#!/usr/bin/env python3
"""wmmp-qmmp-bridge.py -- fake MPD server that drives qmmp via playerctl/MPRIS.

WMmp is an MPD dockapp. This bridge speaks just enough of the MPD protocol
that WMmp actually uses, and translates it to qmmp's MPRIS2 D-Bus interface
(org.mpris.MediaPlayer2.qmmp), so WMmp's controls and display drive qmmp
instead of a real MPD server.  Same idea as ~/.config/doom/lisp/qmmp-mpris.el.

Backend is `playerctl` (not python-dbus): every interaction is a short-lived
subprocess with a hard timeout, so a dead/slow/starting qmmp can never wedge
or kill the bridge.  WMmp's `status`/`playlistinfo` are answered instantly
from a cache refreshed by a background worker; transport commands are
acknowledged immediately and applied by the worker.

Usage:
  wmmp-qmmp-bridge.py [port]          (default: 6601)

Then run WMmp pointing at the bridge:
  MPD_HOST=127.0.0.1 MPD_PORT=6601 WMmp

Requires `playerctl` and qmmp (MPRIS plugin enabled).
Set WMMP_BRIDGE_DEBUG=1 to log every command to stderr.
"""

import os
import queue
import re
import socket
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse

HOST = "127.0.0.1"
DEFAULT_PORT = int(os.environ.get("WMMP_BRIDGE_PORT", "6601"))
WELCOME = b"OK MPD 0.23.4\n"
PLAYER = "qmmp"
POLL_INTERVAL = 0.5          # s between snapshot refreshes
PENDING_DEADLINE = 8.0       # s a queued command may wait for qmmp to start
CMD_TIMEOUT = 2              # s cap on every playerctl call
DEBUG = os.environ.get("WMMP_BRIDGE_DEBUG") == "1"

SEP = "\x1f"
META_FORMAT = ("S=" + SEP + "{{status}}" + SEP + "A=" + SEP + "{{artist}}" + SEP
               + "T=" + SEP + "{{title}}" + SEP + "L=" + SEP + "{{mpris:length}}"
               + SEP + "V=" + SEP + "{{volume}}"
               + SEP + "U=" + SEP + "{{url}}")


class QmmpBackend:
    def __init__(self):
        self._lock = threading.Lock()
        self._cmdq = queue.Queue()
        self._pending = queue.Queue()
        self._cache = {
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
        self._stopped = False
        self._spawned = False
        self._spawned_at = 0.0
        threading.Thread(target=self._worker, daemon=True).start()

    # ----- called from WMmp socket threads -----

    def submit(self, line):
        self._cmdq.put(line)

    def snapshot(self):
        with self._lock:
            return dict(self._cache)

    # ----- playerctl helpers (bounded subprocesses) -----

    @staticmethod
    def _run(args, timeout=CMD_TIMEOUT):
        try:
            r = subprocess.run(
                ["playerctl", "--player=" + PLAYER] + args,
                capture_output=True, text=True, timeout=timeout)
            return r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            return ""

    def _available(self):
        return bool(self._run(["status"]))

    def _spawn_qmmp(self):
        now = time.time()
        if self._spawned and now - self._spawned_at < 10:
            return
        self._spawned = True
        self._spawned_at = now
        try:
            subprocess.Popen(["qmmp"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    # ----- worker (single thread; all playerctl + qmmp cli calls here) -----

    def _worker(self):
        key = None
        version = 0
        song = 0
        plen = 1
        last_file = ""
        while not self._stopped:
            try:
                while True:
                    try:
                        line = self._cmdq.get_nowait()
                    except queue.Empty:
                        break
                    self._exec_command(line)
                available, key, version, song, plen, last_file = self._refresh(
                    key, version, song, plen, last_file)
                if available:
                    drained = []
                    while True:
                        try:
                            drained.append(self._pending.get_nowait())
                        except queue.Empty:
                            break
                    for line, deadline in drained:
                        if time.time() >= deadline:
                            continue
                        applied = self._exec_command(line, deadline)
                        if not applied and time.time() < deadline:
                            self._pending.put((line, deadline))
            except Exception:
                traceback.print_exc()
            time.sleep(POLL_INTERVAL)

    def _exec_command(self, line, deadline=None):
        if DEBUG:
            print("CMD: %s" % line, flush=True)
        parts = line.split()
        if not parts:
            return
        name = parts[0].lower()
        args = [a.strip('"') for a in parts[1:]]
        if name in ("status", "playlistinfo", "ping", "password"):
            return
        if not self._available():
            if deadline is not None:
                return False
            self._spawn_qmmp()
            self._pending.put((line, time.time() + PENDING_DEADLINE))
            return True
        try:
            if name == "play":
                self._run(["play"])
            elif name == "pause":
                self._run(["play-pause"])
            elif name == "stop":
                self._run(["stop"])
            elif name == "next":
                self._run(["next"])
            elif name == "previous":
                self._run(["previous"])
            elif name == "seek" and len(args) >= 2 and args[1]:
                self._run(["position", str(int(float(args[1])))])
            elif name == "repeat":
                loop = "Playlist" if args and args[0] == "1" else "None"
                self._run(["loop", loop])
            elif name == "random":
                # shuffle is intentionally disabled: qmmp segfaults at startup
                # when it saves `shuffle=true` in its config, so we never touch
                # qmmp's Shuffle property.
                pass
            elif name == "setvol" and args:
                v = max(0, min(100, int(float(args[0]))))
                self._run(["volume", "%.2f" % (v / 100.0)])
        except Exception:
            pass
        return True

    def _refresh(self, key, version, song, plen, last_file):
        status = self._run(["status"])
        if not status:
            with self._lock:
                self._cache["state"] = "stop"
                self._cache["elapsed"] = 0
            return False, key, version, song, plen, last_file
        meta = self._run(["metadata", "--format", META_FORMAT])
        fields = {}
        if meta:
            tokens = meta.split(SEP)
            for i in range(0, len(tokens) - 1, 2):
                fields[tokens[i].rstrip("=")] = tokens[i + 1]

        title = fields.get("T") or self._cache["title"]
        artist = fields.get("A") or self._cache["artist"]
        fpath = self._filepath(fields.get("U") or "") or title
        try:
            total = int(float(fields.get("L") or 0)) // 1000000
        except (TypeError, ValueError):
            total = self._cache["total"]
        try:
            volume = max(0, min(100, int(round(float(fields.get("V") or 0) * 100))))
        except (TypeError, ValueError):
            volume = self._cache["volume"]
        pos_s = self._run(["position"])
        try:
            elapsed = max(0, int(float(pos_s))) if pos_s else 0
        except (TypeError, ValueError):
            elapsed = 0
        loop = self._run(["loop"]) or self._cache["loop"]
        shuf = self._run(["shuffle"])
        shuffle = shuf == "On" if shuf else self._cache["shuffle"]

        nkey = (title, artist)
        if nkey != key:
            key = nkey
            version += 1
            song, plen = self._compute_song()
            last_file = fpath

        if status == "Playing":
            st = "play"
        elif status == "Paused":
            st = "pause"
        else:
            st = "stop"
        cur = {
            "state": st,
            "volume": volume,
            "loop": loop or "None",
            "shuffle": shuffle,
            "elapsed": elapsed,
            "total": total,
            "song": song,
            "version": version,
            "plen": max(plen, song + 1),
            "artist": artist,
            "title": title,
            "file": last_file,
        }
        with self._lock:
            self._cache.update(cur)
        return True, key, version, song, plen, last_file

    @staticmethod
    def _filepath(url):
        if not url:
            return ""
        if url.startswith("file://"):
            return urllib.parse.unquote(urllib.parse.urlparse(url).path)
        return url

    @staticmethod
    def _run_qmmp_cli(args, timeout=3):
        try:
            r = subprocess.run(["qmmp"] + args, capture_output=True,
                               text=True, timeout=timeout)
            return r.stdout or ""
        except Exception:
            return ""

    def _compute_song(self):
        try:
            out = self._run_qmmp_cli(["--pl-list"])
            pid = None
            for line in out.splitlines():
                if line.startswith(">"):
                    m = re.match(r">\s*(\d+)", line)
                    if m:
                        pid = m.group(1)
                        break
            if pid is None:
                return 0, 1
            dump = self._run_qmmp_cli(["--pl-dump", pid])
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


def status_response(s):
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


def songinfo_response(s):
    lines = ["file: %s" % s["file"]]
    if s["artist"]:
        lines.append("Artist: %s" % s["artist"])
    if s["title"]:
        lines.append("Title: %s" % s["title"])
    return "\n".join(lines) + "\nOK\n"


def respond(backend, line):
    parts = line.split()
    if not parts:
        return ""
    name = parts[0].lower()
    if name == "status":
        return status_response(backend.snapshot())
    if name == "playlistinfo":
        return songinfo_response(backend.snapshot())
    if name in ("ping", "password"):
        return "OK\n"
    backend.submit(line)
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
                    resp = "".join(respond(backend, c) for c in buf)
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
            resp = respond(backend, line)
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
            try:
                conn, _ = srv.accept()
            except OSError:
                time.sleep(0.1)
                continue
            threading.Thread(target=handle, args=(conn, backend),
                             daemon=True).start()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()