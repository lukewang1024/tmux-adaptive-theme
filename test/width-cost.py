#!/usr/bin/env python3
"""Guard linear tab rendering with realistic controls and independent clients."""
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import statistics
import struct
import subprocess
import tempfile
import termios
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='adaptive-cost-') as directory:
    socket = directory + '/socket'
    env = dict(os.environ, TERM='xterm-256color', XDG_STATE_HOME=directory + '/state')
    env.pop('TMUX', None)
    env.pop('TMUX_PANE', None)
    clients, fds, masters = [], [], []
    def tmux(*args):
        return subprocess.check_output(['tmux', '-S', socket, *args], env=env,
                                       text=True, timeout=5).strip()
    def drain():
        for master in masters:
            while select.select([master], [], [], 0)[0]:
                os.read(master, 65536)
    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'performance', '-n', 'first')
        for key, value in (
            ('@adaptive_time_enabled', 'on'), ('@adaptive_time_format', '12:34'),
            ('@adaptive_date_enabled', 'on'), ('@adaptive_date_format', '10/23'),
            ('@adaptive_battery_enabled', 'on'), ('@adaptive_battery', 'BAT84'),
            ('@adaptive_cpu', 'CPU42 MEM56'), ('@adaptive_cpu_compact', 'CPU42'),
            ('@adaptive_context_state', '#{@test_agent_state}'),
            ('@adaptive_context_label', 'CODING AGENT'),
            ('@adaptive_context_suffix', 'QUOTA73'),
            ('@adaptive_host_icon', 'HOST'),
        ):
            tmux('set', '-g', key, value)
        for slot in (1, 2, 3):
            tmux('set', '-g', f'@adaptive_action_{slot}_icon', str(slot))
        tmux('set', '-w', '@test_agent_state', 'working')
        tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))

        # A tab is not allowed to inspect global name demand, directly or via
        # another option. This is the complexity contract, independent of CPU.
        pending = ['window-status-format', 'window-status-current-format']
        visited = set()
        while pending:
            option = pending.pop()
            if option in visited:
                continue
            visited.add(option)
            template = tmux('show-option', '-gqv', option)
            assert '#{W:' not in template, ('tab performs a nested window scan', option)
            pending.extend(re.findall(r'#\{[ET]:([@A-Za-z0-9_-]+)\}', template))

        for width in (46, 211):
            master, slave = pty.openpty()
            masters.append(master)
            fds.extend([master, slave])
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, width, 0, 0))
            clients.append(subprocess.Popen(['tmux', '-S', socket, 'attach', '-t', 'performance'],
                stdin=slave, stdout=slave, stderr=slave, env=env))
        time.sleep(.1)
        drain()
        observations = []
        for count in (4, 12, 40):
            while len(tmux('list-windows', '-F', '#{window_id}').splitlines()) < count:
                tmux('new-window', '-d', '-n', '修复布局和状态栏 responsive window')
                drain()
            # Identical renders should remain fast at phone and desktop widths.
            for row in tmux('list-clients', '-F', '#{client_name} #{client_width}').splitlines():
                name, width = row.split()
                samples = []
                for _ in range(3):
                    drain()
                    started = time.monotonic()
                    rendered = tmux('display', '-p', '-c', name, '#{W:#{E:window-status-format}}')
                    samples.append(time.monotonic() - started)
                    assert rendered, (count, width)
                elapsed = statistics.median(samples)
                assert elapsed < .5, ('tab render exceeded 500 ms budget', count, width, samples)
                observations.append((count, int(width), round(elapsed * 1000, 2)))
        print('PASS constant-cost tab dependencies; 4/12/40 windows at phone/desktop widths')
        print('windows, client width, median render ms:', observations)
    finally:
        subprocess.run(['tmux', '-S', socket, 'kill-server'], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        for client in clients:
            client.wait(timeout=5)
        for fd in fds:
            os.close(fd)
