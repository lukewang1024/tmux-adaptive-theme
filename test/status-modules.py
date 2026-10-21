#!/usr/bin/env python3
"""Optional modules stay explicit across density changes, reloads and producers."""
import fcntl
import itertools
import os
from pathlib import Path
import pty
import select
import shlex
import signal
import struct
import subprocess
import tempfile
import termios
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='adaptive-modules-') as directory:
    root = Path(directory)
    socket = str(root / 'socket')
    env = dict(os.environ, TERM='xterm-256color', XDG_STATE_HOME=str(root / 'state'))
    env.pop('TMUX', None)
    env.pop('TMUX_PANE', None)
    master, slave = pty.openpty()
    client = None

    def tmux(*args):
        return subprocess.check_output(['tmux', '-S', socket, *args], env=env, text=True).strip()

    def option(name, value):
        tmux('set', '-g', name, value)

    def apply():
        tmux('run-shell', shlex.quote(str(repo / 'tmux-adaptive-theme.tmux')))

    def drain(seconds=.2):
        deadline = time.monotonic() + seconds
        data = b''
        while time.monotonic() < deadline:
            if select.select([master], [], [], .02)[0]:
                data += os.read(master, 65536)
        return data

    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'test', '-n', 'one', '/bin/sh')
        for field in ('time', 'date'):
            option(f'@adaptive_{field}_format', field.upper())
        option('@adaptive_battery', 'BATTERY')
        # Old persisted thresholds cannot override explicit switches.
        for field in ('time', 'date', 'battery'):
            option(f'@adaptive_{field}_min_width', '9999')
        apply()
        for density in ('full', 'compact'):
            rendered = tmux('display', '-p', f'#{{T:@adaptive_{density}_right}}')
            assert not any(word in rendered for word in ('TIME', 'DATE', 'BATTERY')), rendered

        for enabled in itertools.product((False, True), repeat=3):
            for field, on in zip(('time', 'date', 'battery'), enabled):
                option(f'@adaptive_{field}_enabled', 'on' if on else 'off')
            apply()
            for density in ('full', 'compact'):
                rendered = tmux('display', '-p', f'#{{T:@adaptive_{density}_right}}')
                assert tuple(word in rendered for word in ('TIME', 'DATE', 'BATTERY')) == enabled, rendered

        # With all modules enabled, actual client pressure must not hide them.
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 160, 0, 0))
        client = subprocess.Popen(['tmux', '-S', socket, 'attach'], env=env,
                                  stdin=slave, stdout=slave, stderr=slave)
        drain()
        name = tmux('list-clients', '-F', '#{client_name}')
        assert tmux('display', '-p', '-c', name, '#{E:@adaptive_controls_full}') == '1'
        tmux('new-window', '-d', '-n', 'a long window name to force compact controls', '/bin/sh')
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        client.send_signal(signal.SIGWINCH)
        drain()
        assert tmux('display', '-p', '-c', name, '#{E:@adaptive_controls_full}') == '0'
        rendered = tmux('display', '-p', '-c', name, '#{T:status-right}')
        assert all(word in rendered for word in ('TIME', 'DATE', 'BATTERY')), rendered

        # A disabled module must not launch its producer, even inside width probes.
        marker = root / 'producer-ran'
        option('@adaptive_battery_enabled', 'off')
        option('@adaptive_battery', '#(touch ' + shlex.quote(str(marker)) + '; printf BATTERY42)')
        apply()
        drain(1.2)
        assert not marker.exists(), 'disabled battery started its producer'
        rendered = tmux('display', '-p', '#{T:@adaptive_compact_right}')
        option('@adaptive_battery', '')
        option('@adaptive_battery_enabled', 'on')
        apply()
        assert tmux('display', '-p', '#{T:@adaptive_compact_right}') == rendered, 'empty module left a separator'
        option('@adaptive_battery', '#(touch ' + shlex.quote(str(marker)) + '; printf BATTERY42)')
        apply()
        output = b''
        deadline = time.monotonic() + 8
        while b'BATTERY42' not in output:
            assert time.monotonic() < deadline, 'enabled producer never appeared'
            output += drain()
        assert marker.exists()
        print('PASS all module combinations, default off, stale thresholds, compact layouts, reloads and async producers')
    finally:
        subprocess.run(['tmux', '-S', socket, 'kill-server'], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            if client:
                try:
                    client.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    client.terminate()
                    client.wait(timeout=5)
        finally:
            os.close(master)
            os.close(slave)
