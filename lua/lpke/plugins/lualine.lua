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
  { 'SELECT', 'SEL' },
  { 'S-LINE', 'S-L' },
}
local filetypes = {
  { 'javascript', 'js' },
  { 'typescript', 'ts' },
  { 'javascriptreact', 'jsreact' },
  { 'typescriptreact', 'tsreact' },
}

local function config()
  local lualine = require('lualine')
  local tc = Lpke_theme_colors
  local llm_spinner = require('lpke.plugins.ai.helpers.lualine_spinner')
  local refresh = lualine.refresh

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
  Lpke_format_bufname = true -- toggle all formatting of the buffer name (overrides `Lpke_full_path`)
  Lpke_full_path = true -- show full path or not (for applicable file/buf types)
  Lpke_show_encoding = false
  Lpke_show_session = false
  Lpke_show_git = true
  Lpke_show_git_branch = false
  Lpke_show_diagnostics = true
  Lpke_show_active_ids = false

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

  -- TODO: handle [Term]?
  local buffer_tag = {
    function()
      local b = Lpke_buf_details(0)
      if b.oil_trash then
        return '[Trash]'
      elseif b.git_buffer_type then
        return '[Git]'
      elseif b.codecompanion_buffer then
        return '[AI]'
      end
      return ''
    end,
    padding = { left = 1, right = 0 },
    color = function()
      local b = Lpke_buf_details(0)
      if b.oil_trash then
        return { fg = tc.love }
      elseif b.codecompanion_buffer then
        return { fg = tc.iris }
      end
      return { fg = tc.foam }
    end,
  }

  local buffer_name = {
    'filename',
    path = 1,
    fmt = function(str)
      local b = Lpke_buf_details(0)

      -- override toggle to show raw buf name
      if not Lpke_format_bufname then
        return str
      end

      -- filetype dependent naming
      local filetype_bufname_maps = {
        ['TelescopePrompt'] = 'Telescope',
        ['harpoon'] = 'Harpoon Menu',
        ['fugitive'] = 'Fugitive Status',
        ['fugitiveblame'] = 'Fugitive Blame',
        ['NeogitStatus'] = 'Neogit Status',
        ['DiffviewFiles'] = 'Diffview Files',
        ['DiffviewFileHistory'] = 'Diffview File History',
        ['gitsigns-blame'] = 'Gitsigns Blame',
      }
      if filetype_bufname_maps[b.file_type] then
        return filetype_bufname_maps[b.file_type]
      end

      -- handle special cases
      if b.file_type == 'codecompanion' then
        return str:gsub('%[CodeCompanion%]', 'CodeCompanion')
      end

      -- TODO: handle more git related cases + undotree
      -- handle bufs with toggle-able paths
      local has_path_toggling = b.normal_buffer or b.oil_buffer
      if has_path_toggling then
        -- long path format
        if Lpke_full_path then
          if b.oil_buffer then
            local rel_path = helpers.transform_path(
              b.buf_name,
              { include_filename = false, cwd_name = false }
            )
            return rel_path
          else
            return str
          end
        else
          -- short path format
          if b.oil_buffer then
            return helpers.get_path_tail(b.buf_name)
          else
            return helpers.get_path_tail(str)
          end
        end
      end

      -- default fallback to raw buf name
      return str
    end,
    on_click = function()
      Lpke_full_path = not Lpke_full_path
      refresh()
    end,
    file_status = false, -- handled as a seperate component
    shorting_target = 40,
    icons_enabled = true,
    symbols = {
      modified = symbols.modified,
      readonly = symbols.readonly,
      unnamed = symbols.unnamed,
      newfile = symbols.newfile,
    },
  }

  local readonly = {
    function()
      return symbols.readonly
    end,
    cond = function()
      local is_readonly = vim.api.nvim_get_option_value('readonly', { buf = 0 })
        or (not vim.api.nvim_get_option_value('modifiable', { buf = 0 }))
      return is_readonly
    end,
    padding = { left = 0, right = 1 },
    color = { fg = tc.muted },
  }

  local modified = {
    function()
      return symbols.modified
    end,
    cond = function()
      local telescope_buffer = vim.bo.filetype == 'TelescopePrompt'
      local is_modified = vim.api.nvim_get_option_value('modified', { buf = 0 })
      return is_modified and not telescope_buffer
    end,
    padding = { left = 0, right = 1 },
    color = { fg = tc.subtleplus },
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

  local llm_model = {
    function()
      local bufnr = vim.api.nvim_get_current_buf()
      local chat = require('codecompanion').buf_get_chat(bufnr)
      if not chat then
        return nil
      end
      local adapter = chat.adapter
      if not adapter then
        return nil
      end
      local model = adapter.schema.model.default or adapter.opts.model
      local model_display_maps = {
        ['claude-sonnet-4'] = 'sonnet-4',
        ['claude-3.5-sonnet'] = 'sonnet-3.5',
        ['gemini-2.0-flash-001'] = 'gemini-2-flash',
        ['gpt-4.1'] = 'GPT-4.1',
        ['o1'] = 'o1',
        ['claude-3.7-sonnet'] = 'sonnet-3.7',
        ['gemini-2.5-pro'] = 'gemini-2.5-pro',
        ['gpt-4o'] = 'GPT-4o',
        ['o3-mini'] = 'o3-mini',
        ['o4-mini'] = 'o4-mini',
        ['claude-3.7-sonnet-thought'] = 'sonnet-3.7-think',
      }
      return model_display_maps[model] or model
    end,
    cond = function()
      return vim.bo.filetype == 'codecompanion'
    end,
    color = { fg = tc.text },
  }

  local git_components = {
    {
      -- note: this is a diff against what is staged
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
        Lpke_toggle_git_diff(true) -- diff to staging
      end,
      color = { bg = tc.overlaybump },
    },
    {
      'branch',
      cond = function()
        return Lpke_show_git and Lpke_show_git_branch
      end,
      on_click = function()
        Lpke_toggle_git_diff() -- diff to HEAD
      end,
      color = { fg = tc.textminus, bg = tc.overlaybump, gui = 'bold' },
    },
  }

  local active_ids = {
    function()
      return 'T:'
        .. vim.api.nvim_get_current_tabpage()
        .. ' B:'
        .. vim.api.nvim_get_current_buf()
        .. ' W:'
        .. vim.api.nvim_get_current_win()
    end,
    cond = function()
      return Lpke_show_active_ids
    end,
    on_click = function()
      Lpke_active()
    end,
  }

  lualine.setup({
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
      -- FIXME: this should be false, but it's a workaround to a flicker bug
      -- https://github.com/nvim-lualine/lualine.nvim/issues/1280
      globalstatus = true,
      refresh = {
        statusline = 100,
        tabline = 100,
        winbar = 100,
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
              return { fg = tc.textminus, gui = 'bold' }
            else
              return { fg = tc.textminus, gui = '' }
            end
          end,
        },
        harpoon,
        buffer_tag,
        buffer_name,
        readonly,
        modified,
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
          -- codecompanion LLM request spinner
          llm_spinner,
          color = { fg = tc.foam },
        },
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
        llm_model,
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
        -- copilot status
        {
          function()
            return 'C'
          end,
          cond = function()
            local should_attach = require('copilot.util').should_attach()
            local is_disabled = require('copilot.client').is_disabled()
            local buf_attached = require('copilot.client').buf_is_attached()
            local enabled = not not ((not is_disabled) and buf_attached)
            return (should_attach or enabled) and true or false
          end,
          on_click = function()
            Lpke_toggle_copilot()
          end,
          color = function()
            local should_attach = require('copilot.util').should_attach()
            local is_disabled = require('copilot.client').is_disabled()
            local buf_attached = require('copilot.client').buf_is_attached()
            local enabled = not not ((not is_disabled) and buf_attached)

            if (not should_attach) and enabled then
              return { bg = tc.overlayplus, fg = tc.subtleplus }
            elseif enabled then
              return { bg = tc.overlayplus, fg = tc.text }
            else
              return { bg = tc.overlaybump, fg = tc.lovefaded }
            end
          end,
        },
        -- linter status (only for "linters" - see mason <BS>im -> Linter)
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
            local lsp_attached = vim.lsp.get_clients({ bufnr = 0 })[1] ~= nil
            return lsp_attached
          end,
          on_click = function()
            Lpke_toggle_diagnostics()
          end,
          color = function()
            local enabled = vim.diagnostic.is_enabled()
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
        active_ids,
      },
      lualine_z = {},
    },
    inactive_sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = {
        harpoon,
        buffer_tag,
        buffer_name,
        readonly,
        modified,
      },
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
    { 'n', '<A-D>', function() Lpke_show_cwd = not Lpke_show_cwd refresh() end, { desc = 'Lualine: Toggle cwd' }},
    { 'n', '<F2>A', function() Lpke_show_harpoon = not Lpke_show_harpoon refresh() end, { desc = 'Lualine: Toggle harpoon index' }},
    { 'n', '<A-A>', function() Lpke_show_harpoon = not Lpke_show_harpoon refresh() end, { desc = 'Lualine: Toggle harpoon index' }},
    { 'n', '<F2>B', function() Lpke_format_bufname = not Lpke_format_bufname refresh() end, { desc = 'Lualine: Toggle buffer name formatting' }},
    { 'n', '<A-B>', function() Lpke_format_bufname = not Lpke_format_bufname refresh() end, { desc = 'Lualine: Toggle buffer name formatting' }},
    { 'n', '<F2>Z', function() Lpke_full_path = not Lpke_full_path refresh() end, { desc = 'Lualine: Toggle file path' }},
    { 'n', '<A-Z>', function() Lpke_full_path = not Lpke_full_path refresh() end, { desc = 'Lualine: Toggle file path' }},
    { 'n', '<F2>E', function() Lpke_show_encoding = not Lpke_show_encoding refresh() end, { desc = 'Lualine: Toggle encoding info' }},
    { 'n', '<A-E>', function() Lpke_show_encoding = not Lpke_show_encoding refresh() end, { desc = 'Lualine: Toggle encoding info' }},
    { 'n', '<F2>S', function() Lpke_show_session = not Lpke_show_session refresh() end, { desc = 'Lualine: Toggle session name' }},
    { 'n', '<A-S>', function() Lpke_show_session = not Lpke_show_session refresh() end, { desc = 'Lualine: Toggle session name' }},
    { 'n', '<F2>G', function() Lpke_show_git = not Lpke_show_git refresh() end, { desc = 'Lualine: Toggle all git info' }},
    { 'n', '<A-G>', function() Lpke_show_git = not Lpke_show_git refresh() end, { desc = 'Lualine: Toggle all git info' }},
    { 'n', '<F2>g', function() Lpke_show_git_branch = not Lpke_show_git_branch refresh() end, { desc = 'Lualine: Toggle git branch display' }},
    { 'n', '<A-g>', function() Lpke_show_git_branch = not Lpke_show_git_branch refresh() end, { desc = 'Lualine: Toggle git branch display' }},
    { 'n', '<F2>b', function() Lpke_show_active_ids = not Lpke_show_active_ids refresh() end, { desc = 'Lualine: Toggle active IDs display' }},
    { 'n', '<A-b>', function() Lpke_show_active_ids = not Lpke_show_active_ids refresh() end, { desc = 'Lualine: Toggle active IDs display' }},
  })
  -- stylua: ignore end
end

return {
  'nvim-lualine/lualine.nvim',
  lazy = false,
  priority = 800,
  config = config,
}
