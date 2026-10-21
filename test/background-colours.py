#!/usr/bin/env python3
"""Check real OSC 11 replies in an isolated tmux server without clients."""

import json
import os
from pathlib import Path
import re
import select
import shlex
import subprocess
import sys
import tempfile
import termios
import time
import tty


def probe(output):
    original = termios.tcgetattr(0)
    data = bytearray()
    try:
        tty.setraw(0)
        os.write(1, b"\x1b]11;?\x07")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if select.select([0], [], [], 0.1)[0]:
                data.extend(os.read(0, 4096))
                if re.search(rb"rgb:[0-9a-fA-F/]+", data):
                    break
    finally:
        termios.tcsetattr(0, termios.TCSANOW, original)
    Path(output).write_text(json.dumps(data.decode(errors="replace")))


def main():
    socket = f"adaptive-background-{os.getpid()}"
    script = Path(__file__).resolve()
    repo = script.parent.parent

    with tempfile.TemporaryDirectory() as directory:
        env = dict(os.environ, XDG_STATE_HOME=str(Path(directory) / "state"))
        env.pop("TMUX", None)
        env.pop("TMUX_PANE", None)

        def tmux(*args):
            return subprocess.check_output(["tmux", "-L", socket, *args], env=env, text=True)

        try:
            tmux("-f", "/dev/null", "new-session", "-d", "-s", "test")
            for mode, expected in (("dark", "2828/2c2c/3434"), ("light", "fafa/fafa/fafa")):
                tmux("set-option", "-g", "@adaptive_appearance", mode)
                tmux("run-shell", shlex.quote(str(repo / "tmux-adaptive-theme.tmux")))
                output = Path(directory) / mode
                command = shlex.join([sys.executable, str(script), "--probe", str(output)])
                tmux("new-window", "-d", "-t", "test", command)
                deadline = time.monotonic() + 5
                while not output.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                reply = json.loads(output.read_text())
                assert f"rgb:{expected}" in reply, (mode, reply)
                print(f"{mode} OSC 11 background: ok")
        finally:
            subprocess.run(["tmux", "-L", socket, "kill-server"], env=env, check=False)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--probe":
        probe(sys.argv[2])
    else:
        main()
