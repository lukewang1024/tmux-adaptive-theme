# tmux-adaptive-theme

A light/dark-adaptive [One Dark](https://github.com/atom/one-dark-syntax) status theme for tmux. The bar tracks the terminal's **actual background** — **One Dark** on a dark background, **Atom One Light** on a light one — and can optionally pick up the terminal's own palette so its accents match your terminal theme. It keys off the terminal, not the OS light/dark setting, so it stays correct on terminals that don't follow the OS.

Requires a terminal with [True Color](https://en.wikipedia.org/wiki/Color_depth#True_color_.2824-bit.29) and Powerline glyphs.

## Modes

`@adaptive_mode` decides where the accent colors come from (default `light`):

- **`light`** — fixed One Dark / One Light accents.
- **`full`** — the session/host pill accent and the semantic activity/bell marks are taken from the terminal's own ANSI palette, so those hues match your terminal theme. The chrome (bar bg, tab bg, body text) is unchanged — only the accent (`@adaptive_accent`, default `colour2`), the activity mark/cap (`colour3`) and the bell mark/cap (`colour1`) change.

Either way the palette follows the terminal's light/dark background — see [Appearance detection](#appearance-detection).

Pane backgrounds also follow the resolved palette. This makes tmux's OSC 11
background replies agree with its appearance when several terminals with
different themes attach to the same server. Applications such as Codex and
TraeX therefore detect the same light/dark mode as the status bar.

### Appearance detection

Light vs dark is read from the terminal's real theme, not the OS setting. There are two paths, and the theme is happy with whichever your terminal supports.

**Primary — native theme reporting (tmux ≥ 3.5, zero setup).** Modern terminals implement [DEC private mode 2031](https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036) ("color-scheme update notifications"): they *push* a notification the instant their theme flips. tmux negotiates mode 2031 with the outer terminal and fires its built-in `client-light-theme` / `client-dark-theme` hooks; this plugin wires those to set `@adaptive_appearance` and re-apply. It's **push-based (no polling), needs no tty, and relays through SSH and nested tmux** — a remote tmux's hooks fire from the real local terminal's theme. Nothing to configure; it's set up when the plugin loads. Supported by kitty ≥ 0.35, recent iTerm2, Ghostty, WezTerm, foot, Contour, Rio, and others.

Check whether your terminal supports it:

```sh
tmux display-message -p '#{client_theme}'   # prints light/dark if supported, empty if not
```

**Fallback — OSC 11 query (`detect-appearance.sh`).** For terminals *without* mode 2031 (e.g. Apple Terminal.app, older clients), a companion script sends an OSC 11 query, computes the background luminance, and routes the result through the same apply path. It needs a controlling tty, so run it from your shell. For zsh, query on every prompt:

```zsh
autoload -Uz add-zsh-hook
_adaptive_theme() { ~/.local/share/tmux/plugins/tmux-adaptive-theme/detect-appearance.sh }
add-zsh-hook precmd _adaptive_theme
```

(For bash, call it from `PROMPT_COMMAND`.) It no-ops without a tty or a reply, and only re-applies when the value actually changes. Until the first detection the theme defaults to One Dark.

### The appearance state file

On every apply the theme publishes the resolved value (`light`/`dark`) to **`${XDG_STATE_HOME:-~/.local/state}/appearance`** (atomic write, only on change). This is a per-host signal other tools can follow without querying the terminal themselves — for example an editor flipping its own light/dark background in lock-step with the bar. Because tmux consumes the mode-2031 report and does **not** forward it to programs running in its panes, a file is the reliable way to reach them; watch it (e.g. with libuv `fs_event`) and react.

### Activity and bell

A window's `#I`/`#W` separator turns yellow on activity and red on a bell, instead of the default reverse-video banner.

## Options

Set these in your `.tmux.conf`:

```tmux
set -g @adaptive_mode        full        # light | full
set -g @adaptive_cpu         "CPU #{cpu_percentage}"
set -g @adaptive_time_enabled on
set -g @adaptive_time_format '%R'
set -g @adaptive_date_enabled on
set -g @adaptive_date_format '%a %d %b'
set -g @adaptive_battery_enabled on
set -g @adaptive_battery     "#{battery_icon} #{battery_percentage}"
```

- **`@adaptive_cpu`** — CPU content before the host pill (default empty; `@adaptive_widgets` remains a fallback). `#{cpu_percentage}` and `#{cpu_icon}` use [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu).
- **`@adaptive_time_enabled`**, **`@adaptive_date_enabled`**, **`@adaptive_battery_enabled`** — independent `on` / `off` switches, all defaulting to `off`.
- **`@adaptive_time_format`** / **`@adaptive_date_format`** — [strftime](http://man7.org/linux/man-pages/man3/strftime.3.html) formats (defaults `%R`, `%d/%m/%Y`).
- **`@adaptive_battery`** — battery content (default empty). `#{battery_icon}` and `#{battery_percentage}` require [tmux-battery](https://github.com/tmux-plugins/tmux-battery); custom tmux formats or `#(...)` producers also work. Empty content adds no item.
- **`@adaptive_accent`** — accent color for the session/host pill in `full` mode (default `colour2`).
- **`@adaptive_appearance`** — `light` | `dark`; normally set for you by the native theme hooks (or `detect-appearance.sh` as a fallback), defaulting to `dark` until first detected. Pin it yourself to force a fixed appearance.

Time, date and battery live in separate `modules/*.sh` files and load only when
enabled. They use the same layout compiler as the other status items and remain
present in both full and compact layouts. Disabled modules take no space, add no
separator and do not start producers. `@adaptive_maintenance` stays unconditional.
After changing module switches or content, reapply `tmux-adaptive-theme.tmux`.

The old `@adaptive_time_min_width`, `@adaptive_date_min_width` and
`@adaptive_battery_min_width` options are no longer read. Replace threshold-based
hiding (such as `9999`) with `off`; set `on` explicitly for modules you want to
retain. CPU keeps its provider's existing width policy. Run
`python3 test/status-modules.py` to check module combinations and reloads.

### Context provider interface

The theme exposes a generic right-side context capsule for optional provider
plugins. It assigns no Agent or workflow meaning to the values. A provider may
set the following options before the theme loads:

```tmux
set -g @adaptive_context_state       'working'
set -g @adaptive_context_label       'build'
set -g @adaptive_context_icon        '●'
set -g @adaptive_context_suffix      ' 42%'
set -g @adaptive_context_range_open  '#[range=user|provider]'
set -g @adaptive_context_range_close '#[range=]'
```

`state` recognizes `blocked`, `working`, `done`, and `idle` for semantic
colors; an empty state hides the context capsule. Values remain recursive tmux
formats, so a provider can point them at its own window options. A provider
loaded later can read `@adaptive_theme_dir` and run
`$dir/tmux-adaptive-theme.tmux` once after registration. Subsequent theme
repaints preserve the interface without knowing which provider supplied it.

Action providers may set `@adaptive_action_1_visible` through
`@adaptive_action_3_visible` to a tmux format returning `1` or `0` (default `1`).
The condition wraps the whole item, including its separator and mouse range,
so a hidden action leaves no clickable blank space. Pane-local options and
`client_width` are evaluated at render time without reapplying the theme.


`@adaptive_context_visible` may override context visibility with a tmux boolean
format. `@adaptive_context_suffix` stays inside the status surface; optional
`@adaptive_usage_range_open` and `@adaptive_usage_range_close` give that suffix
an independent mouse target.

The layout compiler in `lib/status-layout.sh` accepts ordered items with content,
visibility, surface colours and mouse ranges. It generates native tmux formats
that derive each separator from the previous visible surface. No external
renderer runs during a status refresh. Separators and closing caps are outside
all mouse regions. Run `python3 test/status-layout.py` to verify colour adjacency
and hit regions across light/dark and hidden-item combinations.

The left group has no added blank gap before the window tabs. Layout density
is chosen from the actual display width of all window names and the fixed
controls, per client. Under pressure, Session and Host shorten, CPU uses the
provider's optional `@adaptive_cpu_compact`, and Agent status drops its label
and usage. Window names then truncate with an ellipsis; narrower tabs show
only their index. CJK names use terminal display cells. Enabled metadata modules
stay visible; CPU keeps its minimum-width setting.

The session label keeps its key-mode colours: normal uses the accent background,
prefix uses blue, and OFF uses red, independently of Sidebar visibility.

Action providers can set `@adaptive_action_N_active` to a boolean format.
Active controls use the accent foreground and bold weight; inactive controls
use the dim foreground, with identical geometry and click ranges. Native tmux status
styles have no hover state; this theme does not poll pointer positions.
Run `python3 test/responsive-width.py` for the width-pressure checks.

## Install

With [tpm](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'lukewang1024/tmux-adaptive-theme'
```

Then `prefix + I`. Load it **before** other plugins that alter the status line so they pick up its changes. Or clone it and `run-shell` the `tmux-adaptive-theme.tmux` from your `.tmux.conf`.

On tmux ≥ 3.5 with a mode-2031 terminal, light/dark tracking is automatic with no extra setup. On older terminals, wire `detect-appearance.sh` into your shell for automatic tracking — see [Appearance detection](#appearance-detection).

## Credits

Color scheme and status layout derived from [odedlaz/tmux-onedark-theme](https://github.com/odedlaz/tmux-onedark-theme), which is based on [onedark.vim](https://github.com/joshdick/onedark.vim) / the [One Dark syntax theme](https://github.com/atom/one-dark-syntax). [MIT](LICENSE).
