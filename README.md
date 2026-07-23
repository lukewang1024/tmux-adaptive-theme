# tmux-adaptive-theme

A light/dark-adaptive [One Dark](https://github.com/atom/one-dark-syntax) status theme for tmux. The bar tracks the terminal's **actual background** — **One Dark** on a dark background, **Atom One Light** on a light one — and can optionally pick up the terminal's own palette so its accents match your terminal theme. It keys off the terminal, not the OS light/dark setting, so it stays correct on terminals that don't follow the OS.

Requires a terminal with [True Color](https://en.wikipedia.org/wiki/Color_depth#True_color_.2824-bit.29) and Powerline glyphs.

## Modes

`@adaptive_mode` decides where the accent colors come from (default `light`):

- **`light`** — fixed One Dark / One Light accents.
- **`full`** — the session/host pill accent and the semantic activity/bell marks are taken from the terminal's own ANSI palette, so those hues match your terminal theme. The chrome (bar bg, tab bg, body text) is unchanged — only the accent (`@adaptive_accent`, default `colour2`), the activity mark/cap (`colour3`) and the bell mark/cap (`colour1`) change.

Either way the palette follows the terminal's light/dark background — see [Appearance detection](#appearance-detection).

### Appearance detection

Light vs dark is read from the terminal's real background colour, not the OS setting. The theme can't query the terminal itself — that needs a controlling tty, which a sourced tmux plugin doesn't have — so a companion script does it: **`detect-appearance.sh`** sends an OSC 11 query, computes the background luminance, sets `@adaptive_appearance` (`light`/`dark`) and re-applies the theme.

Run it from your shell so the bar updates **automatically whenever the terminal theme changes**. For zsh, query on every prompt:

```zsh
autoload -Uz add-zsh-hook
_adaptive_theme() { ~/.local/share/tmux/plugins/tmux-adaptive-theme/detect-appearance.sh }
add-zsh-hook precmd _adaptive_theme
```

(For bash, call it from `PROMPT_COMMAND`.) It no-ops without a tty or a reply, and only re-applies when the value actually changes, so it's cheap to run each prompt. Until the first detection the theme defaults to One Dark.

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
- **`@adaptive_appearance`** — `light` | `dark`; normally set for you by `detect-appearance.sh` (defaults to `dark` until first detected). Pin it yourself to force a fixed appearance.

## Install

With [tpm](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'lukewang1024/tmux-adaptive-theme'
```

Then `prefix + I`. Load it **before** other plugins that alter the status line so they pick up its changes. Or clone it and `run-shell` the `tmux-adaptive-theme.tmux` from your `.tmux.conf`.

For automatic light/dark tracking, also wire `detect-appearance.sh` into your shell — see [Appearance detection](#appearance-detection).

## Credits

Color scheme and status layout derived from [odedlaz/tmux-onedark-theme](https://github.com/odedlaz/tmux-onedark-theme), which is based on [onedark.vim](https://github.com/joshdick/onedark.vim) / the [One Dark syntax theme](https://github.com/atom/one-dark-syntax). [MIT](LICENSE).
