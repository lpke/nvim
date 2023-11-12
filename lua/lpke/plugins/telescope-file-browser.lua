local function config()
  local helpers = require('lpke.core.helpers')
  local fb = require('telescope').extensions.file_browser

  -- stylua: ignore start
  -- keymaps
  helpers.keymap_set_multi({
    { 'nC', '<BS>d', [[execute 'Telescope file_browser path=' . substitute(expand('%:p:h'), 'oil://', '', '') . ' select_buffer=true']],
      { desc = 'Open Telescope File Browser' }},
    { 'nC', '<BS>D', [[execute 'Telescope file_browser prompt_title=File\ Browser\ (depth:\ 5) path=' . substitute(expand('%:p:h'), 'oil://', '', '') . ' select_buffer=true depth=5 hidden=false']],
      { desc = 'Open Telescope File Browser (depth: 5)' }},
  })
end
-- stylua: ignore end

local function telescope_settings(
  fb_actions,
  actions,
  actions_state,
  actions_utils
)
  local helpers = require('lpke.core.helpers')
  return {
    initial_mode = 'normal',
    sorting_strategy = 'ascending',
    path = vim.loop.cwd(),
    cwd = vim.loop.cwd(),
    cwd_to_path = false,
    grouped = true,
    files = true,
    add_dirs = true,
    depth = 1,
    auto_depth = false,
    select_buffer = false,
    hidden = { file_browser = true, folder_browser = true },
    respect_gitignore = false,
    follow_symlinks = true,
    browse_files = require('telescope._extensions.file_browser.finders').browse_files,
    browse_folders = require('telescope._extensions.file_browser.finders').browse_folders,
    hide_parent_dir = true,
    collapse_dirs = false,
    prompt_path = false,
    quiet = false,
    dir_icon = ' ',
    dir_icon_hl = 'Default',
    display_stat = { date = true, size = true, mode = true },
    hijack_netrw = false,
    use_fd = true,
    git_status = true,
    mappings = {
      i = {
        -- disabling defaults
        ['<A-c>'] = false,
        ['<A-r>'] = false,
        ['<A-m>'] = false,
        ['<A-y>'] = false,
        ['<A-d>'] = false,
        ['<C-o>'] = false,
        ['<C-g>'] = false,
        ['<C-e>'] = false,
        ['<C-w>'] = false,
        ['<C-t>'] = false,
        ['<C-f>'] = false,
        ['<C-h>'] = false,
        ['<C-s>'] = false,
        ['<bs>'] = false,

        -- NAVIGATION
        ['<BS>'] = fb_actions.backspace,

        -- OPEN
        ['<CR>'] = function(bufnr)
          actions.select_default(bufnr)
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes('<Esc>', true, true, true),
            'n',
            false
          )
        end,

        -- CREATE
        ['<S-CR>'] = fb_actions.create_from_prompt,
      },

      n = {
        -- disabling defaults
        ['c'] = false,
        ['r'] = false,
        -- ['m'] = false,
        ['y'] = false,
        ['d'] = false,
        ['o'] = false,
        ['g'] = false,
        ['e'] = false,
        ['w'] = false,
        ['t'] = false,
        ['f'] = false,
        -- ['h'] = false,
        ['s'] = false,
        -- ['<Esc>'] = false,

        -- NAVIGATION
        ['gh'] = fb_actions.goto_home_dir,
        ['gd'] = fb_actions.goto_cwd,
        ['cd'] = fb_actions.change_cwd,

        -- NAV / OPENING
        ['l'] = actions.select_default,
        ['h'] = fb_actions.goto_parent_dir,

        -- SEARCHING
        ['/'] = { 'i', type = 'command' }, -- 'search'

        -- CREATE / RENAME
        ['<'] = fb_actions.create,
        ['R'] = fb_actions.rename,

        -- MOVE
        ['m'] = fb_actions.move,
        ['P'] = fb_actions.copy,

        -- OPEN
        ['O'] = fb_actions.open,

        -- VIEW
        [','] = fb_actions.toggle_browser,
        ['g.'] = fb_actions.toggle_hidden,
        ['g,'] = fb_actions.toggle_respect_gitignore,

        -- SELECTION
        ['V'] = actions.select_all,
        ['uv'] = actions.drop_all,

        -- DELETE
        ['dD'] = function(bufnr) -- delete to trash
          local picker = actions_state.get_current_picker(bufnr)
          local path = picker.finder.path
          local selection_paths = {}
          actions_utils.map_selections(bufnr, function(entry)
            table.insert(selection_paths, entry[1])
          end)
          if #selection_paths == 0 then
            -- delete highlighted entry
            local selected_path = actions_state.get_selected_entry(bufnr)[1]
            vim.cmd('!trash ' .. selected_path)
          else
            -- delete selected entries
            for _, v in ipairs(selection_paths) do
              vim.cmd('!trash ' .. v)
            end
          end
          vim.cmd('Telescope file_browser path=' .. path)
        end,
        ['dX'] = function(bufnr) -- delete permanently
          fb_actions.remove(bufnr)
        end,
        ['ud'] = function(bufnr) -- 'undo' delete
          local picker_path =
            actions_state.get_current_picker(bufnr).finder.path
          actions.close(bufnr)
          Lpke_trash_restore(picker_path)
        end,
      },
    },
  }
end

return {
  'nvim-telescope/telescope-file-browser.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
  config = config,
  telescope_settings = telescope_settings,
}
