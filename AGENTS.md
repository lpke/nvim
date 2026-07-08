This is my neovim configuration repository.

- When adding keymaps, always prefer to use `keymap_set` (single), `keymap_set_multi` (multiple), `ft_keymap_set_multi` (filetype specific), or `telescope_keymap_set_multi` (telescope pickers) helpers from `lua/lpke/core/helpers/config.lua` over the native neovim keymap setting functions unless they dont fit the requirement.
- Always consult `lua/lpke/core/helpers/` and `lua/lpke/core/globals/` to check if any helper functions exist for the required task before writing code from scrach
- Remember to consult relevant plugin source code when making changes that involve plugins (~/.local/share/nvim/lazy/...).
  - `lua/lpke/local_plugins_src` contains the source code for plugins I've chosen to contain locally rather than install through Lazy. They are still initiated with Lazy under `lua/lpke/plugins/<plugin>.lua`
- When changing CodeCompanion keymaps or workflows, update the custom `g?` help extension in `lua/lpke/plugins/ai/helpers/keymap_help.lua` so the LPKE custom section stays in sync.
- When adding LuaSnip snippets with `fmt`/`fmta`, remember literal `>` characters (for example in JS arrows `=>`) conflict with the `<>` placeholder delimiter unless escaped or avoided. Use plain nodes or a different formatter delimiter when the snippet body contains literal `>`.
- Update `doc/lpke-help.txt` only when adding or changing user-facing workflows that someone would need to look up later: substantial custom commands, keymaps, workflows, snippets, or filetype behavior. Do not document bugfixes, intended behavior, or internal implementation details. Keep `doc/tags` in sync with `:helptags doc` when help docs change.
