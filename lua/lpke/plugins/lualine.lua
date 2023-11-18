local options = require('lpke.core.options')
local symbols = options.custom_opts.symbols
local helpers = require('lpke.core.helpers')

-- mappings for display
local modes = {
  { 'NORMAL', 'NOR' },
  { 'INSERT', 'INS' },
  { 'VISUAL', 'VIS' },
  { 'V-LINE', 'V-L' },
  { 'V-BLOCK', 'V-B' },
  { 'REPLACE', 'REP' },
  { 'V-REPLACE', 'V-R' },
  { 'COMMAND', 'CMD' },
  { 'TERMINAL', 'TER' },
  { 'O-PENDING', 'O-P' },
}
local filetypes = {
  { 'javascript', 'js' },
  { 'typescript', 'ts' },
  { 'javascriptreact', 'jsreact' },
  { 'typescriptreact', 'tsreact' },
}

local function config()
  local tc = Lpke_theme_colors
  local refresh = require('lualine').refresh

  local custom_theme = {
    normal = {
      a = { bg = tc.overlayplus, fg = tc.subtleplus },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    insert = {
      a = { bg = tc.overlayplus, fg = tc.text },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    visual = {
      a = { bg = tc.growth, fg = tc.base },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    replace = {
      a = { bg = tc.love, fg = tc.base },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    command = {
      a = { bg = tc.overlayplus, fg = tc.iris },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    terminal = {
      a = { bg = tc.iris, fg = tc.base },
      b = { bg = tc.overlay, fg = tc.subtleplus },
      c = { bg = tc.overlay, fg = tc.subtleplus },
    },
    inactive = {
      a = { bg = tc.surface, fg = tc.mutedplus },
      b = { bg = tc.surface, fg = tc.mutedplus },
      c = { bg = tc.surface, fg = tc.mutedplus },
    },
  }

  Lpke_show_cwd = true
  Lpke_show_harpoon = true
  Lpke_full_path = true
  Lpke_show_encoding = false
  Lpke_show_session = false
  Lpke_show_git = true
  Lpke_show_git_branch = false
  Lpke_show_diagnostics = true

  -- custom component display
  local zoom_status = function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tab_zoomed = (Lpke_zoomed[cur_tab] == true)
    return tab_zoomed and '▣' or ''
  end
  local cwd_folder = helpers.get_cwd_folder

  -- custom component tables
  local harpoon = {
    function()
      return require('harpoon.mark').get_current_index()
    end,
    cond = function()
      local index = require('harpoon.mark').get_current_index()
      return (index and Lpke_show_harpoon) and true or false
    end,
    on_click = function()
      Lpke_show_harpoon = not Lpke_show_harpoon
      refresh()
    end,
    padding = { left = 1, right = 0 },
    color = { fg = tc.mutedplus },
  }
  local filename = {
    'filename',
    path = 1,
    fmt = function(str)
      -- only show filename when: toggled off OR an accepted buffer
      local normal_buffer = vim.bo.buftype == ''
      local oil_buffer = vim.bo.filetype == 'oil'
      local accepted_buffer = normal_buffer or oil_buffer
      if Lpke_full_path and accepted_buffer then
        if oil_buffer and string.match(str, '^ ?oi?l?:?//') then
          return str:gsub('^ ?oi?l?:?//', '')
        else
          return str
        end
      else
        return helpers.get_path_tail(str)
      end
    end,
    on_click = function()
      Lpke_full_path = not Lpke_full_path
      refresh()
    end,
    shorting_target = 40,
    icons_enabled = true,
    symbols = {
      modified = symbols.modified,
      readonly = symbols.readonly,
      unnamed = symbols.unnamed,
      newfile = symbols.newfile,
    },
  }

  local session_cond = function()
    return Lpke_show_session
  end
  local session_components = {
    {
      function()
        return 'S:'
      end,
      cond = session_cond,
      on_click = function()
        Lpke_show_session = not Lpke_show_session
        refresh()
      end,
      padding = { left = 1, right = 0 },
      color = { fg = tc.mutedplus, bg = tc.overlaybump },
    },
    {
      function()
        return helpers.get_session_name()
      end,
      cond = session_cond,
      on_click = function()
        Lpke_show_session = not Lpke_show_session
        refresh()
      end,
      padding = { left = 0, right = 1 },
      color = { fg = tc.textminus, bg = tc.overlaybump, gui = 'bold' },
    },
  }

  local git_components = {
    {
      'diff',
      colored = true,
      cond = function()
        return Lpke_show_git
      end,
      diff_color = {
        added = { fg = tc.foam },
        modified = { fg = tc.rose },
        removed = { fg = tc.love },
      },
      on_click = function()
        Lpke_show_git_branch = not Lpke_show_git_branch
        refresh()
      end,
      color = { bg = tc.overlaybump },
    },
    {
      'branch',
      cond = function()
        return Lpke_show_git and Lpke_show_git_branch
      end,
      on_click = function()
        Lpke_show_git_branch = not Lpke_show_git_branch
        refresh()
      end,
      color = { fg = tc.textminus, bg = tc.overlaybump, gui = 'bold' },
    },
  }

  require('lualine').setup({
    options = {
      icons_enabled = false,
      theme = custom_theme,
      component_separators = { left = '', right = '' },
      section_separators = { left = '', right = '' },
      disabled_filetypes = {
        statusline = {},
        winbar = {},
      },
      ignore_focus = {},
      always_divide_middle = false,
      globalstatus = false,
      refresh = {
        statusline = 1000,
        tabline = 1000,
        winbar = 1000,
      },
    },
    sections = {
      lualine_a = {
        {
          zoom_status,
          on_click = Lpke_win_zoom_toggle,
          color = { bg = tc.iris, fg = tc.base },
        },
        {
          'mode',
          fmt = function(str)
            return helpers.map_string(str, modes)
          end,
          on_click = function()
            Lpke_show_cwd = not Lpke_show_cwd
            refresh()
          end,
          color = function()
            local reg_rec = vim.fn.reg_recording()
            if reg_rec ~= '' then
              return { fg = tc.love, gui = 'bold' }
            end
          end,
        },
      },
      lualine_b = {
        session_components[1],
        session_components[2],
        {
          cwd_folder,
          cond = function()
            return Lpke_show_cwd
          end,
          on_click = function()
            Lpke_show_session = not Lpke_show_session
            refresh()
          end,
          color = function()
            local session = helpers.get_session_name()
            if session then
              return { gui = 'bold', fg = tc.textminus }
            else
              return { gui = '' }
            end
          end,
        },
        harpoon,
        filename,
      },
      lualine_c = {
        {
          'diagnostics',
          cond = function()
            return Lpke_show_diagnostics
          end,
          symbols = {
            error = '', -- ■
            warn = '', -- ▲
            info = '', -- ◆
            hint = '', -- ●
          },
        },
      },
      lualine_x = {
        {
          'encoding',
          cond = function()
            return Lpke_show_encoding
          end,
        },
        {
          'fileformat',
          cond = function()
            return Lpke_show_encoding
          end,
          icons_enabled = true,
          symbols = {
            unix = 'LF', -- LF
            dos = 'CRLF', -- CRLF
            mac = 'CR', -- CR
          },
        },
        {
          'filetype',
          fmt = function(str)
            return helpers.map_string(str, filetypes)
          end,
          on_click = function()
            Lpke_show_encoding = not Lpke_show_encoding
            refresh()
          end,
        },
      },
      lualine_y = {
        'progress',
        {
          'location',
          on_click = function()
            Lpke_show_git = not Lpke_show_git
            refresh()
          end,
        },
        git_components[1],
        git_components[2],
        -- linter status
        {
          function()
            return 'T'
          end,
          cond = function()
            local linter_for_ft = require('lint').linters_by_ft[vim.bo.filetype]
            return linter_for_ft and true or false
          end,
          on_click = function()
            Lpke_toggle_linting()
          end,
          color = function()
            local enabled = Lpke_linting_enabled
            return enabled and { bg = tc.overlayplus, fg = tc.text }
              or { bg = tc.overlaybump, fg = tc.lovefaded }
          end,
        },
        -- diagnostic status
        {
          function()
            return 'D'
          end,
          cond = function()
            local lsp_attached = vim.lsp.get_active_clients({ bufnr = 0 })[1]
              ~= nil
            return lsp_attached
          end,
          on_click = function()
            Lpke_toggle_diagnostics()
          end,
          color = function()
            local enabled = not vim.diagnostic.is_disabled()
            return enabled and { bg = tc.overlayplus, fg = tc.text }
              or { bg = tc.overlaybump, fg = tc.lovefaded }
          end,
        },
        -- auto cmp status
        {
          function()
            return 'M'
          end,
          on_click = function()
            Lpke_toggle_auto_cmp()
            refresh()
          end,
          color = function()
            local enabled = Lpke_auto_cmp
            return enabled and { bg = tc.overlayplus, fg = tc.text }
              or { bg = tc.overlaybump, fg = tc.lovefaded }
          end,
        },
      },
      lualine_z = {},
    },
    inactive_sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = { harpoon, filename },
      lualine_x = { 'location' },
      lualine_y = {},
      lualine_z = {},
    },
    tabline = {},
    winbar = {},
    inactive_winbar = {},
    extensions = {},
  })

  -- options when using lualine
  vim.cmd('set noshowmode')
  vim.o.laststatus = options.vim_opts.laststatus -- override plugin control of this

  -- stylua: ignore start
  -- keymaps when using lualine
  helpers.keymap_set_multi({
    { 'n', '<F2>D', function() Lpke_show_cwd = not Lpke_show_cwd refresh() end, { desc = 'Lualine: Toggle cwd' }},
    { 'n', '<F2>A', function() Lpke_show_harpoon = not Lpke_show_harpoon refresh() end, { desc = 'Lualine: Toggle harpoon index' }},
    { 'n', '<F2>F', function() Lpke_full_path = not Lpke_full_path refresh() end, { desc = 'Lualine: Toggle file path' }},
    { 'n', '<F2>E', function() Lpke_show_encoding = not Lpke_show_encoding refresh() end, { desc = 'Lualine: Toggle encoding info' }},
    { 'n', '<F2>S', function() Lpke_show_session = not Lpke_show_session refresh() end, { desc = 'Lualine: Toggle session name' }},
    { 'n', '<F2>G', function() Lpke_show_git = not Lpke_show_git refresh() end, { desc = 'Lualine: Toggle all git info' }},
    { 'n', '<F2>V', function() Lpke_show_diagnostics = not Lpke_show_diagnostics refresh() end, { desc = 'Lualine: Toggle diagnostics display' }},
    { 'n', '<F2>g', function() Lpke_show_git_branch = not Lpke_show_git_branch refresh() end, { desc = 'Lualine: Toggle git branch display' }},
  })
  -- stylua: ignore end
end

return {
  'nvim-lualine/lualine.nvim',
  lazy = false,
  priority = 800,
  config = config,
}
