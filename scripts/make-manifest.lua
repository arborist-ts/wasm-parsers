--- Run via `nvim -l make-manifest.lua <out_dir> <tag> <pins_toml> <pins_ref> <neovim_id> <output_path>`.
--- Scans <out_dir> for *.wasm files, computes sha256 for each, reads
--- per-parser revision from <pins_toml>, and writes a manifest JSON
--- conforming to schema_version=1.

local out_dir   = arg[1] or error("usage: make-manifest.lua <out_dir> <tag> <pins_toml> <pins_ref> <neovim_id> <output_path>")
local tag       = arg[2] or error("tag required")
local pins_path = arg[3] or error("pins_toml path required")
local pins_ref  = arg[4] or error("pins_ref required")
local nvim_id   = arg[5] or error("neovim_id required")
local out_path  = arg[6] or error("output path required")

local function sha256_hex(path)
  local r = vim.system({ "sha256sum", path }, { text = true }):wait()
  assert(r.code == 0, "sha256sum failed for " .. path)
  return (r.stdout or ""):match("^(%x+)")
end

local function fsize(path)
  local s = vim.uv.fs_stat(path)
  return s and s.size or nil
end

--- Load all `[lang] revision = "..."` pairs from a pins.toml.
--- @param path string
--- @return table<string, string>  lang -> revision
local function read_pins(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("warning: pins.toml not found at " .. path .. "\n")
    return out
  end
  local current
  for line in f:lines() do
    local sec = line:match("^%[([%w_]+)%]$")
    if sec then current = sec end
    if current then
      local rev = line:match('^revision%s*=%s*"([^"]+)"')
      if rev then out[current] = rev end
    end
  end
  f:close()
  return out
end

local pins = read_pins(pins_path)

local parsers = {}
local bundle_langs = {}
for _, path in ipairs(vim.fn.glob(out_dir .. "/*.wasm", false, true)) do
  local lang = vim.fn.fnamemodify(path, ":t:r")
  local entry = {
    sha256 = sha256_hex(path),
    size = fsize(path),
    url = string.format(
      "https://github.com/arborist-ts/wasm-parsers/releases/download/%s/%s.wasm",
      tag, lang),
  }
  if pins[lang] then entry.revision = pins[lang] end
  parsers[lang] = entry
  bundle_langs[#bundle_langs + 1] = lang
end
table.sort(bundle_langs)

local bundle_path = out_dir .. "/popular.tar.gz"
local bundle = vim.uv.fs_stat(bundle_path) and {
  url = string.format(
    "https://github.com/arborist-ts/wasm-parsers/releases/download/%s/popular.tar.gz", tag),
  sha256 = sha256_hex(bundle_path),
  size = fsize(bundle_path),
  parsers = bundle_langs,
} or nil

local manifest = {
  schema_version = 1,
  tag = tag,
  generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  arborist_pins_ref = pins_ref,
  tested_with_neovim = nvim_id,
  bundle = bundle,
  parsers = parsers,
}

local f = assert(io.open(out_path, "w"))
f:write(vim.json.encode(manifest))
f:close()
io.write(string.format("wrote %s (%d parsers)\n", out_path, vim.tbl_count(parsers)))
