#!/bin/sh
# set-appearance.sh light|dark — the single funnel that applies an appearance:
# set @adaptive_appearance and re-apply the theme (which also publishes the
# value to the shared state file for non-tmux consumers). Both the terminal's
# native theme reporting (tmux 3.5+ client-light-theme/client-dark-theme hooks,
# wired up by tmux-adaptive-theme.tmux) and the OSC-11 fallback detector
# (detect-appearance.sh) route through here, so there is one apply path.
#
# No tty required — unlike the OSC-11 query, this just consumes a decision that
# was already made, so it is safe from run-shell, launchd, and SSH. POSIX sh.
set -u
case "${1:-}" in
   light|dark) want=$1 ;;
   *) printf 'usage: %s light|dark\n' "$0" >&2; exit 2 ;;
esac
command -v tmux >/dev/null 2>&1 || exit 0
tmux has-session >/dev/null 2>&1 || exit 0

dir=$(dirname "$0")
old=$(tmux show-option -gqv @adaptive_appearance)
if [ "$old" = "$want" ]; then changed=no; else changed=yes; fi

trace="${XDG_STATE_HOME:-$HOME/.local/state}/tmux/appearance.log"
mkdir -p "$(dirname "$trace")" 2>/dev/null || true
printf '%s pid=%s ppid=%s source=set-appearance old=%s want=%s changed=%s client_themes=%s tmux=%s\n' \
   "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "$PPID" "${old:-unset}" "$want" \
   "$changed" "$(tmux list-clients -F '#{client_theme}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')" \
   "${TMUX:-none}" >> "$trace" 2>/dev/null || true

# Only touch the option (and thus repaint) when it actually changes; but always
# re-run the theme so a first apply after tmux start still paints. The theme
# itself publishes the state file, guarded on change.
if [ "$changed" = yes ]; then
   tmux set-option -g @adaptive_appearance "$want"
fi
tmux run-shell -b "$dir/tmux-adaptive-theme.tmux"
