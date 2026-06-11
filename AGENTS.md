This is my neovim configuration repository.

- When adding keymaps, always prefer to use `keymap_set` (single), `keymap_set_multi` (multiple), `ft_keymap_set_multi` (filetype specific), or `telescope_keymap_set_multi` (telescope pickers) helpers from `lua/lpke/core/helpers/config.lua` over the native neovim keymap setting functions unless they dont fit the requirement.
- Always consult `lua/lpke/core/helpers/` and `lua/lpke/core/globals/` to check if any helper functions exist for the required task before writing code from scrach
- Remember to consult relevant plugin source code when making changes that involve plugins (~/.local/share/nvim/lazy/...).
- Update `doc/lpke-help.txt` when adding or changing substantial custom commands, keymaps, helpers, plugin workflows, snippets, or filetype behavior. Keep `doc/tags` in sync with `:helptags doc` so `<BS>fh` can find custom help tags. Keep it concise and workflow-oriented, so it remains useful after time away from Neovim.
