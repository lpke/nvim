This is my neovim configuration repository.

- When adding keymaps, always prefer to use `keymap_set` (single), `keymap_set_multi` (multiple), `ft_keymap_set_multi` (filetype specific), or `telescope_keymap_set_multi` (telescope pickers) helpers from `lua/lpke/core/helpers/config.lua` over the native neovim keymap setting functions unless they dont fit the requirement.
- Always consult `lua/lpke/core/helpers/` and `lua/lpke/core/globals/` to check if any helper functions exist for the required task before writing code from scrach
- Remember to consult relevant plugin source code when making changes that involve plugins (~/.local/share/nvim/lazy/...).
- When changing CodeCompanion keymaps or workflows, update the custom `g?` help extension in `lua/lpke/plugins/ai/helpers/keymap_help.lua` so the LPKE custom section stays in sync.
- Update `doc/lpke-help.txt` only when adding or changing user-facing workflows that someone would need to look up later: substantial custom commands, keymaps, workflows, snippets, or filetype behavior. Do not document bugfixes, intended behavior, or internal implementation details. Keep `doc/tags` in sync with `:helptags doc` when help docs change.
