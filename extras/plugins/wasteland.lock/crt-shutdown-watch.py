#!/usr/bin/python3
"""CRT tube-TV power-off before a shutdown or reboot (Nov 15, 2026).

Started by Service.qml in the wasteland.lock plugin while crtEnabled is true.
Holds a logind *delay* inhibitor (never a block lock). When logind announces
a shutdown or reboot (PrepareForShutdown true) it asks the shell to play the
CRT power-off, then releases the lock ~0.7 s later so the shutdown carries on.
It never waits on the shell, and logind itself proceeds after
InhibitDelayMaxSec no matter what. Exits with the shell (PDEATHSIG).

  --test   play the power-off now and release, without any shutdown
"""

import ctypes
import os
import signal
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

RELEASE_MS = 700
LOGIN1 = ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")

try:
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
except Exception:
    pass

lock_fd = None
bus = None


def log(msg):
    print("crt-shutdown-watch: " + msg, file=sys.stderr, flush=True)


def take_lock():
    global lock_fd
    if lock_fd is not None:
        return
    try:
        res, fdlist = bus.call_with_unix_fd_list_sync(
            LOGIN1[0], LOGIN1[1], LOGIN1[2], "Inhibit",
            GLib.Variant("(ssss)", ("shutdown", "CRT power-off", "Tube-TV power-off animation", "delay")),
            GLib.VariantType("(h)"), Gio.DBusCallFlags.NONE, 3000, None, None)
        lock_fd = fdlist.get(res.unpack()[0])
        del fdlist
    except Exception as e:
        log("no delay lock: %s" % e)


def release_lock():
    global lock_fd
    if lock_fd is not None:
        try:
            os.close(lock_fd)
        except OSError:
            pass
        lock_fd = None
    return False


def play_off():
    try:
        subprocess.Popen(["omarchy-shell", "-q", "lock", "crtOff"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception as e:
        log("crtOff failed: %s" % e)
    GLib.timeout_add(RELEASE_MS, release_lock)


def on_prepare(_conn, _sender, _path, _iface, _name, params, *_):
    starting = params.unpack()[0]
    if starting:
        play_off()
    else:
        # The shutdown was cancelled: give the screen back and take the lock
        # again for next time.
        try:
            subprocess.Popen(["omarchy-shell", "-q", "lock", "crtCancel"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception:
            pass
        take_lock()


def main():
    global bus
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    loop = GLib.MainLoop()
    # SIGTERM keeps its default action: the process ends and the kernel
    # closes the inhibitor fd, which releases the lock.
    bus.signal_subscribe(LOGIN1[0], LOGIN1[2], "PrepareForShutdown", LOGIN1[1], None,
                         Gio.DBusSignalFlags.NONE, on_prepare)
    take_lock()
    if "--test" in sys.argv:
        log("test: lock held=%s" % (lock_fd is not None))
        play_off()
        GLib.timeout_add(RELEASE_MS + 100, lambda: (loop.quit(), False)[1])
    loop.run()
    release_lock()
    return 0


if __name__ == "__main__":
    sys.exit(main())
