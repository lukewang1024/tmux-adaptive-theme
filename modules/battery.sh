#!/bin/sh
# Loaded only when @adaptive_battery_enabled is on. Content may come from
# tmux-battery placeholders or a provider's own native/async tmux format.
battery_status=$(get @adaptive_battery '')
battery_status=$(printf '%s' "$battery_status" | sed \
  -e "s|#{battery_icon}|#($plug/tmux-battery/scripts/battery_icon.sh)|g" \
  -e "s|#{battery_percentage}|#($plug/tmux-battery/scripts/battery_percentage.sh)|g")

status_module_battery() {
  [ -n "$battery_status" ] || return 0
  status_layout_item "${density}_battery" 1 "$c_sel" "$c_fg" nobold "$battery_status" '' ''
}
