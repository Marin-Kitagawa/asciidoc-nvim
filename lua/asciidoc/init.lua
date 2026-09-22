local preview = require("asciidoc.preview")

local M = {}

M.version = "0.1.0"

--- Configure the plugin.
---@param opts? asciidoc.Config
function M.setup(opts)
  preview.setup(opts)
  if opts and opts.auto_preview then
    pcall(vim.api.nvim_create_autocmd, "FileType", {
      pattern = "asciidoc",
      desc = "asciidoc-nvim auto preview",
      callback = function(event)
        M.preview(event.buf)
      end,
    })
  end
end

--- Open a browser preview of an asciidoc buffer.
---@param bufnr? integer
function M.preview(bufnr)
  preview.preview(bufnr)
end

--- Toggle live preview <-> preview on save.
---@param bufnr? integer
function M.toggle_live(bufnr)
  preview.toggle_live(bufnr)
end

--- Set the preview mode explicitly: "live" or "save".
---@param mode "live"|"save"
---@param bufnr? integer
function M.set_mode(mode, bufnr)
  preview.set_mode(mode, bufnr)
end

--- Stop previewing and remove temp files.
---@param bufnr? integer
function M.close(bufnr)
  preview.close(bufnr)
end

--- Show preview status for a buffer.
---@param bufnr? integer
function M.status(bufnr)
  preview.status(bufnr)
end

return M