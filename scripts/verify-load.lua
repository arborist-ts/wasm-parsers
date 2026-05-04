--- Run via:
---   WASM_OUT_DIR=<dir> nvim --headless -c 'luafile scripts/verify-load.lua' -c 'qa!'
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
---
--- On first failure we dump diagnostics: nvim version, has('wasmtime'),
--- CWD, the full path tried, file readability, and the raw return values
--- of language.add. ABI mismatches surface here.

local out_dir = os.getenv("WASM_OUT_DIR")
  or error("set WASM_OUT_DIR before invoking")

io.write("nvim version: " .. tostring((vim.version() or {}).api_level or "?") .. "\n")
io.write("nvim full version:\n")
for line in (vim.fn.execute("version") or ""):gmatch("[^\n]+") do
  if line:match("^NVIM") or line:match("Build type") or line:match("LuaJIT") then
    io.write("  " .. line .. "\n")
  end
end
io.write("has('wasmtime'): " .. tostring(vim.fn.has("wasmtime")) .. "\n")
io.write("cwd: " .. (vim.uv.cwd() or "?") .. "\n")
io.write("WASM_OUT_DIR: " .. out_dir .. "\n")
io.write("\n")

local fail_count, ok_count = 0, 0
local failed = {}
local first_fail_dumped = false
for _, path in ipairs(vim.fn.glob(out_dir .. "/*.wasm", false, true)) do
  local lang = vim.fn.fnamemodify(path, ":t:r")
  local abs = vim.fn.fnamemodify(path, ":p")
  local lok, r, lerr = pcall(vim.treesitter.language.add, lang, { path = path })
  if lok and r and lerr == nil then
    ok_count = ok_count + 1
    io.write(string.format("[ok]   %s\n", lang))
  else
    fail_count = fail_count + 1
    failed[#failed + 1] = lang
    io.write(string.format("[FAIL] %s: %s\n", lang,
      tostring(lerr or (not lok and r) or "language.add returned " .. tostring(r))))

    -- Dump rich diagnostics on the first failure only.
    if not first_fail_dumped then
      first_fail_dumped = true
      io.write("\n--- diagnostics for first failure ---\n")
      io.write("  given path: " .. tostring(path) .. "\n")
      io.write("  abs path:   " .. tostring(abs) .. "\n")
      local stat = vim.uv.fs_stat(abs)
      io.write("  fs_stat: " .. (stat
        and string.format("size=%d type=%s", stat.size, stat.type) or "MISSING") .. "\n")
      -- Read first 16 bytes to confirm wasm magic
      local f = io.open(abs, "rb")
      if f then
        local hdr = f:read(16) or ""
        f:close()
        local hex = ""
        for i = 1, #hdr do hex = hex .. string.format("%02x ", hdr:byte(i)) end
        io.write("  first 16 bytes: " .. hex .. "\n")
        io.write("    (wasm magic = 00 61 73 6d ...)\n")
      else
        io.write("  could not open file for reading\n")
      end
      -- Try add with absolute path in case relative is the issue
      local lok2, r2, lerr2 = pcall(vim.treesitter.language.add, lang, { path = abs })
      io.write(string.format("  retry with absolute path: ok=%s ret=%s err=%s\n",
        tostring(lok2), tostring(r2), tostring(lerr2)))
      io.write("--- end diagnostics ---\n\n")
    end
  end
end

io.write(string.format("\n%d ok, %d failed\n", ok_count, fail_count))
if fail_count > 0 then
  io.write("failed: " .. table.concat(failed, ", ") .. "\n")
  vim.cmd("cq 1")
end
