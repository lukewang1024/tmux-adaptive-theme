#!/bin/sh
# Loaded only when @adaptive_time_enabled is on.
time_format=$(get @adaptive_time_format '%R')

status_module_time() {
  status_layout_item "${density}_time" 1 "$c_bg" "$c_fg" nobold "$time_format" '' ''
}
