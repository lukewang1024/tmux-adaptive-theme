#!/bin/sh
# tmux-adaptive-theme — a light/dark-adaptive One Dark status theme for tmux.
#
# The palette tracks the terminal's own background — One Dark on a dark
# background, Atom One Light on a light one — and can also pick up the terminal's
# ANSI colors:
#   * @adaptive_mode = light | full — `light` keeps fixed One Dark/Light accents;
#     `full` takes the accent + semantic warn/alert marks from the terminal's own
#     ANSI palette.
#   * Activity/bell show as a recolored #I/#W separator mark (activity -> yellow,
#     bell -> red) rather than a reverse-video banner.
#
# Light vs dark is decided by the terminal's ACTUAL background (not the OS
# preference), detected by the companion detect-appearance.sh (OSC 11) which sets
# @adaptive_appearance; run that from your shell (see README). This theme has no
# tty of its own, so it just consumes @adaptive_appearance.
#
# Color scheme derived from odedlaz/tmux-onedark-theme (MIT); see LICENSE.
#
# POSIX sh so it also runs under a minimal environment (tpm, run-shell); the
# explicit PATH lets tmux resolve there, and the refresh-client at the end makes
# a re-apply repaint immediately.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"
command -v tmux >/dev/null 2>&1 || exit 0
tmux has-session >/dev/null 2>&1 || exit 0

get() {
   _v=$(tmux show-option -gqv "$1")
   if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "$2"; fi
}
t()  { tmux set-option -gq "$1" "$2"; }
tw() { tmux set-window-option -gq "$1" "$2"; }

# --- resolve appearance + palette --------------------------------------------
# Appearance comes from the terminal's actual background, detected out-of-band by
# detect-appearance.sh (which sets @adaptive_appearance). The theme just consumes
# it; default dark until the first detection runs.
appearance=$(get "@adaptive_appearance" "dark")
[ "$appearance" = light ] || appearance=dark

if [ "$appearance" = light ]; then
   # Atom One Light
   c_bg="#fafafa"; c_fg="#383a42"; c_sel="#e5e5e6"; c_dim="#a0a1a7"
   c_accent="#50a14f"; c_warn="#c18401"; c_alert="#e45649"; c_info="#4078f2"
else
   # One Dark
   c_bg="#282c34"; c_fg="#aab2bf"; c_sel="#3e4452"; c_dim="#5c6370"
   c_accent="#98c379"; c_warn="#e5c07b"; c_alert="#e06c75"; c_info="#61afef"
fi

# full mode: take the accent + semantic warn/alert from the terminal's own ANSI
# palette so they match the terminal theme (chrome stays the palette above).
if [ "$(get "@adaptive_mode" "light")" = full ]; then
   c_accent=$(get "@adaptive_accent" "colour2")   # session/host pill accent
   c_warn=colour3                                  # activity mark / cap
   c_alert=colour1                                 # bell mark / cap
   c_info=colour4
fi

# Powerline separators are kept in opaque @pl* options and referenced as #{@pl*}
# in the (pure-ASCII) format strings below. A multibyte glyph written straight
# into a format-string option is mangled to "_" when the theme is re-applied from
# a minimal environment (the appearance watcher under launchd); an opaque option
# keeps its bytes, and #{@pl*} expands to the glyph at render time in the client.
t "@pl0" "$(printf '\356\202\260')"   # U+E0B0  right, filled
t "@pl1" "$(printf '\356\202\261')"   # U+E0B1  right, thin
t "@pl2" "$(printf '\356\202\262')"   # U+E0B2  left,  filled
t "@pl3" "$(printf '\356\202\263')"   # U+E0B3  left,  thin

# Clear deprecated *-fg/*-bg/*-attr options first. tmux still honours them and
# lets them OVERRIDE the modern *-style options this theme uses, so any legacy
# value left by another config (or an older theme) would win and, e.g., keep the
# bar background dark in light mode. Wipe them so *-style below is authoritative.
for o in status status-left status-right message message-command \
         pane-border pane-active-border; do
   tmux set-option -gu "${o}-bg" 2>/dev/null
   tmux set-option -gu "${o}-fg" 2>/dev/null
   tmux set-option -gu "${o}-attr" 2>/dev/null
done
for o in window-status window-status-current window-status-activity \
         window-status-bell window-status-last; do
   tmux set-window-option -gu "${o}-bg" 2>/dev/null
   tmux set-window-option -gu "${o}-fg" 2>/dev/null
   tmux set-window-option -gu "${o}-attr" 2>/dev/null
done

# --- options (modern *-style) ------------------------------------------------
t "status" "on"
t "status-justify" "left"
t "status-left-length" "100"
t "status-right-length" "150"
t "status-style" "bg=$c_bg,fg=$c_fg,none"
t "message-style" "bg=$c_bg,fg=$c_fg"
t "message-command-style" "bg=$c_bg,fg=$c_fg"

tw "window-status-style" "fg=$c_fg,bg=$c_bg,none"
# Keep activity/bell tabs neutral (no reverse-video banner); the indicator is
# the recolored separator mark in window-status-format below.
tw "window-status-activity-style" "fg=$c_fg,bg=$c_bg,none"
tw "window-status-bell-style" "fg=$c_fg,bg=$c_bg,none"
tw "window-status-separator" ""

t "window-style" "fg=$c_dim"
t "window-active-style" "fg=$c_fg"

t "pane-border-style" "fg=$c_fg,bg=$c_bg"
t "pane-active-border-style" "fg=$c_accent,bg=$c_bg"

t "display-panes-active-colour" "$c_warn"
t "display-panes-colour" "$c_info"

t "@prefix_highlight_fg" "$c_bg"
t "@prefix_highlight_bg" "$c_accent"
t "@prefix_highlight_copy_mode_attr" "fg=$c_bg,bg=$c_accent"
t "@prefix_highlight_output_prefix" "  "

status_widgets=$(get "@adaptive_widgets")
time_format=$(get "@adaptive_time_format" "%R")
date_format=$(get "@adaptive_date_format" "%d/%m/%Y")

# activity -> warn, bell -> alert, else normal: recolors the #I/#W separator.
mark="#{?window_bell_flag,$c_alert,#{?window_activity_flag,$c_warn,$c_fg}}"

# --- status format strings ---------------------------------------------------
t "status-right" "#[fg=$c_fg,bg=$c_bg,nounderscore,noitalics]${time_format} #{@pl3} ${date_format} #[fg=$c_sel,bg=$c_bg]#{@pl2}#[fg=$c_sel,bg=$c_sel]#{@pl2}#[fg=$c_fg, bg=$c_sel]${status_widgets} #[fg=$c_accent,bg=$c_sel,nobold,nounderscore,noitalics]#{@pl2}#[fg=$c_bg,bg=$c_accent,bold] #h #[fg=$c_warn, bg=$c_accent]#{@pl2}#[fg=$c_alert,bg=$c_warn]#{@pl2}"
t "status-left" "#[fg=$c_bg,bg=$c_accent,bold] #S #{prefix_highlight}#[fg=$c_accent,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"

t "window-status-format" "#[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_bg] #I #[fg=${mark}]#{@pl1}#[fg=$c_fg] #W #[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"
t "window-status-current-format" "#[fg=$c_bg,bg=$c_sel,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_sel,nobold] #I #{@pl1} #W #[fg=$c_sel,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"

# The widgets in status-right come from other plugins (battery/cpu/
# prefix-highlight) that tpm may source after this theme; re-run them so their
# format placeholders resolve, then refresh each client so a re-apply (e.g. from
# an appearance watcher) repaints immediately instead of on the next attach.
plug="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.local/share/tmux/plugins}"
for p in tmux-prefix-highlight/prefix_highlight tmux-battery/battery tmux-cpu/cpu; do
   [ -x "$plug/$p.tmux" ] && "$plug/$p.tmux" >/dev/null 2>&1
done
for c in $(tmux list-clients -F '#{client_name}' 2>/dev/null); do
   tmux refresh-client -S -t "$c" 2>/dev/null || true
done
