# tuition 2.3.0 Release Notes

I'm pleased to announce tuition 2.3.0, a feature release of the Common Lisp library for building terminal user interfaces. This release ports another batch of recent `charmbracelet/bubbles`, `bubbletea`, and `lipgloss` work to tuition, adds three larger component features, and fixes a Kitty keyboard decoding bug.

## What's New

### Table height, overflow, and width fitting (lipgloss #620, #671)

`tuition.render.table:make-table` now honours `:width` and `:height`:

- **`:width`** — columns are expanded to fill, or shrunk to fit, the requested total width. Shrinking never collapses a column to zero (a one-column floor is kept, with a no-floor fallback for impossibly small widths).
- **`:height`** — rows are windowed to the requested height and an ellipsis (`…`) overflow row is appended to signal hidden rows.

Both are opt-in; tables without `:width`/`:height` render exactly as before.

### Viewport soft-wrapping

The viewport component gained opt-in soft-wrapping (`:soft-wrap t`): content lines wider than the viewport width wrap onto multiple visual lines, and scrolling, `scroll-percent`, and the max offset all track visual lines. Horizontal scrolling is disabled while wrapping. New helpers: `viewport-set-content-lines`, `viewport-total-visual-lines`, and the `viewport-soft-wrap` accessor.

### Paginated, filterable list component (bubbles #831/#837)

The list component was rebuilt around a paginator model:

- **Pagination** — items are laid out across pages of `list-per-page` (height) rows, with `list-page`, `list-total-pages`, and `list-items-on-page`.
- **Cursor clamping** — the cursor can never point past the last item on a page, including partial last pages and after paging (bubbles #831/#837).
- **Navigation** — `list-cursor-up` / `list-cursor-down` (advancing pages at the edges), `list-next-page` / `list-prev-page`, and `list-go-to-start` / `list-go-to-end`.
- **Filtering** — `list-set-filter` (case-insensitive substring match) and `list-reset-filter`, with `list-visible-items` reflecting the active filter.
- **Infinite scrolling** — `:infinite-scrolling t` wraps top-to-bottom and back.

The existing `list-selected`, `list-move-up` / `list-move-down`, `list-get-selected`, and `list-set-items` API continues to work.

### Textarea editing and layout (bubbles #910, #875, #1020)

- **`Ctrl-Left` / `Ctrl-Right`** move by word, and **`Ctrl-Backspace` / `Ctrl-Delete`** delete by word.
- **`textarea-line` / `textarea-column`** accessors return the zero-indexed cursor row and column.
- **`:max-content-height`** caps content growth in visual rows; inserts are trimmed and newlines blocked once the cap is reached (`textarea-at-content-limit-p`).
- **Page-up / page-down** now snap the cursor to the first / last visible line on the first press before paging by a full viewport height.

### Textinput placeholder

The placeholder is now truncated with an ellipsis when it is wider than the input, and padded with trailing spaces to the input width, matching bubbles' placeholder rendering.

### Extended Kitty keyboard enhancements (bubbletea #1626)

The declarative view can now request the full set of Kitty progressive-enhancement flags via `:keyboard-enhancements`: `:report-event-types`, `:report-alternate-keys`, `:report-all-keys-as-escapes`, and `:report-associated-text`.

On decode, key events now expose the alternate keys reported under flag 4 — `key-event-shifted-code` (the shifted key) and `key-event-base-code` (the PC-101 / base-layout key) — and the associated text reported under flag 16 becomes the event's `key-event-text`.

### Native terminal progress bar

`make-view` accepts `:progress-bar`, built with `make-progress-bar` (`:state` one of `:none`, `:default`, `:error`, `:indeterminate`, `:warning`; `:value` a 0–100 percentage). The renderer emits the OSC 9;4 taskbar-progress sequence, diffed against the previous frame, honoured by Windows Terminal, Ghostty, ConEmu, and similar terminals.

### Panic backtraces and trace files (bubbletea #1446)

The default error handler now reports a backtrace to `*error-output*` in addition to the condition. Setting the `TUITION_DEBUG` environment variable (or `tuition:*panic-log-enabled*`) also writes a `tuition-panic-<timestamp>.log` trace file.

## Bug Fixes

### Kitty modifier / event-type decoding

CSI `u` sequences with sub-parameters (e.g. `modifiers:event-type`) were decoded from a flattened sub-parameter list, which conflated the modifier and event-type values and could report the wrong press/repeat/release state. The parser now tracks sub-parameters per parameter group, so modifiers, event types, alternate keys, and associated text are decoded independently.

### Render table accepts non-string cells

`tuition.render.table` now coerces non-string cell values (numbers, symbols, etc.) to strings, matching the component table. Previously a numeric cell such as `(1 "Alice")` raised a type error during rendering.

### Sequenced-command errors no longer kill the sequence silently

An error raised by a command in a `:sequence` was previously unhandled, silently terminating the sequence thread. Sequenced commands are now wrapped like batched commands and reported through the error handler, so the sequence keeps running.

## Installation

### Via ocicl
```bash
ocicl install tuition
```

### From Source
```bash
git clone https://github.com/atgreen/tuition.git
cd tuition
# Load in your Lisp environment
```

---

For more information, visit the [tuition repository](https://github.com/atgreen/tuition) or read the [README](https://github.com/atgreen/tuition/blob/master/README.md).
