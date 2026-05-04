--- Run via:
---   WASM_OUT_DIR=<dir> nvim --headless -c 'luafile scripts/verify-load.lua' -c 'cq! 0'
--- Loads every <dir>/*.wasm into Neovim's wasmtime via
--- `vim.treesitter.language.add` and exits non-zero on any failure.
---
--- This is the single most important step in the release pipeline. It
--- catches the dylink/ABI breakage class that sank the first CDN attempt
--- (unpkg's tree-sitter-wasms) — a binary that builds cleanly but the
--- runtime can't actually load.
---
--- Note on invocation: `nvim --headless -l <script>` does NOT initialize
--- wasmtime in current Neovim builds, so language.add always fails for
--- wasm parsers under `-l`. Using `-c 'luafile'` + `-c 'qa'` avoids that.

local out_dir = os.getenv("WASM_OUT_DIR")
  or error("set WASM_OUT_DIR before invoking")

local fail_count, ok_count = 0, 0
local failed = {}
for _, path in ipairs(vim.fn.glob(out_dir .. "/*.wasm", false, true)) do
  local lang = vim.fn.fnamemodify(path, ":t:r")
  local lok, r, lerr = pcall(vim.treesitter.language.add, lang, { path = path })
  if lok and r and lerr == nil then
    ok_count = ok_count + 1
    io.write(string.format("[ok]   %s\n", lang))
  else
    fail_count = fail_count + 1
    failed[#failed + 1] = lang
    io.write(string.format("[FAIL] %s: %s\n", lang,
      tostring(lerr or (not lok and r) or "language.add returned " .. tostring(r))))
  end
end

io.write(string.format("\n%d ok, %d failed\n", ok_count, fail_count))
if fail_count > 0 then
  io.write("failed: " .. table.concat(failed, ", ") .. "\n")
  vim.cmd("cq 1")
end
