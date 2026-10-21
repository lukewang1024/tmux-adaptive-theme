#!/usr/bin/env python3
"""Exercise adjacency, boundaries and hit regions with real tmux expansion."""
import itertools
import fcntl
import pty
import select
import struct
import termios
import time
import os
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
socket = f'adaptive-layout-{os.getpid()}'
test_root = tempfile.TemporaryDirectory(prefix='adaptive-layout-')
env = dict(os.environ, TERM='xterm-256color', XDG_STATE_HOME=str(Path(test_root.name) / 'state'))
env.pop('TMUX', None)
env.pop('TMUX_PANE', None)

def tmux(*args):
    return subprocess.check_output(['tmux', '-L', socket, *args], env=env, text=True).strip()

def option(key, value):
    tmux('set-option', '-g', key, value)

def check_boundaries(rendered, base):
    fg, bg, previous, hit, expected = '', base, base, '', None
    for token in re.findall(r'#\[[^\]]*\]|.', rendered):
        if token.startswith('#['):
            for field in token[2:-1].split(','):
                if field == 'default':
                    fg, bg, hit = '', base, ''
                elif field.startswith('fg='):
                    fg = field[3:]
                elif field.startswith('bg='):
                    bg = field[3:]
                elif field.startswith('range='):
                    hit = field[6:]
            continue
        if expected is not None:
            assert bg == expected, ('surface after boundary', expected, bg, rendered)
            expected = None
        if token == '\ue0b2':
            assert not hit and bg == previous, ('left boundary', hit, bg, previous, rendered)
            expected = fg
        elif token == '\ue0b0':
            assert not hit and fg == previous and bg == base, ('right boundary', hit, fg, previous, rendered)
        elif token == '\ue0b3':
            assert not hit and bg == previous, ('internal divider', hit, bg, previous, rendered)
        previous = fg if token == '\ue0b2' else bg
    assert bg == base and not hit, ('unclosed surface or mouse range', rendered)

try:
    tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'test')
    option('@adaptive_context_state', '#{@test_state}')
    option('@adaptive_context_label', 'AGENT')
    option('@adaptive_context_range_open', '#[range=user|agent]')
    option('@adaptive_context_range_close', '#[range=]')
    option('@adaptive_context_suffix', 'QUOTA')
    option('@adaptive_usage_range_open', '#[range=user|usage]')
    option('@adaptive_usage_range_close', '#[range=]')
    option('@adaptive_cpu', 'CPU')
    option('@adaptive_cpu_min_width', '0')
    option('@adaptive_cpu_range_open', '#[range=user|cpu]')
    option('@adaptive_cpu_range_close', '#[range=]')
    option('@adaptive_host_icon', 'HOST')
    option('@adaptive_host_range_open', '#[range=user|host]')
    option('@adaptive_host_range_close', '#[range=]')
    for slot in (1, 2, 3):
        option(f'@adaptive_action_{slot}_icon', str(slot))
        option(f'@adaptive_action_{slot}_range', f'action{slot}')
        option(f'@adaptive_action_{slot}_visible', f'#{{@test_visible_{slot}}}')
    option('@adaptive_action_2_active', '#{@test_sidebar_open}')
    count = 0
    for appearance, metadata in itertools.product(('dark', 'light'), (False, True)):
        option('@adaptive_appearance', appearance)
        for field in ('time', 'date'):
            option(f'@adaptive_{field}_enabled', 'on' if metadata else 'off')
        tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))
        for density in ('full', 'compact'):
            option('@test_sidebar_open', '0')
            hidden_style = tmux('display-message', '-p', f'#{{E:@adaptive_item_{density}_action2_body}}')
            option('@test_sidebar_open', '1')
            visible_style = tmux('display-message', '-p', f'#{{E:@adaptive_item_{density}_action2_body}}')
            assert hidden_style != visible_style, ('sidebar colour did not change', density)
            option('@test_sidebar_open', '0')
            hidden_session = tmux('display-message', '-p', f'#{{E:@adaptive_item_{density}_session_body}}')
            option('@test_sidebar_open', '1')
            visible_session = tmux('display-message', '-p', f'#{{E:@adaptive_item_{density}_session_body}}')
            assert hidden_session == visible_session, ('sidebar changed session colour', density)

        base = re.search(r'bg=([^,]+)', tmux('show-option', '-gqv', 'status-style')).group(1)
        for visibility, state in itertools.product(itertools.product((0, 1), repeat=3), ('', 'working', 'blocked')):
            for slot, visible in enumerate(visibility, 1):
                option(f'@test_visible_{slot}', str(visible))
            option('@test_state', state)
            rendered = tmux('display-message', '-p', '#{T:@adaptive_full_right}')
            check_boundaries(rendered, base)
            ranges = re.findall(r'range=user\|([a-z0-9]+)', rendered)
            wanted = ['cpu', 'host']
            if state:
                wanted += ['agent', 'usage']
            assert ranges == wanted, (ranges, wanted)
            left = tmux('display-message', '-p', '#{T:@adaptive_full_left}')
            left_ranges = re.findall(r'range=user\|([a-z0-9]+)', left)
            expected_left = [f'action{i}' for i in (2, 1, 3) if visibility[i - 1]]
            assert left_ranges == expected_left, (left_ranges, expected_left)
            right_text = re.sub(r'#\[[^\]]*\]', '', rendered)
            assert not right_text.endswith('\ue0b0'), ('right edge must be flat', rendered)
            assert not tmux('show-option', '-gqv', '@adaptive_full_left').endswith(' '), ('extra window label gap', left)

            count += 1
    option('@adaptive_cpu', '#(printf CPU)')
    tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))
    rendered = tmux('display-message', '-p', '#{T:@adaptive_full_right}')
    assert 'range=user|cpu' in rendered, 'An empty first async sample hid its own producer'
    # Real attached status rendering must start async producers nested inside
    # compiled item bodies, then redraw when their first output arrives.
    option('@adaptive_cpu', '#(printf CPU42)')
    option('@adaptive_context_suffix', '#(printf QUOTA73)')
    tmux('run-shell', str(repo / 'tmux-adaptive-theme.tmux'))
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 200, 0, 0))
    client = subprocess.Popen(['tmux', '-L', socket, 'attach-session', '-t', 'test'],
                              stdin=slave, stdout=slave, stderr=slave, env=env)
    try:
        data = b''
        deadline = time.monotonic() + 8
        while b'CPU42' not in data or b'QUOTA73' not in data:
            assert client.poll() is None
            assert time.monotonic() < deadline, ('async item never refreshed', data[-1000:])
            if select.select([master], [], [], 0.1)[0]:
                data += os.read(master, 65536)
    finally:
        client.terminate()
        client.wait(timeout=5)
        os.close(master)
        os.close(slave)
    print(f'PASS {count} light/dark, visibility, metadata and agent-state layouts')
    print('PASS async CPU and usage producers refresh in an attached client')
finally:
    subprocess.run(['tmux', '-L', socket, 'kill-server'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    test_root.cleanup()
