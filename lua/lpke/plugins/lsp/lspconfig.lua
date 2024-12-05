-- toggle LSP diagnostics globally
Lpke_diagnostics_enabled_initial = true
Lpke_diagnostics_enabled_prev = nil
function Lpke_toggle_diagnostics(choice)
  -- getting and storing current state
  local enabled = vim.diagnostic.is_enabled()
  Lpke_diagnostics_enabled_prev = enabled

  -- manual choice
  if choice ~= nil then
    if choice == false then
      pcall(vim.diagnostic.enable, false)
    elseif choice == true then
      pcall(vim.diagnostic.enable)
    elseif choice == 'prev' then
      if Lpke_diagnostics_enabled_prev == true then
        pcall(vim.diagnostic.enable)
      else
        pcall(vim.diagnostic.enable, false)
      end
    else
      print(
        'Diagnostics toggle: invalid argument:'
          .. ' `'
          .. tostring(choice)
          .. '` ('
          .. type(choice)
          .. ')'
      )
    end
    pcall(function()
      require('lualine').refresh()
    end)
    return
  end

  -- toggle based on previous state
  if enabled then
    pcall(vim.diagnostic.enable, false)
  else
    pcall(vim.diagnostic.enable)
  end
  pcall(function()
    require('lualine').refresh()
  end)
end

-- shared emmet options for multiple filetypes
local emmet_opts_global = {
  ['bem.enabled'] = false,
  ['output.selfClosingStyle'] = 'xhtml',
  ['output.attributeQuotes'] = 'double',
}

local emmet_opts_jsx = {
  ['jsx.enabled'] = true,
  ['markup.attributes'] = {
    ['class'] = 'className',
    ['for'] = 'htmlFor',
  },
}

local function config()
  local lspconfig = require('lspconfig')
  local cmp_nvim_lsp = require('cmp_nvim_lsp')
  local helpers = require('lpke.core.helpers')
  local merge_tables = helpers.merge_tables
  local tc = Lpke_theme_colors

  -- stylua: ignore start
  local function hide_diagnostic_hl()
    helpers.set_hl('DiagnosticUnnecessary', {})
    helpers.set_hl('DiagnosticUnderlineOk', {})
    helpers.set_hl('DiagnosticUnderlineHint', {})
    helpers.set_hl('DiagnosticUnderlineInfo', {})
    helpers.set_hl('DiagnosticUnderlineWarn', {})
    helpers.set_hl('DiagnosticUnderlineError', {})
  end
  local function show_diagnostic_hl()
    helpers.set_hl('DiagnosticUnnecessary', { fg = tc.subtleplus })
    helpers.set_hl('DiagnosticUnderlineOk', { bg = tc.growthbg })
    helpers.set_hl('DiagnosticUnderlineHint', { bg = tc.irisbg })
    helpers.set_hl('DiagnosticUnderlineInfo', { bg = tc.foambg })
    helpers.set_hl('DiagnosticUnderlineWarn', { bg = tc.goldbg })
    helpers.set_hl('DiagnosticUnderlineError', { bg = tc.lovebg })
  end

  local function dim_diagnostic_virtual_text()
    helpers.set_hl('DiagnosticVirtualTextOk', { fg = tc.growthbg, italic = true })
    helpers.set_hl('DiagnosticVirtualTextHint', { fg = tc.irisbg, italic = true })
    helpers.set_hl('DiagnosticVirtualTextInfo', { fg = tc.foambg, italic = true })
    helpers.set_hl('DiagnosticVirtualTextWarn', { fg = tc.goldbg, italic = true })
    helpers.set_hl('DiagnosticVirtualTextError', { fg = tc.lovebg, italic = true })
  end
  local function show_diagnostic_virtual_text()
    helpers.set_hl('DiagnosticVirtualTextOk', { fg = tc.growth, italic = true })
    helpers.set_hl('DiagnosticVirtualTextHint', { fg = tc.irisfaded, italic = true })
    helpers.set_hl('DiagnosticVirtualTextInfo', { fg = tc.foamfaded, italic = true })
    helpers.set_hl('DiagnosticVirtualTextWarn', { fg = tc.goldfaded, italic = true })
    helpers.set_hl('DiagnosticVirtualTextError', { fg = tc.lovefaded, italic = true })
  end

  -- toggle LSP diagnostic highlighting globally
  Lpke_diagnostics_hl_enabled = false
  function Lpke_toggle_diagnostics_hl()
    local enabled = Lpke_diagnostics_hl_enabled
    if enabled then
      hide_diagnostic_hl()
      Lpke_diagnostics_hl_enabled = false
    else
      show_diagnostic_hl()
      Lpke_diagnostics_hl_enabled = true
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end

  -- toggle LSP diagnostic virtual text globally
  Lpke_diagnostics_virtual_text_enabled = true
  function Lpke_toggle_diagnostics_virtual_text()
    local enabled = Lpke_diagnostics_virtual_text_enabled
    if enabled then
      dim_diagnostic_virtual_text()
      Lpke_diagnostics_virtual_text_enabled = false
    else
      show_diagnostic_virtual_text()
      Lpke_diagnostics_virtual_text_enabled = true
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end

  -- theme
  helpers.set_hl('LspInfoTitle', { fg = tc.growth })
  helpers.set_hl('DiagnosticOk', { fg = tc.growth })
  helpers.set_hl('DiagnosticSignOk', { fg = tc.growth })
  helpers.set_hl('DiagnosticFloatingOk', { fg = tc.growth })
  show_diagnostic_virtual_text()
  hide_diagnostic_hl()

  -- when a language server attaches to a buffer...
  local on_attach = function(_, bufnr) -- client, bufnr
    -- respect the initial setting
    if Lpke_diagnostics_enabled_initial then
      Lpke_toggle_diagnostics(true)
    else
      Lpke_toggle_diagnostics(false)
    end

    -- set keybinds (Lazy sync required to remove old bindings)
    local opts = function(desc) return { buffer = bufnr, desc = desc  } end
    helpers.keymap_set_multi({
      -- info/toggle/reload
      {'nC', '<BS>ip', 'LspInfo', opts('Open LSP info window')},
      {'nv', '<F2>d', Lpke_toggle_diagnostics, opts('Toggle diagnostics visibility globally')},
      {'nv', '<F2>v', Lpke_toggle_diagnostics_virtual_text, opts('Toggle diagnostics virtual text brightness globally')},
      {'nv', '<F2>V', Lpke_toggle_diagnostics_hl, opts('Toggle diagnostics highlighting globally')},
      {'nC', '<leader>R', 'LspRestart', opts('Restart LSP')},

      -- smart actions
      {'n', 'gr', vim.lsp.buf.rename, opts('Smart rename')},
      {'nv', '<leader>a', vim.lsp.buf.code_action, opts('See available code actions')},

      -- hover info
      {'n', 'gh', vim.lsp.buf.hover, opts('Show documentation for what is under cursor')},
      {'n', 'gl', vim.diagnostic.open_float, opts('Show line diagnostics')},

      -- 'l'sp navigation
      {'nC', '<leader>l', 'Telescope diagnostics bufnr=0', opts('Show buffer diagnostics')},
      {'n', '[l', vim.diagnostic.goto_prev, opts('Go to previous diagnostic')},
      {'n', ']l', vim.diagnostic.goto_next, opts('Go to next diagnostic')},

      -- jump/list related code
      {'nC', '<leader>;', 'Telescope lsp_references', opts('Show LSP references')},
      {'nC', 'gd', 'Telescope lsp_definitions', opts('Show LSP definitions')},
      {'nC', 'gt', 'Telescope lsp_type_definitions', opts('Show LSP type definitions')},
      {'nC', 'gi', 'Telescope lsp_implementations', opts('Show LSP implementations')},
      {'n', 'gD', vim.lsp.buf.declaration, opts('Go to declaration')},
    })
  end
  -- stylua: ignore end

  -- used to enable autocompletion (assign to every lsp server config)
  local capabilities = cmp_nvim_lsp.default_capabilities()

  -- symbols
  local signs = {
    Error = '■',
    Warn = '▲',
    Info = '◆',
    Hint = '●',
  }
  for type, icon in pairs(signs) do
    local hl = 'DiagnosticSign' .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = '' })
  end

  vim.diagnostic.config({
    virtual_text = {
      prefix = '■',
    },
    float = {
      border = 'rounded',
    },
  })

  -- diagnostics filter
  -- TODO: this does not seem to include `eslint-lsp` diagnostics - need to add
  -- this wherever that can be as well
  local function filter_diagnostics(diag) -- diag.source, diag.message, diag.code
    -- current line diagnostics (not including `diag`)
    local ldiag =
      vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })

    -- lua
    if string.match(diag.source, '^[Ll]ua.*') then
      if string.match(diag.message, 'Unused local `_.+`.') then
        return false
      end
    end

    -- typescript
    if diag.source == 'typescript' then
      local esldiag = helpers.arr_filter((ldiag or {}), function(item)
        if type(item) ~= 'table' then
          return false
        end
        return item.source == 'eslint_d' -- deprecated: `eslint_d` linter replaced with `eslint-lsp` (mason)
      end)

      -- handle TS/eslint diagnostic double-ups
      if #esldiag > 0 then
        -- unused variables
        if diag.code == 6133 then
          return false
        end
      end
    end

    return true
  end

  -- can be overwritten per language (these will be merged in initially)
  local handlers = {
    ['textDocument/hover'] = vim.lsp.with(
      vim.lsp.handlers.hover,
      { border = 'rounded' }
    ),
    ['textDocument/signatureHelp'] = vim.lsp.with(
      vim.lsp.handlers.signature_help,
      { border = 'rounded' }
    ),
    ['textDocument/publishDiagnostics'] = vim.lsp.with(
      -- injecting custom code to allow filtering/control of diagnostic messages
      function(err, result, context, conf)
        helpers.arr_filter_inplace(result.diagnostics, filter_diagnostics) -- custom part
        vim.lsp.diagnostic.on_publish_diagnostics(err, result, context, conf) -- default part
      end,
      {
        -- ensure that signs are sorted in sign column (errors on top)
        severity_sort = true,
      }
    ),
  }

  -- configure LSP servers
  -- server = { ...setup table }
  local servers = {
    html = {},
    ts_ls = { -- formerly: `tsserver`
      init_options = {
        preferences = {
          importModuleSpecifierPreference = 'non-relative', -- use absolute/non-relative import paths if possible
          importModuleSpecifierEnding = 'minimal', -- shorten path ending if possible (omit `.ts` etc)
        },
      },
    },
    -- defaults: https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#eslint
    eslint = {
      settings = {
        rulesCustomizations = {
          {
            rule = '*exhaustive-deps',
            severity = 'off',
          },
          {
            rule = '*no-unused-vars',
            severity = 'off',
          },
          {
            rule = 'prettier/prettier',
            severity = 'warn',
          },
        },
      },
    },
    cssls = {},
    tailwindcss = {},
    jsonls = {
      filetypes = { 'json', 'jsonc' },
    },
    graphql = {
      filetypes = {
        'graphql',
        'gql',
        'svelte',
        'typescriptreact',
        'javascriptreact',
      },
    },
    emmet_ls = {
      filetypes = {
        'html',
        'htmx',
        'pug',
        'jsx',
        'javascriptreact',
        'tsx',
        'typescriptreact',
        'vue',
        'svelte',
        'css',
        'sass',
        'scss',
        'less',
        'eruby',
      },
      init_options = {
        html = {
          options = emmet_opts_global,
        },
        pug = {
          options = emmet_opts_global,
        },
        xml = {
          options = emmet_opts_global,
        },
        xsl = {
          options = emmet_opts_global,
        },
        js = {
          options = merge_tables(emmet_opts_global, emmet_opts_jsx),
        },
        jsx = {
          options = merge_tables(emmet_opts_global, emmet_opts_jsx),
        },
        svelte = {
          options = emmet_opts_global,
        },
        vue = {
          options = emmet_opts_global,
        },
        slim = {
          options = emmet_opts_global,
        },
        haml = {
          options = emmet_opts_global,
        },
      },
    },
    lua_ls = {
      settings = { -- custom settings for lua
        Lua = {
          -- make the language server recognize 'vim' global
          diagnostics = {
            globals = { 'vim' },
          },
          workspace = {
            -- make language server aware of runtime files
            library = {
              [vim.fn.expand('$VIMRUNTIME/lua')] = true,
              [vim.fn.stdpath('config') .. '/lua'] = true,
            },
          },
        },
      },
    },
    bashls = {
      filetypes = { 'sh' },
    },
    pyright = {},
  }
  for lsp, conf in pairs(servers) do
    conf.capabilities = conf.capabilities or capabilities
    conf.on_attach = conf.on_attach or on_attach
    conf.handlers = helpers.merge_tables(handlers, (conf.handlers or {}))
    lspconfig[lsp].setup(conf)
  end
end

return {
  'neovim/nvim-lspconfig',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = {
    'hrsh7th/cmp-nvim-lsp', -- completions
  },
  config = config,
}
