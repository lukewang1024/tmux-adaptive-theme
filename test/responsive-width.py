#!/usr/bin/env python3
"""Test width pressure with actual window names and independently sized clients."""
import fcntl
import os
from pathlib import Path
import pty
import re
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
        for key, value_ in (('@adaptive_time_enabled', 'off'), ('@adaptive_date_enabled', 'off'), ('@adaptive_cpu', 'CPU42 MEM56'), ('@adaptive_cpu_compact', 'CPU42'), ('@adaptive_context_state', '#{@test_agent_state}'), ('@adaptive_context_label', 'CODING AGENT'), ('@adaptive_context_suffix', 'QUOTA73'), ('@adaptive_host_icon', 'H'), ('@adaptive_host_range_open', '#[range=user|host]'), ('@adaptive_host_range_close', '#[range=]')):
            tmux('set', '-g', key, value_)
        tmux('set', '-w', '@test_agent_state', 'working')
        tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 130, 0, 0))
        client = subprocess.Popen(['tmux', '-S', socket, 'attach'], stdin=slave, stdout=slave, stderr=slave, env=env)
        drain()
        name = tmux('list-clients', '-F', '#{client_name}')
        assert value('#{E:@adaptive_controls_full}') == '1'
        hostname = value('#{host}')
        assert hostname in value('#{E:@adaptive_item_full_host_body}')
        compact_host = value('#{E:@adaptive_item_compact_host_body}')
        assert 'range=user|host' in compact_host and hostname not in compact_host, compact_host
        assert re.sub(r'#\[[^\]]*\]', '', compact_host).strip() == 'H', compact_host
        for session_name, label in (('CCM运维', 'CCM'), ('中文会话名称', '中文'), ('ab中会话', 'ab中'), ('long-session-name', 'long')):
            tmux('rename-session', session_name)
            for density, expected in (('full', session_name), ('compact', label)):
                body = value(f'#{{E:@adaptive_item_{density}_session_body}}')
                assert re.sub(r'#\[[^\]]*\]', '', body).strip() == expected, body
            left = re.sub(r'#\[[^\]]*\]', '', value('#{T:status-left}'))
            assert session_name in left, (session_name, left)
        # Same client width, greater tab demand: fixed controls compact first.
        for index, title in enumerate(('investigate responsive layout', '修复侧边栏状态和窗口标签', 'test unicode width handling'), 1):
            tmux('new-window', '-d', '-n', title)
        assert value('#{E:@adaptive_controls_full}') == '0'
        observations = []
        for width in (318, 240, 180, 130, 110, 90, 70, 50):
            resize(width)
            full = value('#{E:@adaptive_controls_full}')
            labels_full = value('#{E:@adaptive_tabs_full}')
            limit = int(value('#{E:@adaptive_tab_name_limit}'))
            left = int(value('#{w:#{T:status-left}}'))
            right = int(value('#{w:#{T:status-right}}'))
            tabs = int(value('#{w:#{W:#{E:window-status-format}}}'))
            assert value('#{W:#{E:@adaptive_controls_full}}') == full * 4
            observations.append((width, full, labels_full, limit, left, right, tabs))
            session = re.sub(r'#\[[^\]]*\]', '', value('#{T:status-left}')).strip(' \ue0b0')
            assert session == ('long-session-name' if full == '1' else 'long'), (width, full, session)
            if limit >= 2:
                names = value('#{W:#{window_name}|}').split('|')[:-1]
                labels = value('#{W:#{E:@adaptive_tab_label}|}').split('|')[:-1]
                for title, label in zip(names, labels, strict=True):
                    expected = title[:limit if title.isascii() else limit // 2]
                    assert label == expected, (width, limit, title, label)
            if width >= 70:
                assert left + right + tabs <= width, observations
            rendered = value('#{E:status-right}')
            if full == '0':
                assert 'QUOTA73' not in rendered and 'CPU42' in rendered, rendered
        assert any(row[1] == '1' for row in observations), observations
        assert any(row[2] == '0' and row[3] >= 2 for row in observations), observations
        assert any(row[3] < 2 for row in observations), observations
        print('PASS demand-driven full controls, compact controls, shortened labels, index-only and CJK widths')
        print(observations)
    finally:
        subprocess.run(['tmux', '-S', socket, 'kill-server'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if client:
            client.wait(timeout=5)
        os.close(master)
        os.close(slave)
