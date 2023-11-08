-- toggle LSP diagnostics globally
Lpke_diagnostics_enabled_initial = true
Lpke_diagnostics_enabled_prev = nil
function Lpke_toggle_diagnostics(choice)
  -- getting and storing current state
  local enabled = not vim.diagnostic.is_disabled()
  Lpke_diagnostics_enabled_prev = enabled

  -- manual choice
  if choice ~= nil then
    if choice == false then
      pcall(vim.diagnostic.disable)
    elseif choice == true then
      pcall(vim.diagnostic.enable)
    elseif choice == 'prev' then
      if Lpke_diagnostics_enabled_prev == true then
        pcall(vim.diagnostic.enable)
      else
        pcall(vim.diagnostic.disable)
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
    pcall(vim.diagnostic.disable)
  else
    pcall(vim.diagnostic.enable)
  end
  pcall(function()
    require('lualine').refresh()
  end)
end

local function config()
  local lspconfig = require('lspconfig')
  local cmp_nvim_lsp = require('cmp_nvim_lsp')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  local function set_diagnostic_hl()
    helpers.set_hl('DiagnosticUnnecessary', {})
    helpers.set_hl('DiagnosticUnderlineHint', {})
    helpers.set_hl('DiagnosticUnderlineInfo', {})
    helpers.set_hl('DiagnosticUnderlineWarn', {})
    helpers.set_hl('DiagnosticUnderlineError', {})
    helpers.set_hl('DiagnosticUnderlineOk', {})
  end

  -- toggle LSP diagnostic highlighting globally
  Lpke_diagnostics_hl_enabled = false
  function Lpke_toggle_diagnostics_hl()
    local enabled = Lpke_diagnostics_hl_enabled
    if enabled then
      set_diagnostic_hl()
      Lpke_diagnostics_hl_enabled = false
    else
      helpers.set_hl('DiagnosticUnnecessary', { fg = tc.subtleplus })
      helpers.set_hl('DiagnosticUnderlineHint', { bg = tc.irisbg })
      helpers.set_hl('DiagnosticUnderlineInfo', { bg = tc.foambg })
      helpers.set_hl('DiagnosticUnderlineWarn', { bg = tc.goldbg })
      helpers.set_hl('DiagnosticUnderlineError', { bg = tc.lovebg })
      helpers.set_hl('DiagnosticUnderlineOk', { bg = tc.growthbg })
      Lpke_diagnostics_hl_enabled = true
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end

  -- stylua: ignore start
  -- theme
  helpers.set_hl('LspInfoTitle', { fg = tc.growth })
  helpers.set_hl('DiagnosticOk', { fg = tc.growth })
  helpers.set_hl('DiagnosticSignOk', { fg = tc.growth })
  helpers.set_hl('DiagnosticFloatingOk', { fg = tc.growth })
  helpers.set_hl('DiagnosticVirtualTextError', { fg = tc.lovefaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextWarn', { fg = tc.goldfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextHint', { fg = tc.irisfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextInfo', { fg = tc.foamfaded, italic = true })
  helpers.set_hl('DiagnosticVirtualTextOk', { fg = tc.growth, italic = true })
  set_diagnostic_hl()

  -- when a language server attaches to a buffer...
  local on_attach = function(client, bufnr)
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
      {'nv', '<F2>v', Lpke_toggle_diagnostics_hl, opts('Toggle diagnostics highlighting globally')},
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

  -- can be overwritten per language
  local handlers = {
    ['textDocument/hover'] = vim.lsp.with(
      vim.lsp.handlers.hover,
      { border = 'rounded' }
    ),
    ['textDocument/signatureHelp'] = vim.lsp.with(
      vim.lsp.handlers.signature_help,
      { border = 'rounded' }
    ),
  }

  -- configure LSP servers
  -- server = { ...setup table }
  local servers = {
    html = {},
    tsserver = {},
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
        'typescriptreact',
        'javascriptreact',
        'vue',
        'svelte',
        'css',
        'sass',
        'scss',
        'less',
        'eruby',
      },
      init_options = {},
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
    conf.handlers = conf.handlers or handlers
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
