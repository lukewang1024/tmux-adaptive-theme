# tmux-adaptive-theme

A light/dark-adaptive [One Dark](https://github.com/atom/one-dark-syntax) status theme for tmux. The bar tracks the terminal's **actual background** — **One Dark** on a dark background, **Atom One Light** on a light one — and can optionally pick up the terminal's own palette so its accents match your terminal theme. It keys off the terminal, not the OS light/dark setting, so it stays correct on terminals that don't follow the OS.

Requires a terminal with [True Color](https://en.wikipedia.org/wiki/Color_depth#True_color_.2824-bit.29) and Powerline glyphs.

## Modes

`@adaptive_mode` decides where the accent colors come from (default `light`):

- **`light`** — fixed One Dark / One Light accents.
- **`full`** — the session/host pill accent and the semantic activity/bell marks are taken from the terminal's own ANSI palette, so those hues match your terminal theme. The chrome (bar bg, tab bg, body text) is unchanged — only the accent (`@adaptive_accent`, default `colour2`), the activity mark/cap (`colour3`) and the bell mark/cap (`colour1`) change.

Either way the palette follows the terminal's light/dark background — see [Appearance detection](#appearance-detection).

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
set -g @adaptive_widgets     "#{battery_icon} #{battery_percentage}  CPU #{cpu_percentage}"
set -g @adaptive_time_format '%R'
set -g @adaptive_date_format '%a %d %b'
```

- **`@adaptive_widgets`** — content shown on the right, before the host pill (default empty). Placeholders like `#{battery_percentage}` are provided by other plugins (e.g. [tmux-battery](https://github.com/tmux-plugins/tmux-battery), [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu)).
- **`@adaptive_time_format`** / **`@adaptive_date_format`** — [strftime](http://man7.org/linux/man-pages/man3/strftime.3.html) formats (defaults `%R`, `%d/%m/%Y`).
- **`@adaptive_accent`** — accent color for the session/host pill in `full` mode (default `colour2`).
- **`@adaptive_appearance`** — `light` | `dark`; normally set for you by the native theme hooks (or `detect-appearance.sh` as a fallback), defaulting to `dark` until first detected. Pin it yourself to force a fixed appearance.

## Install

With [tpm](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'lukewang1024/tmux-adaptive-theme'
```

Then `prefix + I`. Load it **before** other plugins that alter the status line so they pick up its changes. Or clone it and `run-shell` the `tmux-adaptive-theme.tmux` from your `.tmux.conf`.

On tmux ≥ 3.5 with a mode-2031 terminal, light/dark tracking is automatic with no extra setup. On older terminals, wire `detect-appearance.sh` into your shell for automatic tracking — see [Appearance detection](#appearance-detection).

## Credits

Color scheme and status layout derived from [odedlaz/tmux-onedark-theme](https://github.com/odedlaz/tmux-onedark-theme), which is based on [onedark.vim](https://github.com/joshdick/onedark.vim) / the [One Dark syntax theme](https://github.com/atom/one-dark-syntax). [MIT](LICENSE).
