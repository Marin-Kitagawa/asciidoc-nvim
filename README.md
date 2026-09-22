# asciidoc-nvim

Live AsciiDoc preview for Neovim, rendered with the `asciidoctor` CLI into a
browser tab. Supports both **live** preview (re-renders as you type) and
**preview-on-save** modes.

## Requirements

- Neovim >= 0.10 (uses `vim.system`)
- [asciidoctor](https://asciidoctor.org) CLI on `PATH`
  - Ruby gem install: `gem install asciidoctor`

## Installation

Via lazy.nvim:

```lua
{
  "Marin-Kitagawa/asciidoc-nvim",
  ft = "asciidoc",
  config = function()
    require("asciidoc").setup({})
  end,
}
```

Via packer.nvim:

```lua
use {
  "Marin-Kitagawa/asciidoc-nvim",
  ft = "asciidoc",
  config = function()
    require("asciidoc").setup({})
  end,
}
```

## Usage

Open an `.adoc` / `.asciidoc` / `.ad` file (or one with `filetype=asciidoc`)
and run:

| Command                   | Action                                            |
| ------------------------- | ------------------------------------------------- |
| `:AsciidocPreview`        | Render and open the preview in your browser       |
| `:AsciidocPreviewToggle`  | Switch between live preview and preview-on-save   |
| `:AsciidocPreviewMode X`  | Set mode explicitly: `live` or `save`             |
| `:AsciidocPreviewStatus`  | Show the current buffer's preview status          |
| `:AsciidocPreviewClose`   | Stop previewing and delete the temp HTML          |

Example mappings:

```lua
vim.keymap.set("n", "<leader>ap", ":AsciidocPreview<CR>")
vim.keymap.set("n", "<leader>at", ":AsciidocPreviewToggle<CR>")
```

### Modes

- **Live** (default): re-renders on `TextChanged` / `TextChangedI` /
  `InsertLeave` and `BufWritePost`, debounced. When `write_on_change` is
  enabled (default) the buffer is written to disk before each render so the
  preview always reflects your current editing. The generated page contains a
  `<meta http-equiv="refresh">` tag so the browser auto-reloads.
- **On save**: re-renders only on `BufWritePost`.

Auto-preview when opening an AsciiDoc file can be enabled with
`setup { auto_preview = true }`.

## Configuration

```lua
require("asciidoc").setup({
  auto_preview = false,      -- open the preview automatically on ft=asciidoc
  executable = "asciidoctor", -- asciidoctor binary on PATH
  backend = "html5",          -- asciidoctor backend
  live = true,                -- default mode for new previews
  debounce_ms = 300,          -- debounce between live re-renders
  refresh = 1,                -- browser auto-reload interval (seconds); 0 disables
  write_on_change = true,     -- write the buffer before rendering in live mode
  out_dir = nil,              -- temp HTML output dir (nil = stdpath("cache") .. "/asciidoc-nvim")
  max_file_size_kb = 2048,    -- skip rendering files larger than this
})
```

## How it works

`render` shells out to `asciidoctor -b <backend> -o <temp>.html <file>` via
`vim.system`. On success a refresh meta tag is injected (if enabled) and the
page is opened with `vim.ui.open` (Windows/macOS/Linux). Preview state and
autocommands are tracked per buffer and cleaned up automatically when the
buffer is wiped.

## License

MIT