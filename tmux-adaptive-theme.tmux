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
# Light vs dark is decided by the terminal's ACTUAL theme (not the OS
# preference). Primary source: tmux's native client-light-theme/client-dark-theme
# hooks (tmux 3.5+, DEC mode 2031), wired up below — push-based and SSH-safe.
# Fallback for terminals without 2031: the companion detect-appearance.sh
# (OSC 11), run from your shell (see README). Either way @adaptive_appearance
# holds the decision; this theme just consumes it (it has no tty of its own).
#
# Color scheme derived from odedlaz/tmux-onedark-theme (MIT); see LICENSE.
#
# POSIX sh so it also runs under a minimal environment (tpm, run-shell); the
# extra dirs are APPENDED so tmux still resolves under a minimal environment
# (e.g. the launchd appearance watcher) without shadowing the tmux that is
# already on PATH — prepending them lets a stale /usr/bin/tmux win over the real
# one and talk to the wrong server, so has-session below fails and the theme
# silently no-ops. The refresh-client at the end makes a re-apply repaint now.

export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
command -v tmux >/dev/null 2>&1 || exit 0
tmux has-session >/dev/null 2>&1 || exit 0

# --- subscribe to the terminal's NATIVE light/dark reporting (tmux 3.5+) ------
# Terminals that implement DEC private mode 2031 (kitty >=0.35, recent iTerm2,
# Ghostty, WezTerm, foot, Contour, Rio, …) push a notification the instant their
# theme flips; tmux negotiates 2031 with its outer terminal and fires these
# hooks. The report also relays through SSH and nested tmux, so a remote tmux's
# hooks fire from the real local terminal — no tty, no polling, no manual
# re-sync, no palette reading. Terminals without 2031 (Apple Terminal.app, older
# clients) simply never fire these; the OSC-11 fallback (detect-appearance.sh)
# or an OS-appearance watcher covers them. Re-registering on every apply is
# idempotent (set-hook -g replaces) and cannot recurse: the hooks call
# set-appearance.sh, which re-runs this script but does not itself re-fire them.
_dir=$(dirname "$0")
tmux set-hook -g client-light-theme "run-shell -b '$_dir/set-appearance.sh light'"
tmux set-hook -g client-dark-theme  "run-shell -b '$_dir/set-appearance.sh dark'"

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

# Publish the resolved appearance to a per-host state file so non-tmux consumers
# can track the same signal without querying the terminal themselves — nvim's
# libuv fs watcher (which tmux would otherwise starve, since tmux consumes the
# 2031 report and does not forward it to panes), plain vim's FocusGained hook,
# etc. Atomic write (temp + rename) so a watcher never reads a half-written
# file, and only on change so re-applies/attaches don't fire watchers spuriously.
_state="${XDG_STATE_HOME:-$HOME/.local/state}/appearance"
if [ "$(cat "$_state" 2>/dev/null)" != "$appearance" ]; then
   mkdir -p "$(dirname "$_state")" 2>/dev/null
   printf '%s\n' "$appearance" > "$_state.$$" 2>/dev/null &&
      mv "$_state.$$" "$_state" 2>/dev/null
fi

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
t "@adaptive_agent_icon" "$(printf '\363\260\232\251')" # U+F06A9 Nerd Font robot

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
# Status messages are transient notices, so give them the semantic warning
# background instead of letting them disappear into the ordinary status bar.
# Options permit a personal override without forking the theme.
message_bg=$(get "@adaptive_message_bg" "$c_warn")
if [ "$appearance" = light ]; then
   message_contrast="$c_fg"
else
   message_contrast="$c_bg"
fi
message_fg=$(get "@adaptive_message_fg" "$message_contrast")
t "message-style" "bg=$message_bg,fg=$message_fg,fill=$message_bg,bold"
t "message-command-style" "bg=$message_bg,fg=$message_fg,fill=$message_bg,bold"

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

plug="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.local/share/tmux/plugins}"
case "$plug" in
   "~")   plug="$HOME" ;;
   "~/"*) plug="$HOME/${plug#"~/"}" ;;
esac
maintenance=$(get "@adaptive_maintenance" "")
battery_status=$(get "@adaptive_battery" "")
cpu_status=$(get "@adaptive_cpu" "$(get "@adaptive_widgets" "")")
# CPU/battery plugins only interpolate placeholders found directly in
# status-right. Resolve them before composing the responsive metric sections.
battery_status=$(printf '%s' "$battery_status" | sed \
   -e "s|#{battery_icon}|#($plug/tmux-battery/scripts/battery_icon.sh)|g" \
   -e "s|#{battery_percentage}|#($plug/tmux-battery/scripts/battery_percentage.sh)|g")
cpu_status=$(printf '%s' "$cpu_status" | sed \
   -e "s|#{cpu_percentage}|#($plug/tmux-cpu/scripts/cpu_percentage.sh)|g" \
   -e "s|#{cpu_icon}|#($plug/tmux-cpu/scripts/cpu_icon.sh)|g")
time_format=$(get "@adaptive_time_format" "%R")
date_format=$(get "@adaptive_date_format" "%d/%m/%Y")
time_min_width=$(get "@adaptive_time_min_width" "0")
date_min_width=$(get "@adaptive_date_min_width" "0")
battery_min_width=$(get "@adaptive_battery_min_width" "0")
cpu_min_width=$(get "@adaptive_cpu_min_width" "0")
compact_min_width=$(get "@adaptive_compact_min_width" "0")
session_compact_chars=$(get "@adaptive_session_compact_chars" "8")
host_compact_chars=$(get "@adaptive_host_compact_chars" "8")
script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)

# activity -> warn, bell -> alert, else normal: recolors the #I/#W separator.
mark="#{?window_bell_flag,$c_alert,#{?window_activity_flag,$c_warn,$c_fg}}"

# --- status format strings ---------------------------------------------------
# Store complete styled sections in opaque options.  The status format can then
# conditionally include each whole section without commas inside style strings
# confusing tmux's conditional-format parser.
t "@adaptive_status_time" "#[fg=$c_fg,bg=$c_bg,nounderscore,noitalics]${time_format} #{@pl3} "
t "@adaptive_status_date" "#[fg=$c_fg,bg=$c_bg,nounderscore,noitalics]${date_format} "
t "@adaptive_status_metrics_lead" "#[fg=$c_sel,bg=$c_bg]#{@pl2}#[fg=$c_fg,bg=$c_sel] "
# Match Peon Ping's tab-colour semantics: ready/idle green, working amber,
# done blue, and approval/blocked red.  Use this theme's adaptive equivalents
# so the badge remains legible in both light and dark terminal palettes.
agent_bg="#{?#{==:#{@workbench_window_state},blocked},$c_alert,#{?#{==:#{@workbench_window_state},working},$c_warn,#{?#{==:#{@workbench_window_state},done},$c_info,#{?#{==:#{@workbench_window_state},idle},$c_accent,$c_dim}}}}"
agent_mark="#{?#{==:#{@workbench_window_state},blocked},!,#{?#{==:#{@workbench_window_state},working},●,#{?#{==:#{@workbench_window_state},done},✓,#{?#{==:#{@workbench_window_state},idle},○,?}}}}"
agent_content="#{@adaptive_agent_icon} #{?#{e|>=:#{client_width},${compact_min_width}},#{@workbench_window_label},${agent_mark}}"
t "@adaptive_status_agent" "#[fg=${agent_bg},bg=$c_sel,nobold]#{@pl2}#[fg=$c_bg,bg=${agent_bg},bold] ${agent_content} "
t "@adaptive_status_agent_standalone" "#[fg=${agent_bg},bg=$c_bg,nobold]#{@pl2}#[fg=$c_bg,bg=${agent_bg},bold] ${agent_content} "
t "@adaptive_status_host_close" "#[fg=$c_accent,bg=$c_sel,nobold]#{@pl2}#[fg=$c_bg,bg=$c_accent] #{@adaptive_agent_icon} "
t "@adaptive_status_empty_agent_standalone" "#[fg=$c_accent,bg=$c_bg,nobold]#{@pl2}#[fg=$c_bg,bg=$c_accent] #{@adaptive_agent_icon} "
# Agent is the non-negotiable tail.  Every optional tier before it includes its
# own opening separator, so a hidden/truncated tier can never leave a loose grey
# triangle behind.  Below host_min_width the complete right side is only the
# agent capsule; session/window/host compaction therefore creates space for
# state instead of allowing tmux to crop it away. Host remains present at every
# width, using the same middle truncation as the session in compact mode.
host_content="#{?#{e|>=:#{client_width},${compact_min_width}},#H,#($script_dir/compact-label #{q:host} $host_compact_chars)}"
t "@adaptive_status_host_body" "#[fg=$c_fg,bg=$c_sel,bold] ${host_content} "
t "@adaptive_status_host" "#[fg=$c_sel,bg=$c_bg]#{@pl2}#{E:@adaptive_status_host_body}"
t "@adaptive_status_metrics" "#{E:@adaptive_status_metrics_lead}#{?#{e|>=:#{client_width},${battery_min_width}},${battery_status} #{@pl3} ,}#{?#{e|>=:#{client_width},${cpu_min_width}},${cpu_status} #{@pl3} ,}#{E:@adaptive_status_host_body}"
metrics_visible="#{||:#{e|>=:#{client_width},${battery_min_width}},#{e|>=:#{client_width},${cpu_min_width}}}"
t "status-right" "${maintenance}#{?#{e|>=:#{client_width},${time_min_width}},#{E:@adaptive_status_time},}#{?#{e|>=:#{client_width},${date_min_width}},#{E:@adaptive_status_date},}#{?${metrics_visible},#{E:@adaptive_status_metrics},#{E:@adaptive_status_host}}#{?#{@workbench_window_state},#{E:@adaptive_status_agent},#{E:@adaptive_status_host_close}}"
# The session pill also owns global key-mode feedback: disabled bindings are a
# red OFF warning, prefix is blue, and the ordinary session stays green. Keep
# OFF ahead of prefix so the more important persistent state always wins.
off_mode="#{==:#{client_key_table},off}"
sess_bg="#{?${off_mode},$c_alert,#{?client_prefix,$c_info,$c_accent}}"
sess_full_content="#{?${off_mode},OFF,#S}"
sess_compact_content="#{?${off_mode},OFF,#($script_dir/compact-label #{q:session_name} $session_compact_chars)}"
t "@adaptive_status_session_full" "#[fg=$c_bg,bg=$sess_bg,bold] ${sess_full_content} #[fg=$sess_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"
t "@adaptive_status_session_compact" "#[fg=$c_bg,bg=$sess_bg,bold] ${sess_compact_content} #[fg=$sess_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"
t "status-left" "#{?#{e|>=:#{client_width},${compact_min_width}},#{E:@adaptive_status_session_full},#{E:@adaptive_status_session_compact}}"

t "window-status-format" "#[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_bg] #I #{?#{e|>=:#{client_width},${compact_min_width}},#[fg=${mark}]#{@pl1}#[fg=$c_fg] #W ,}#[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"
t "window-status-current-format" "#[fg=$c_bg,bg=$c_sel,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_sel,nobold] #I #{?#{e|>=:#{client_width},${compact_min_width}},#{@pl1} #W ,}#[fg=$c_sel,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"

# The widgets in status-right come from other plugins (battery/cpu/
# prefix-highlight) that tpm may source after this theme; re-run them so their
# format placeholders resolve, then refresh each client so a re-apply (e.g. from
# an appearance watcher) repaints immediately instead of on the next attach.
# TMUX_PLUGIN_MANAGER_PATH is commonly set with a literal leading '~' (tmux
# set-environment performs no tilde expansion), and the quoted -x test below
# won't expand it either — so without this the test silently fails and the
# battery/cpu/prefix widgets never get re-sourced, leaving their placeholders
# (#{cpu_percentage}, …) raw and rendering empty after any theme re-apply.
for p in tmux-prefix-highlight/prefix_highlight tmux-battery/battery tmux-cpu/cpu; do
   [ -x "$plug/$p.tmux" ] && "$plug/$p.tmux" >/dev/null 2>&1
done
for c in $(tmux list-clients -F '#{client_name}' 2>/dev/null); do
   tmux refresh-client -S -t "$c" 2>/dev/null || true
done
