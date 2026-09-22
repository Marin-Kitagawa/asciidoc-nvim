local M = {}

local DEFAULT_CONFIG = {
  executable = "asciidoctor",
  backend = "html5",
  live = true,
  debounce_ms = 300,
  refresh = 1, -- seconds between browser auto-reloads; 0/false disables
  write_on_change = true,
  out_dir = nil, -- default: stdpath("cache") .. "/asciidoc-nvim"
  max_file_size_kb = 2048,
}

M.config = vim.deepcopy(DEFAULT_CONFIG)

--- Per-buffer state: bufnr -> { live, group, timer, rendering, want_open, last_rendered }
local state = {}

local function notify(msg, level)
  vim.notify("asciidoc-nvim: " .. msg, level or vim.log.levels.INFO)
end

local function outdir()
  local dir = M.config.out_dir or vim.fn.stdpath("cache") .. "/asciidoc-nvim"
  vim.fn.mkdir(dir, "p")
  return dir
end

local function outfile_for(bufnr)
  return outdir() .. "/preview-" .. bufnr .. ".html"
end

local function is_asciidoc_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].filetype == "asciidoc" then
    return true
  end
  local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e"):lower()
  return ext == "adoc" or ext == "asciidoc" or ext == "ad"
end

local function refresh_tag()
  local refresh = M.config.refresh
  if not refresh or refresh <= 0 then
    return nil
  end
  return string.format('<meta http-equiv="refresh" content="%d">', refresh)
end

--- Insert a <meta http-equiv="refresh"> tag after <head> if missing.
local function ensure_refresh_meta(path)
  local tag = refresh_tag()
  if not tag then
    return
  end
  local f = io.open(path, "rb")
  if not f then
    return -- output already removed (e.g. preview closed mid-render)
  end
  local data = f:read("*a")
  f:close()
  if data:find('http-equiv="refresh"', 1, true) then
    return
  end
  local out, n = data:gsub("<head>", "<head>" .. tag, 1)
  if n > 0 then
    local w = io.open(path, "wb")
    if w then
      w:write(out)
      w:close()
    end
  end
end

local function open_browser(path)
  if vim.ui and vim.ui.open then
    vim.ui.open(path)
    return
  end
  local cmd
  if vim.fn.has("win32") == 1 then
    cmd = { "cmd", "/c", "start", "", path }
  elseif vim.fn.has("mac") == 1 then
    cmd = { "open", path }
  else
    cmd = { "xdg-open", path }
  end
  vim.fn.jobstart(cmd, { detach = true })
end

local function do_render(bufnr)
  local s = state[bufnr]
  if not s or s.rendering then
    return
  end
  local input = vim.api.nvim_buf_get_name(bufnr)
  if input == "" then
    notify("buffer is not backed by a file yet; save it first", vim.log.levels.WARN)
    return
  end
  local info = vim.loop.fs_stat(input)
  if not info then
    notify("file not found on disk: " .. input, vim.log.levels.WARN)
    return
  end
  if M.config.max_file_size_kb and info.size > M.config.max_file_size_kb * 1024 then
    notify(
      "file is larger than max_file_size_kb (" .. M.config.max_file_size_kb .. "), skipping preview",
      vim.log.levels.WARN
    )
    return
  end
  local out = outfile_for(bufnr)
  s.rendering = true
  vim.system(
    { M.config.executable, "-b", M.config.backend, "-o", out, input },
    { text = true },
    function(res)
      s.rendering = false
      if state[bufnr] ~= s then
        return -- preview was closed while rendering
      end
      if res.code ~= 0 then
        local err = vim.trim(res.stderr or res.stdout or "no output")
        notify(M.config.executable .. " failed:\n" .. err, vim.log.levels.ERROR)
        return
      end
      ensure_refresh_meta(out)
      s.last_rendered = out
      if s.want_open then
        s.want_open = false
        open_browser(out)
      end
    end
  )
end

local function render_now(bufnr)
  local s = state[bufnr]
  if not s then
    return
  end
  if s.live and M.config.write_on_change and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent update")
    end)
  end
  do_render(bufnr)
end

local function schedule_render(bufnr)
  local s = state[bufnr]
  if not s then
    return
  end
  if s.timer then
    s.timer:stop()
  else
    s.timer = vim.uv.new_timer()
  end
  s.timer:start(M.config.debounce_ms, 0, function()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state[bufnr] then
        render_now(bufnr)
      end
    end)
  end)
end

local function setup_autocmds(bufnr)
  local s = state[bufnr]
  if not s then
    return
  end
  local group = vim.api.nvim_create_augroup("AsciidocPreviewBuf" .. bufnr, { clear = true })
  s.group = group
  local events = { "TextChanged", "TextChangedI", "InsertLeave", "BufWritePost" }
  if not s.live then
    events = { "BufWritePost" }
  end
  for _, ev in ipairs(events) do
    vim.api.nvim_create_autocmd(ev, {
      group = group,
      buffer = bufnr,
      desc = "asciidoc-nvim render",
      callback = function()
        schedule_render(bufnr)
      end,
    })
  end
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    desc = "asciidoc-nvim cleanup",
    callback = function()
      M.close(bufnr)
    end,
  })
end

--- Open (or re-open) the browser preview for an asciidoc buffer.
function M.preview(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not is_asciidoc_buf(bufnr) then
    notify(vim.api.nvim_buf_get_name(bufnr) .. " is not an AsciiDoc file", vim.log.levels.WARN)
    return
  end
  local s = state[bufnr]
  if not s then
    s = { live = M.config.live, want_open = true }
    state[bufnr] = s
    setup_autocmds(bufnr)
  else
    s.want_open = true
  end
  render_now(bufnr)
end

--- Toggle between live preview and preview-on-save for a buffer.
function M.toggle_live(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state[bufnr]
  if not s then
    notify("no preview for this buffer; run :AsciidocPreview first", vim.log.levels.INFO)
    return
  end
  s.live = not s.live
  setup_autocmds(bufnr)
  render_now(bufnr)
  notify("preview mode -> " .. (s.live and "live" or "on save") .. " (buffer " .. bufnr .. ")")
end

--- Explicitly set the preview mode for a buffer: "live" or "save".
function M.set_mode(mode, bufnr)
  if mode ~= "live" and mode ~= "save" then
    notify("mode must be \"live\" or \"save\"", vim.log.levels.ERROR)
    return
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state[bufnr]
  if not s then
    M.preview(bufnr)
    s = state[bufnr]
  end
  if s then
    s.live = mode == "live"
    setup_autocmds(bufnr)
    render_now(bufnr)
    notify("preview mode -> " .. mode .. " (buffer " .. bufnr .. ")")
  end
end

--- Stop previewing a buffer and clean up its temp files.
function M.close(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state[bufnr]
  if not s then
    return
  end
  if s.group then
    vim.api.nvim_del_augroup_by_id(s.group)
  end
  if s.timer then
    s.timer:stop()
    s.timer:close()
  end
  vim.fn.delete(outfile_for(bufnr))
  if s.last_rendered then
    vim.fn.delete(s.last_rendered)
  end
  state[bufnr] = nil
end

--- Print the current preview status for a buffer.
function M.status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state[bufnr]
  if not s then
    notify("no preview active for buffer " .. bufnr, vim.log.levels.INFO)
    return
  end
  notify(string.format("buffer %d: mode=%s output=%s", bufnr, s.live and "live" or "on save", s.last_rendered or "not rendered yet"))
end

--- Merge user configuration into the defaults.
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
end

return M