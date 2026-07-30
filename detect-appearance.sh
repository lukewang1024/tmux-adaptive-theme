#!/bin/sh
# detect-appearance.sh — FALLBACK detector for terminals without native theme
# reporting (DEC mode 2031): set @adaptive_appearance from the terminal's ACTUAL
# background via an OSC 11 query and re-apply the theme. On terminals that DO
# support 2031 (kitty, recent iTerm2, Ghostty, WezTerm, …) you don't need this —
# tmux-adaptive-theme.tmux wires up tmux's native client-light-theme/
# client-dark-theme hooks, which are push-based, tty-free, and relay through SSH.
# This script is for the stragglers (Apple Terminal.app, older clients).
#
# It MUST run from an interactive terminal: the OSC query needs a controlling
# tty, which tmux's run-shell and the theme itself don't have. Wire it into your
# shell so the bar updates when the terminal theme changes, e.g. for zsh:
#
#     autoload -Uz add-zsh-hook
#     add-zsh-hook precmd() { ~/.local/share/tmux/plugins/tmux-adaptive-theme/detect-appearance.sh }
#
# Safe to call any time: it no-ops without tmux, without a tty, or if the
# terminal doesn't answer, and only re-applies the theme when the value changes.
# POSIX sh.
set -u
[ -n "${TMUX:-}" ] || exit 0
[ -t 1 ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# --- query OSC 11 (terminal background) --------------------------------------
old_stty=$(stty -g 2>/dev/null) || exit 0
stty raw -echo min 0 time 2 2>/dev/null            # ~0.2s ceiling for the reply
printf '\033]11;?\007' > /dev/tty                  # BEL-terminated query
resp=$(head -c 48 < /dev/tty 2>/dev/null)
stty "$old_stty" 2>/dev/null

case "$resp" in
   *rgb:*) hex=${resp#*rgb:} ;;
   *) exit 0 ;;                                     # no/unknown reply -> leave as-is
esac

# hex = RRRR/GGGG/BBBB (16-bit) or RR/GG/BB — take the high byte of each channel
r=${hex%%/*}; rest=${hex#*/}; g=${rest%%/*}; rest=${rest#*/}; b=${rest%%[!0-9A-Fa-f]*}
hibyte() { printf '%s' "$1" | cut -c1-2; }
r=$(( 0x$(hibyte "$r") )); g=$(( 0x$(hibyte "$g") )); b=$(( 0x$(hibyte "$b") ))

# perceived luminance 0..255; >128 = light background
lum=$(( (r*2126 + g*7152 + b*722) / 10000 ))
[ "$lum" -gt 128 ] && want=light || want=dark

# --- apply -------------------------------------------------------------------
# Route through the shared funnel so this fallback and the native theme hooks
# take the exact same apply path (set option -> publish state file -> repaint).
"$(dirname "$0")/set-appearance.sh" "$want"
