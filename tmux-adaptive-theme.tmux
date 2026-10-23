#!/bin/sh
# tmux-adaptive-theme — a light/dark-adaptive One Dark status theme for tmux.
#
# The palette tracks the terminal's own background — One Dark on a dark
# background, Atom One Light on a light one — and can also pick up the terminal's
# ANSI colors:
#   * @adaptive_mode = light | full — `light` keeps fixed One Dark/Light accents;
#     `full` takes the accent + semantic warn/alert marks from the terminal's own
#     ANSI palette.
#   * Context state colours mark the fixed full-height #I/#W separator.
#     Terminal activity and bells do not affect window tab styling.
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
tmux set-option -gq @adaptive_theme_dir "$(CDPATH='' cd "$_dir" && pwd -P)"
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
# Keep activity/bell tabs neutral; separator colours reflect context state.
tw "window-status-activity-style" "fg=$c_fg,bg=$c_bg,none"
tw "window-status-bell-style" "fg=$c_fg,bg=$c_bg,none"
tw "window-status-separator" ""

# OSC 11 replies use the pane's default background. Leaving it unset lets
# tmux borrow another attached client's background, even in the opposite mode.
t "window-style" "fg=$c_dim,bg=$c_bg"
t "window-active-style" "fg=$c_fg,bg=$c_bg"

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
cpu_status=$(get "@adaptive_cpu" "$(get "@adaptive_widgets" "")")
cpu_range_open=$(get "@adaptive_cpu_range_open" "")
cpu_range_close=$(get "@adaptive_cpu_range_close" "")
# CPU plugins only interpolate placeholders found directly in
# status-right. Resolve them before composing the responsive metric sections.
cpu_status=$(printf '%s' "$cpu_status" | sed \
   -e "s|#{cpu_percentage}|#($plug/tmux-cpu/scripts/cpu_percentage.sh)|g" \
   -e "s|#{cpu_icon}|#($plug/tmux-cpu/scripts/cpu_icon.sh)|g")
cpu_min_width=$(get "@adaptive_cpu_min_width" "0")
script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
# Optional metadata modules are opt-in. Width controls density, not whether a
# requested module exists. Disabled modules neither load nor register producers.
optional_modules=''
for status_module in time date battery; do
  if [ "$(get "@adaptive_${status_module}_enabled" off)" = on ]; then
    . "$script_dir/modules/$status_module.sh"
    optional_modules="$optional_modules $status_module"
  fi
done

# --- status layout -----------------------------------------------------------
# Providers declare content and visibility; one compiler owns all boundaries.
context_state=$(get "@adaptive_context_state" "")
context_label=$(get "@adaptive_context_label" "")
context_icon=$(get "@adaptive_context_icon" "#{@adaptive_agent_icon}")
context_suffix=$(get "@adaptive_context_suffix" "")
context_range_open=$(get "@adaptive_context_range_open" "")
context_range_close=$(get "@adaptive_context_range_close" "")
context_visible=$(get "@adaptive_context_visible" "#{!=:${context_state},}")
host_bg="#{?${context_visible},$c_sel,$c_accent}"
host_fg="#{?${context_visible},$c_fg,$c_bg}"
usage_range_open=$(get "@adaptive_usage_range_open" "")
usage_range_close=$(get "@adaptive_usage_range_close" "")
host_icon=$(get "@adaptive_host_icon" "󰍹")
host_range_open=$(get "@adaptive_host_range_open" "")
host_range_close=$(get "@adaptive_host_range_close" "")
session_range_open=$(get "@adaptive_session_range_open" "")
session_range_close=$(get "@adaptive_session_range_close" "")
context_bg="#{?#{==:${context_state},blocked},$c_alert,#{?#{==:${context_state},working},$c_warn,#{?#{==:${context_state},done},$c_info,#{?#{==:${context_state},idle},$c_accent,$c_dim}}}}"
context_mark="#{?#{==:${context_state},blocked},!,#{?#{==:${context_state},working},●,#{?#{==:${context_state},done},✓,#{?#{==:${context_state},idle},○,?}}}}"
# Use the same semantic colour as the context capsule. A completion bell must
# not turn a provider's blue done state into a red alert.
mark="#{?${context_visible},${context_bg},$c_fg}"
tab_marker="#[fg=${mark}]#{@pl1}#[fg=$c_fg]"
# Compile two fixed-control variants once. Width decisions are native formats:
# window names, counts and client sizes update without a process or scan.
. "$script_dir/lib/status-layout.sh"
off_mode="#{==:#{client_key_table},off}"
prefix_mode="#{==:#{client_key_table},prefix}"
sess_bg="#{?${off_mode},$c_alert,#{?${prefix_mode},$c_info,$c_accent}}"
sess_fg=$c_bg
sess_full_content="#{?${off_mode},OFF,#S}"
sess_compact_content="#{?${off_mode},OFF,#{=/6/…:session_name}}"
cpu_compact_status=$(get "@adaptive_cpu_compact" "$cpu_status")
for density in full compact; do
  status_layout_begin
  for status_module in $optional_modules; do
    "status_module_$status_module"
  done
  if [ "$density" = full ]; then
    host_content="${host_icon} #H"
    context_content="${context_icon} ${context_label}"
    if [ -n "$context_suffix" ]; then
      context_content="${context_content}${context_range_close} ${usage_range_open}${context_suffix}${usage_range_close}"
    fi
    session_content=$sess_full_content
    cpu_content=$cpu_status
  else
    host_content=$host_icon
    context_content="${context_icon} ${context_mark}"
    session_content=$sess_compact_content
    cpu_content=$cpu_compact_status
  fi
  if [ -n "$cpu_status" ]; then
    status_layout_item "${density}_cpu" "#{e|>=:#{client_width},${cpu_min_width}}" "$c_sel" "$c_fg" nobold "$cpu_content" "$cpu_range_open" "$cpu_range_close"
  fi
  status_layout_item "${density}_host" 1 "$host_bg" "$host_fg" bold "$host_content" "$host_range_open" "$host_range_close"
  status_layout_item "${density}_context" "$context_visible" "$context_bg" "$c_bg" bold "$context_content" "$context_range_open" "$context_range_close"
  status_layout_end
  t "@adaptive_${density}_right" "${maintenance}${status_layout}"
  t "@adaptive_${density}_right_width_probe" "${maintenance}${status_width_probe}"
  status_layout_begin left
  status_layout_item "${density}_session" 1 "$sess_bg" "$sess_fg" bold "$session_content" "$session_range_open" "$session_range_close"
  for status_slot in 2 1 3; do
    status_icon=$(get "@adaptive_action_${status_slot}_icon" "")
    status_range=$(get "@adaptive_action_${status_slot}_range" "")
    status_on=$(get "@adaptive_action_${status_slot}_visible" "1")
    status_active=$(get "@adaptive_action_${status_slot}_active" "")
    status_colour=$c_fg
    status_weight=nobold
    if [ -n "$status_active" ]; then
      status_colour="#{?${status_active},$c_accent,$c_dim}"
      status_weight="#{?${status_active},bold,nobold}"
    fi
    status_layout_item "${density}_action${status_slot}" "#{&&:#{!=:${status_icon},},#{==:${status_on},1}}" "$c_sel" "$status_colour" "$status_weight" "$status_icon" "#[range=user|${status_range}]" '#[range=]'
  done
  status_layout_end
  # The powerline cap itself is the gap; add no extra blank cells.
  t "@adaptive_${density}_left" "$status_layout"
  t "@adaptive_${density}_left_width_probe" "$status_width_probe"
done
# Only the two control groups inspect total window-name demand. Each tab has a
# constant-cost equal-share budget, so rendering N windows is O(N), not O(N²).
# Width probes contain text only; measuring the paint tree repeatedly used to
# amplify its nested visibility/colour expressions on every window label.
t @adaptive_full_tabs_width '#{w:#{W: #I  #W }}'
t @adaptive_full_fixed_width '#{e|+:#{w:#{T:@adaptive_full_left_width_probe}},#{w:#{T:@adaptive_full_right_width_probe}}}'
t @adaptive_compact_fixed_width '#{e|+:#{w:#{T:@adaptive_compact_left_width_probe}},#{w:#{T:@adaptive_compact_right_width_probe}}}'
t @adaptive_controls_full '#{||:#{==:#{client_width},0},#{e|>=:#{client_width},#{e|+:#{E:@adaptive_full_fixed_width},#{E:@adaptive_full_tabs_width}}}}'
t @adaptive_tabs_budget '#{e|-:#{client_width},#{E:@adaptive_compact_fixed_width}}'
# Demand telemetry remains available, but must never be a tab-render dependency.
t @adaptive_tabs_full '#{e|>=:#{E:@adaptive_tabs_budget},#{E:@adaptive_full_tabs_width}}'
t @adaptive_tab_name_limit '#{e|-:#{e|/:#{E:@adaptive_tabs_budget},#{session_windows}},#{e|+:7,#{w:window_index}}}'
t @adaptive_tab_trim_limit '#{e|-:#{E:@adaptive_tab_name_limit},1}'
t @adaptive_tab_label '#{=/#{E:@adaptive_tab_trim_limit}/…:window_name}'
t @adaptive_tab_text " #I#{?#{e|>=:#{E:@adaptive_tab_name_limit},4}, ${tab_marker} #{E:@adaptive_tab_label},} "
t status-left '#{?#{E:@adaptive_controls_full},#{T:@adaptive_full_left},#{T:@adaptive_compact_left}}'
t status-right '#{?#{E:@adaptive_controls_full},#{T:@adaptive_full_right},#{T:@adaptive_compact_right}}'
t "@adaptive_status_session_full" "${session_range_open}#[fg=$sess_fg,bg=$sess_bg,bold] ${sess_full_content} ${session_range_close}#[default]"
t "@adaptive_status_session_compact" "${session_range_open}#[fg=$sess_fg,bg=$sess_bg,bold] ${sess_compact_content} ${session_range_close}#[default]"
t "window-status-format" "#[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_bg]#{E:@adaptive_tab_text}#[fg=$c_bg,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"
t "window-status-current-format" "#[fg=$c_bg,bg=$c_sel,nobold,nounderscore,noitalics]#{@pl0}#[fg=$c_fg,bg=$c_sel,nobold]#{E:@adaptive_tab_text}#[fg=$c_sel,bg=$c_bg,nobold,nounderscore,noitalics]#{@pl0}"

# The widgets in status-right come from battery/cpu plugins that tpm may source
# after this theme; re-run them so their
# format placeholders resolve, then refresh each client so a re-apply (e.g. from
# an appearance watcher) repaints immediately instead of on the next attach.
# TMUX_PLUGIN_MANAGER_PATH is commonly set with a literal leading '~' (tmux
# set-environment performs no tilde expansion), and the quoted -x test below
# won't expand it either — so without this the test silently fails and the
# battery/cpu widgets never get re-sourced, leaving their placeholders
# (#{cpu_percentage}, …) raw and rendering empty after any theme re-apply.
widget_plugins=tmux-cpu/cpu
case " $optional_modules " in
  *' battery '*) widget_plugins="$widget_plugins tmux-battery/battery" ;;
esac
for p in $widget_plugins; do
   [ -x "$plug/$p.tmux" ] && "$plug/$p.tmux" >/dev/null 2>&1
done
for c in $(tmux list-clients -F '#{client_name}' 2>/dev/null); do
   tmux refresh-client -S -t "$c" 2>/dev/null || true
done
