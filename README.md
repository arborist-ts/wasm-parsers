# arborist-ts/wasm-parsers

Prebuilt WASM tree-sitter parsers consumed by [arborist.nvim](https://github.com/arborist-ts/arborist.nvim).

Each tagged release contains:

- `<lang>.wasm` for every parser in `parsers.txt` at that tag, built from
  the revision pinned in `arborist.nvim/registry/pins.toml` at the same tag.
- `popular.tar.gz` — the same set bundled into one tarball for fast bulk
  install.
- `manifest.json` — the source of truth for sha256, sizes, and URLs.

## Manifest schema

```json
{
  "schema_version": 1,
  "tag": "v0.8.0",
  "generated_at": "2026-05-04T12:34:56Z",
  "arborist_pins_ref": "arborist-ts/arborist.nvim@<sha>",
  "tested_with_neovim": "NVIM v0.12.0-nightly+...",
  "bundle": {
    "url": "https://.../popular.tar.gz",
    "sha256": "...",
    "size": 5242880,
    "parsers": ["bash", "c", "cpp", "..."]
  },
  "parsers": {
    "lua": {
      "revision": "<commit sha>",
      "sha256": "...",
      "size": 134217,
      "url": "https://.../lua.wasm"
    }
  }
}
```

## Tag policy

**Tags are immutable.** Don't delete and recreate. If a release ships
broken artifacts, cut a new tag (`v0.8.0` → `v0.8.0.1`) and bump
`lua/arborist/version.lua` in arborist.nvim.

Consumers cache the manifest by tag (`<cache_dir>/manifest-<tag>.json`)
and trust it for the lifetime of the tag. Re-releasing a tag breaks
that contract.

## Coverage

`parsers.txt` is the public contract for what's published at each tag.
To add or remove parsers from coverage: edit the file and tag a release.

If a parser fails to build or fails the runtime load test, the entire
release is failed — partial manifests aren't shipped. Either fix the
parser (bump its pin in arborist.nvim), or remove it from `parsers.txt`
for the release.

## Cutting a release

Two ways:

1. **Tag-driven** — push a tag matching `v*` to this repo. The workflow
   reads `pins.toml` from arborist.nvim at the same tag (which must
   already exist there), builds, verifies, and publishes the release.

2. **Manual** (workflow_dispatch) — trigger the workflow with:
   - `pin_ref`: arborist.nvim ref to read pins from (defaults to `main`)
   - `release_tag`: tag to publish under (blank = build-only, no release)

## Verification

Every release goes through:

1. **Build** — `tree-sitter build --wasm` for every parser in `parsers.txt`.
2. **Load test** — `nvim --headless -l verify-load.lua` calls
   `vim.treesitter.language.add` on each `.wasm`. This is the single most
   important step: it catches the dylink/ABI breakage class that sank
   the previous (unpkg-fronted) CDN attempt.
3. **sha256 inventory** — `make-manifest.lua` records every artifact's
   sha256 and size; consumers reject any download whose bytes don't match.

The Neovim build used for the load test is captured in the manifest's
`tested_with_neovim` field; users reporting load failures can diff their
local Neovim against it.
