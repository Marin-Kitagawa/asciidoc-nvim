local asciidoc = require("asciidoc")

vim.api.nvim_create_user_command(
  "AsciidocPreview",
  function()
    asciidoc.preview()
  end,
  { desc = "Open browser preview of the current AsciiDoc buffer", force = true }
)

vim.api.nvim_create_user_command(
  "AsciidocPreviewToggle",
  function()
    asciidoc.toggle_live()
  end,
  { desc = "Toggle live preview vs preview-on-save", force = true }
)

vim.api.nvim_create_user_command(
  "AsciidocPreviewMode",
  function(args)
    asciidoc.set_mode(args.args)
  end,
  { nargs = 1, desc = "Set preview mode: live or save", force = true }
)

vim.api.nvim_create_user_command(
  "AsciidocPreviewClose",
  function()
    asciidoc.close()
  end,
  { desc = "Stop previewing the current buffer", force = true }
)

vim.api.nvim_create_user_command(
  "AsciidocPreviewStatus",
  function()
    asciidoc.status()
  end,
  { desc = "Show preview status for the current buffer", force = true }
)