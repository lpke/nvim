local options = require('lpke.core.options')
local helpers = require('lpke.core.helpers')

-- mappings for display
local modes = {
  { 'NORMAL', 'NOR' },
  { 'INSERT', 'INS' },
  { 'VISUAL', 'VIS' },
  { 'V-LINE', 'V-L' },
  { 'V-BLOCK', 'V-B' },
  { 'REPLACE', 'REP' },
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
  Lpke_full_path = true
  Lpke_show_encoding = false
  Lpke_show_diagnostics_vis = true

  -- custom component display
  local zoom_status = function()
    local cur_tab = vim.api.nvim_get_current_tabpage()
    local tab_zoomed = (Lpke_zoomed[cur_tab] == true)
    return tab_zoomed and '▣' or ''
  end
  local session_name = function()
    return helpers.formatted_session_name()
  end
  local cwd_folder = helpers.get_cwd_folder

  -- custom component tables
  local filename = {
    'filename',
    path = 1,
    fmt = function(str)
      -- only show filename when: toggled off OR not a normal buffer
      local normal_buffer = vim.bo.buftype == ''
      return (Lpke_full_path and normal_buffer) and str
        or helpers.get_path_tail(str)
    end,
    on_click = function()
      Lpke_full_path = not Lpke_full_path
      refresh()
    end,
    shorting_target = 40,
    icons_enabled = true,
    symbols = {
      modified = '●',
      readonly = '',
      unnamed = '[No Name]',
      newfile = '[New]',
    },
  }
  local session_name_components = {
    {
      function()
        return 'S:'
      end,
      cond = helpers.session_in_cwd,
      padding = { left = 1, right = 0 },
      color = { fg = tc.mutedplus },
    },
    {
      session_name,
      cond = helpers.session_in_cwd,
      padding = { left = 0, right = 1 },
      color = { gui = 'bold' },
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
          on_click = helpers.win_zoom_toggle,
          color = { bg = tc.irisfaded, fg = tc.base },
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
        },
      },
      lualine_b = {
        {
          cwd_folder,
          cond = function()
            return Lpke_show_cwd
          end,
          on_click = function()
            Lpke_show_cwd = not Lpke_show_cwd
            refresh()
          end,
          color = function()
            local cwd = helpers.get_cwd_folder()
            local session = helpers.get_session_name()
            if cwd == session then
              return { gui = 'bold', fg = tc.textminus }
            elseif session then
              return { gui = 'bold' }
            else
              return { gui = '' }
            end
          end,
        },
        filename,
        {
          'branch',
          color = { gui = 'italic' },
        },
      },
      lualine_c = {
        'diff',
        {
          'diagnostics',
          symbols = {
            error = '■:',
            warn = '▲:',
            info = '◆:',
            hint = '●:',
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
        session_name_components[1],
        session_name_components[2],
      },
      lualine_y = {
        'progress',
        'location',
        -- diagnostic status
        {
          function()
            return 'D'
          end,
          cond = function()
            local lsp_attached = vim.lsp.get_active_clients({ bufnr = 0 })[1]
              ~= nil
            return Lpke_show_diagnostics_vis and lsp_attached
          end,
          on_click = function()
            Lpke_toggle_diagnostics()
            -- refresh()
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
      lualine_c = { filename },
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
    { 'n', '<F2>D', function() Lpke_show_cwd = not Lpke_show_cwd refresh() end, }, -- toggle cwd
    { 'n', '<F2>F', function() Lpke_full_path = not Lpke_full_path refresh() end, }, -- toggle file path
    { 'n', '<F2>E', function() Lpke_show_encoding = not Lpke_show_encoding refresh() end, }, -- toggle encoding info
    { 'n', '<F2>X', function() Lpke_show_diagnostics_vis = not Lpke_show_diagnostics_vis refresh() end, }, -- toggle diagnostics visibility
  })
  -- stylua: ignore end
end

return {
  'nvim-lualine/lualine.nvim',
  lazy = false,
  priority = 800,
  config = config,
}
