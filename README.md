# nvim

My Neovim config.

## Layout

- `init.lua` loads core config, plugins, and LSP setup.
- `lua/lpke/core/` contains options, keymaps, commands, autocommands, globals, and helpers.
- `lua/lpke/plugins/` contains lazy.nvim plugin specs.
- `lua/lpke/lsp/` contains language server setup and overrides.
- `lua/lpke/snippets/` contains LuaSnip snippets.

## Includes

- lazy.nvim plugin management
- LSP, completion, snippets, formatting, and linting
- Telescope, Treesitter, Oil, Harpoon, Aerial, and Undotree
- Git integration with Fugitive, Gitsigns, and Diffview
- CodeCompanion and Copilot config
- Rose Pine theme and Lualine statusline

## Setup

Clone to `~/.config/nvim` and start Neovim. `lazy.nvim` bootstraps itself on first launch.
