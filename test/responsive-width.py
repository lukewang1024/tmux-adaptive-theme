#!/usr/bin/env python3
"""Test width pressure with actual window names and independently sized clients."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='adaptive-width-') as directory:
    socket = directory + '/socket'
    env = dict(os.environ, TERM='xterm-256color', XDG_STATE_HOME=str(Path(directory) / 'state'))
    env.pop('TMUX', None)
    env.pop('TMUX_PANE', None)
    def tmux(*args):
        return subprocess.check_output(['tmux', '-S', socket, *args], env=env, text=True).strip()
    master, slave = pty.openpty()
    client = None
    def drain():
        deadline = time.monotonic() + .15
        while time.monotonic() < deadline:
            if select.select([master], [], [], .01)[0]:
                os.read(master, 65536)
    def resize(width):
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, width, 0, 0))
        os.kill(client.pid, signal.SIGWINCH)
        for _ in range(30):
            drain()
            if tmux('display', '-p', '-c', name, '#{client_width}') == str(width):
                return
        raise AssertionError('client did not resize')
    def value(fmt):
        return tmux('display', '-p', '-c', name, fmt)
    try:
        tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'long-session-name', '-n', 'one')
        for key, value_ in (('@adaptive_time_enabled', 'off'), ('@adaptive_date_enabled', 'off'), ('@adaptive_cpu', 'CPU42 MEM56'), ('@adaptive_cpu_compact', 'CPU42'), ('@adaptive_context_state', '#{@test_agent_state}'), ('@adaptive_context_label', 'CODING AGENT'), ('@adaptive_context_suffix', 'QUOTA73')):
            tmux('set', '-g', key, value_)
        tmux('set', '-w', '@test_agent_state', 'working')
        tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 130, 0, 0))
        client = subprocess.Popen(['tmux', '-S', socket, 'attach'], stdin=slave, stdout=slave, stderr=slave, env=env)
        drain()
        name = tmux('list-clients', '-F', '#{client_name}')
        assert value('#{E:@adaptive_controls_full}') == '1'
        # Same client width, greater tab demand: fixed controls compact first.
        for index, title in enumerate(('investigate responsive layout', '修复侧边栏状态和窗口标签', 'test unicode width handling'), 1):
            tmux('new-window', '-d', '-n', title)
        assert value('#{E:@adaptive_controls_full}') == '0'
        observations = []
        for width in (240, 180, 130, 110, 90, 70, 50):
            resize(width)
            full = value('#{E:@adaptive_controls_full}')
            labels_full = value('#{E:@adaptive_tabs_full}')
            limit = int(value('#{E:@adaptive_tab_name_limit}'))
            left = int(value('#{w:#{T:status-left}}'))
            right = int(value('#{w:#{T:status-right}}'))
            tabs = int(value('#{w:#{W:#{E:window-status-format}}}'))
            assert value('#{W:#{E:@adaptive_controls_full}}') == full * 4
            observations.append((width, full, labels_full, limit, left, right, tabs))
            if width >= 70:
                assert left + right + tabs <= width, observations
            rendered = value('#{E:status-right}')
            if full == '0':
                assert 'QUOTA73' not in rendered and 'CPU42' in rendered, rendered
        assert any(row[1] == '1' for row in observations), observations
        assert any(row[2] == '0' and row[3] >= 4 for row in observations), observations
        assert any(row[3] < 4 for row in observations), observations
        print('PASS demand-driven full controls, compact controls, shortened labels, index-only and CJK widths')
        print(observations)
    finally:
        subprocess.run(['tmux', '-S', socket, 'kill-server'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if client:
            client.wait(timeout=5)
        os.close(master)
        os.close(slave)
