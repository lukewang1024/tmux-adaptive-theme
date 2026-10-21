#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
socket=adaptive-context-$$
test_root=$(mktemp -d "${TMPDIR:-/tmp}/adaptive-context.XXXXXX")
export XDG_STATE_HOME="$test_root/state"
cleanup() {
  tmux -L "$socket" kill-server >/dev/null 2>&1 || true
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

tmux -L "$socket" -f /dev/null new-session -d -s test
tmux -L "$socket" run-shell "$repo/tmux-adaptive-theme.tmux"
sleep 0.2

# Simulate a provider loading after the theme.
tmux -L "$socket" set-option -g @adaptive_context_state '#{@provider_state}'
tmux -L "$socket" set-option -g @adaptive_context_label '#{@provider_label}'
tmux -L "$socket" set-option -g @adaptive_context_suffix ' USAGE'
tmux -L "$socket" set-option -g @adaptive_usage_range_open '#[range=user|usage]'
tmux -L "$socket" set-option -g @adaptive_usage_range_close '#[range=]'
tmux -L "$socket" set-option -g @adaptive_context_range_open '#[range=user|provider]'
tmux -L "$socket" set-option -g @adaptive_context_range_close '#[range=]'
tmux -L "$socket" set-option -g @adaptive_session_range_open '#[range=user|prefix]'
tmux -L "$socket" set-option -g @adaptive_session_range_close '#[range=]'
tmux -L "$socket" set-option -g @adaptive_host_icon H
tmux -L "$socket" set-option -g @adaptive_host_range_open '#[range=user|host]'
tmux -L "$socket" set-option -g @adaptive_host_range_close '#[range=]'
tmux -L "$socket" set-option -g @adaptive_cpu C
tmux -L "$socket" set-option -g @adaptive_cpu_min_width 0
tmux -L "$socket" set-option -g @adaptive_cpu_range_open '#[range=user|cpu]'
tmux -L "$socket" set-option -g @adaptive_cpu_range_close '#[range=]'
tmux -L "$socket" set-option -g @adaptive_action_1_icon A
tmux -L "$socket" set-option -g @adaptive_action_1_range action_one
tmux -L "$socket" set-option -g @adaptive_action_2_icon B
tmux -L "$socket" set-option -g @adaptive_action_2_range action_two
tmux -L "$socket" set-option -g @adaptive_action_3_icon C
tmux -L "$socket" set-option -g @adaptive_action_3_range action_three
tmux -L "$socket" set-window-option @provider_state working
tmux -L "$socket" set-window-option @provider_label CODEX

# A provider loaded after the theme requests one apply through the published
# directory; later appearance-driven applies consume the retained options too.
theme_dir=$(tmux -L "$socket" show-option -gqv @adaptive_theme_dir)
tmux -L "$socket" run-shell "$theme_dir/tmux-adaptive-theme.tmux"
sleep 0.2

assert_context() {
  rendered=$(tmux -L "$socket" display-message -p '#{T:@adaptive_full_right}')
  case $rendered in *CODEX*USAGE*) ;; *)
    printf 'context provider was not rendered: %s\n' "$rendered" >&2
    exit 1
  esac
  case $rendered in *'range=user|provider'*) ;; *)
    printf 'context provider range was not rendered: %s\n' "$rendered" >&2
    exit 1
  esac
  rendered_left=$(tmux -L "$socket" display-message -p '#{E:status-left}')
  case $rendered_left in *'range=user|prefix'*) ;; *)
    printf 'session range was not rendered: %s\n' "$rendered_left" >&2
    exit 1
  esac
  rendered_right=$(tmux -L "$socket" display-message -p '#{T:@adaptive_full_right}')
  case $rendered_left in *'range=user|prefix'*'range=user|action_two'*'range=user|action_one'*'range=user|action_three'*) ;; *)
    printf 'action and context ranges were not rendered in order: %s\n' "$rendered_right" >&2
    exit 1
  esac
  case $rendered_right in *'range=user|cpu'*'range=user|host'*) ;; *)
    printf 'CPU and host ranges were not rendered in order: %s\n' "$rendered_right" >&2
    exit 1
  esac
}

assert_context
tmux -L "$socket" run-shell "$repo/tmux-adaptive-theme.tmux"
sleep 0.2
assert_context
# Providers can hide a complete action without a theme repaint. Pane focus
# and per-client sizing are format inputs, not asynchronous status scripts.
tmux -L "$socket" set-option -g @adaptive_action_2_visible '#{==:#{@provider_agent},1}'
tmux -L "$socket" set-option -g @adaptive_action_3_visible '#{e|<:#{@provider_width},106}'
tmux -L "$socket" set-option -g @provider_width 140
tmux -L "$socket" set-option -p @provider_agent 1
first_pane=$(tmux -L "$socket" display-message -p '#{pane_id}')
tmux -L "$socket" run-shell "$repo/tmux-adaptive-theme.tmux"
rendered=$(tmux -L "$socket" display-message -p '#{E:status-left}')
case $rendered in *action_two*) ;; *) exit 1 ;; esac
case $rendered in *action_three*) exit 1 ;; esac
second_pane=$(tmux -L "$socket" split-window -d -P -F '#{pane_id}')
tmux -L "$socket" set-option -p -t "$second_pane" @provider_agent 0
tmux -L "$socket" select-pane -t "$second_pane"
rendered=$(tmux -L "$socket" display-message -p '#{E:status-left}')
case $rendered in *action_two*|*action_three*) exit 1 ;; esac
tmux -L "$socket" set-option -g @provider_width 80
rendered=$(tmux -L "$socket" display-message -p '#{E:status-left}')
case $rendered in *action_three*) ;; *) exit 1 ;; esac
tmux -L "$socket" select-pane -t "$first_pane"
rendered=$(tmux -L "$socket" display-message -p '#{E:status-left}')
case $rendered in *action_two*action_one*action_three*) ;; *) exit 1 ;; esac
printf '%s\n' 'context provider and dynamic action visibility: ok'
