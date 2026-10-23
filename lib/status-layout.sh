#!/bin/sh
# Compile visible items into tmux formats. No process runs at status refresh.
status_layout_begin() {
  status_layout=''
  status_width_probe=''
  status_direction=${1:-right}
  status_previous_bg=$c_bg
  status_previous_visible='#{==:0,1}'
}

# id, visible format, background, foreground, attributes, content, range open/close
status_layout_item() {
  status_id=$1 status_visible=$2 status_bg=$3 status_fg=$4
  status_attributes=$5 status_content=$6 status_range_open=$7 status_range_close=$8
  case "$status_visible" in
    1) status_visible='#{==:1,1}' ;;
    0) status_visible='#{==:0,1}' ;;
  esac
  # Measure content once, without expanding the recursive paint/boundary tree.
  # Reserve configured items even when a window-local condition hides them:
  # tab budgets must not depend on which window is currently being formatted.
  # One boundary cell plus both padding cells is a conservative upper bound.
  if [ -n "$status_content" ] && [ "$status_visible" != '#{==:0,1}' ]; then
    status_width_probe="${status_width_probe}| ${status_content} "
  fi
  # Boundaries are outside all mouse ranges. Their colours depend solely on
  # the previous visible surface, regardless of item order or visibility.
  if [ "$status_direction" = left ]; then
    t "@adaptive_item_${status_id}_boundary" "#[range=]#{?${status_previous_visible},#{?#{==:${status_bg},${status_previous_bg}},#[fg=$c_dim#,bg=${status_bg}#,nobold]#{@pl1},#[fg=${status_previous_bg}#,bg=${status_bg}#,nobold]#{@pl0}},}"
  else
    t "@adaptive_item_${status_id}_boundary" "#[range=]#{?#{==:${status_bg},${status_previous_bg}},#{?${status_previous_visible},#[fg=$c_dim#,bg=${status_bg}#,nobold]#{@pl3},},#[fg=${status_bg}#,bg=${status_previous_bg}#,nobold]#{@pl2}}"
  fi
  t "@adaptive_item_${status_id}_body" "${status_range_open}#[fg=${status_fg},bg=${status_bg},${status_attributes},nounderscore,noitalics] ${status_content}#[fg=${status_fg},bg=${status_bg},${status_attributes},nounderscore,noitalics] ${status_range_close}"
  t "@adaptive_item_${status_id}_after_bg" "#{?${status_visible},${status_bg},${status_previous_bg}}"
  t "@adaptive_item_${status_id}_after_visible" "#{||:${status_previous_visible},${status_visible}}"
  status_layout="${status_layout}#{?${status_visible},#{E:@adaptive_item_${status_id}_boundary}#{E:@adaptive_item_${status_id}_body},}"
  status_previous_bg="#{E:@adaptive_item_${status_id}_after_bg}"
  status_previous_visible="#{E:@adaptive_item_${status_id}_after_visible}"
}

status_layout_end() {
  # The left group points into the window gap; the right screen edge is flat.
  if [ "$status_direction" = left ]; then
    status_layout="${status_layout}#[range=]#{?#{!=:${status_previous_bg},$c_bg},#[fg=${status_previous_bg}#,bg=$c_bg#,nobold]#{@pl0},}"
  fi
  status_layout="${status_layout}#[range=]#[default]"
}
