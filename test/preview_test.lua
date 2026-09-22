local ROOT = vim.fn.getcwd()
local scratch = vim.fn.stdpath("cache") .. "/asciidoc-nvim-test"
vim.fn.delete(scratch, "rf")
vim.fn.mkdir(scratch, "p")
local outdir = scratch .. "/out"
local fixture = scratch .. "/basic.adoc"
local fixture2 = scratch .. "/second.adoc"
local function copy(src, dst)
  vim.fn.writefile(vim.fn.readfile(src), dst)
end
copy(ROOT .. "/test/fixtures/basic.adoc", fixture)
copy(ROOT .. "/test/fixtures/second.adoc", fixture2)

local passed = 0
local function ok(cond, msg)
  if not cond then
    error("ASSERT FAILED: " .. msg, 2)
  end
  passed = passed + 1
end

if vim.ui then
  vim.ui.open = function(path)
    _G.__opened = path
  end
end

local function html_path(buf)
  return outdir .. "/preview-" .. buf .. ".html"
end

local function html_content(buf)
  local p = html_path(buf)
  if vim.fn.filereadable(p) ~= 1 then
    return nil
  end
  return table.concat(vim.fn.readfile(p), "\n")
end

local function wait_for(fn, timeout, msg)
  local ok_ = vim.wait(timeout or 15000, fn, 25)
  ok(ok_, msg or "timeout waiting for condition")
  return true
end

-- 1. Verify default executable resolves on PATH (libuv spawn of .bat on Windows).
local asciidoc = require("asciidoc")
asciidoc.setup({ out_dir = outdir })
local probe = vim.system({ "asciidoctor", "--version" }, { text = true }):wait(15000)
ok(probe.code == 0, "asciidoctor did not run on PATH: " .. vim.inspect(probe))

-- 2. Commands defined by plugin/asciidoc.lua.
ok(vim.fn.exists(":AsciidocPreview") == 2, "AsciidocPreview command missing")
ok(vim.fn.exists(":AsciidocPreviewToggle") == 2, "AsciidocPreviewToggle command missing")
ok(vim.fn.exists(":AsciidocPreviewMode") == 2, "AsciidocPreviewMode command missing")
ok(vim.fn.exists(":AsciidocPreviewClose") == 2, "AsciidocPreviewClose command missing")
ok(vim.fn.exists(":AsciidocPreviewStatus") == 2, "AsciidocPreviewStatus command missing")

-- 3. Open preview (default: live mode).
vim.cmd("edit " .. fixture)
local buf = vim.api.nvim_get_current_buf()
asciidoc.preview()

wait_for(function()
  local h = html_content(buf)
  return h ~= nil and h:find('http-equiv="refresh" content="1"', 1, true) ~= nil
end, 20000, "preview html was not rendered")

local html = html_content(buf)
ok(html:find('http-equiv="refresh" content="1"', 1, true), "no refresh meta injected")
ok(html:find("Test Document", 1, true), "rendered html lost the document title")
ok(_G.__opened and _G.__opened == html_path(buf), "open_browser was not called with the preview file")

-- 4. Toggle to on-save mode: text edits must NOT trigger a render.
asciidoc.toggle_live()
local html_before = html_content(buf)
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "MARKER_UNSAVED=1", "" })
vim.wait(1500, function() return true end, 50)
local html_after_typing = html_content(buf)
ok(html_after_typing == html_before, "on-save mode rendered on TextChanged")

-- 5. Saving must trigger a render in on-save mode.
vim.cmd("silent write")
wait_for(function()
  local h = html_content(buf)
  return h ~= nil and h ~= html_before
end, 20000, "on-save mode did not render on write")
ok(html_before:find("MARKER_UNSAVED", 1, true) == nil, "unsaved marker leaked in on-save render")

-- 6. Live mode back on: editing renders (and auto-writes the buffer).
asciidoc.toggle_live()
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "MARKER_LIVE=1", "" })
wait_for(function()
  local h = html_content(buf)
  return h ~= nil and h:find("MARKER_LIVE", 1, true) ~= nil
end, 20000, "live mode did not render on TextChanged")
ok(vim.fn.filereadable(fixture) == 1, "live fixture disappeared")
local disk = table.concat(vim.fn.readfile(fixture), "\n")
ok(disk:find("MARKER_LIVE", 1, true), "write_on_change did not persist live edits to disk")

-- 7. set_mode("save") / set_mode("live") work.
asciidoc.set_mode("save")
asciidoc.set_mode("live")

-- 8. Close removes the temp html and state.
asciidoc.close()
ok(vim.fn.filereadable(html_path(buf)) == 0, "preview close left the temp html behind")

-- 9. Closing on buffer wipe via autocmd.
vim.cmd("edit " .. fixture2)
local buf2 = vim.api.nvim_get_current_buf()
asciidoc.preview()
local html2 = html_path(buf2)
wait_for(function()
  return vim.fn.filereadable(html2) == 1
end, 20000, "second preview html was not rendered")

vim.api.nvim_buf_delete(buf2, { force = true })
wait_for(function()
  return vim.fn.filereadable(html2) == 0
end, 20000, "temp html survived BufWipeout")

print("ALL TESTS PASSED (" .. passed .. " assertions)")
vim.cmd("qa")