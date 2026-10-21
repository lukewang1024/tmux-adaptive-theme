#!/bin/sh
# Loaded only when @adaptive_date_enabled is on.
date_format=$(get @adaptive_date_format '%d/%m/%Y')

status_module_date() {
  status_layout_item "${density}_date" 1 "$c_bg" "$c_fg" nobold "$date_format" '' ''
}
