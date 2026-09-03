#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
socket=adaptive-context-$$
cleanup() { tmux -L "$socket" kill-server >/dev/null 2>&1 || true; }
trap cleanup EXIT HUP INT TERM

tmux -L "$socket" -f /dev/null new-session -d -s test
tmux -L "$socket" run-shell "$repo/tmux-adaptive-theme.tmux"
sleep 0.2

# Simulate a provider loading after the theme.
tmux -L "$socket" set-option -g @adaptive_context_state '#{@provider_state}'
tmux -L "$socket" set-option -g @adaptive_context_label '#{@provider_label}'
tmux -L "$socket" set-option -g @adaptive_context_suffix ' USAGE'
tmux -L "$socket" set-option -g @adaptive_context_range_open '#[range=user|provider]'
tmux -L "$socket" set-option -g @adaptive_context_range_close '#[range=]'
tmux -L "$socket" set-window-option @provider_state working
tmux -L "$socket" set-window-option @provider_label CODEX

# A provider loaded after the theme requests one apply through the published
# directory; later appearance-driven applies consume the retained options too.
theme_dir=$(tmux -L "$socket" show-option -gqv @adaptive_theme_dir)
tmux -L "$socket" run-shell "$theme_dir/tmux-adaptive-theme.tmux"
sleep 0.2

assert_context() {
  rendered=$(tmux -L "$socket" display-message -p '#{E:status-right}')
  case $rendered in *CODEX*USAGE*) ;; *)
    printf 'context provider was not rendered: %s\n' "$rendered" >&2
    exit 1
  esac
  case $rendered in *'range=user|provider'*) ;; *)
    printf 'context provider range was not rendered: %s\n' "$rendered" >&2
    exit 1
  esac
}

assert_context
tmux -L "$socket" run-shell "$repo/tmux-adaptive-theme.tmux"
sleep 0.2
assert_context
printf '%s\n' 'context provider: ok'
