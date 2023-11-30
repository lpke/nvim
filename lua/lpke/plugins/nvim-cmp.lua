Lpke_auto_cmp = true

local function deprio(kind)
  return function(e1, e2)
    if e1:get_kind() == kind then
      return false
    end
    if e2:get_kind() == kind then
      return true
    end
  end
end

local function config()
  local cmp = require('cmp')
  local types = require('cmp.types')
  local luasnip = require('luasnip')
  local helpers = require('lpke.core.helpers')
  local tc = Lpke_theme_colors

  -- toggle automatic cmp completion menu (can still be activated manually)
  function Lpke_toggle_auto_cmp()
    if not Lpke_auto_cmp then
      cmp.setup({
        completion = {
          autocomplete = { types.cmp.TriggerEvent.TextChanged },
        },
      })
      Lpke_auto_cmp = true
    else
      cmp.setup({
        completion = {
          autocomplete = false,
        },
      })
      if cmp.visible then
        cmp.abort()
      end
      Lpke_auto_cmp = false
    end
    pcall(function()
      require('lualine').refresh()
    end)
  end

  local function cmp_mapping(conds, action, custom_fallback)
    local cond_v = function()
      return true
    end
    local cond_a = function()
      return true
    end
    local cond_d = function()
      return true
    end
    for char in conds:gmatch('.') do
      if char == 'v' then
        cond_v = cmp.visible
      elseif char == 'a' then
        cond_a = cmp.get_active_entry
      elseif char == 'd' then
        cond_d = cmp.visible_docs
      end
    end
    return function(fallback)
      if cond_v() and cond_a() and cond_d() then
        action()
      else
        if custom_fallback then
          custom_fallback()
        else
          fallback()
        end
      end
    end
  end

  -- theme
  helpers.set_hl('CmpItemKind', { fg = tc.muted, italic = true })
  helpers.set_hl('CmpItemKindDefault', { fg = tc.rose, italic = true })
  helpers.set_hl('CmpItemKindFunction', { fg = tc.rose, italic = true })
  helpers.set_hl('CmpItemKindSnippet', { fg = tc.gold, italic = true })
  helpers.set_hl('CmpItemKindMethod', { fg = tc.iris, italic = true })
  helpers.set_hl('CmpItemKindClass', { fg = tc.pine, italic = true })
  helpers.set_hl('CmpItemKindVariable', { fg = tc.textminus, italic = true })
  helpers.set_hl('CmpItemKindInterface', { fg = tc.foam, italic = true })

  -- keymaps - general
  helpers.keymap_set_multi({
    {
      'ni',
      '<F2>m',
      Lpke_toggle_auto_cmp,
      { desc = 'Toggle automatic cmp menu display when typing' },
    },
  })

  -- CMP SETUP: GENERAL/INSERT
  cmp.setup({
    -- options
    completion = {
      completeopt = 'menu,menuone,noselect,preview',
    },
    performance = {
      debounce = 200,
    },
    window = {
      documentation = {
        max_width = 200,
        max_height = 200,
        border = 'rounded',
        winhighlight = 'FloatBorder:FloatBorder',
      },
    },

    -- keymaps - editor
    mapping = {
      ['<F2>,'] = cmp.mapping.complete(),

      -- completion menu
      ['<Up>'] = cmp.mapping.select_prev_item(),
      ['<Down>'] = cmp.mapping.select_next_item(),
      ['<C-p>'] = cmp.mapping.select_prev_item(),
      ['<C-n>'] = cmp.mapping.select_next_item(),
      ['<F2>p'] = cmp.mapping.select_prev_item(),
      ['<F2>n'] = cmp.mapping.select_next_item(),

      -- preview/'docs' window
      ['<C-k>'] = cmp.mapping.scroll_docs(-4),
      ['<C-j>'] = cmp.mapping.scroll_docs(4),
      -- confim/abort
      ['<F2><CR>'] = cmp.mapping.confirm({
        select = true,
      }),
      ['<C-c>'] = cmp.mapping.abort(),
    },

    -- autocompletion suggestion sources (in order of priority)
    sources = cmp.config.sources({
      { name = 'nvim_lsp', keyword_length = 3 }, -- LSP
      { name = 'luasnip', keyword_length = 5 }, -- snippets
      { name = 'path' }, -- file system paths
      { name = 'buffer', keyword_length = 5 }, -- text within current buffer
    }),

    -- autocompletion suggestion sorting
    sorting = {
      comparators = {
        deprio(types.lsp.CompletionItemKind.Snippet),
        -- deprio(types.lsp.CompletionItemKind.Text),
        -- deprio(types.lsp.CompletionItemKind.Keyword),
      },
    },

    -- handle snippets
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },

    -- kind string maps
    formatting = {
      format = function(entry, vim_item)
        -- name
        vim_item.kind = ' '
          .. helpers.map_string(vim_item.kind, {
            { 'Snippet', 'Snip' },
            { 'Function', 'Func' },
            { 'Constructor', 'Constr' },
            { 'Variable', 'Var' },
            { 'Interface', 'Interf' },
            { 'Property', 'Prop' },
            { 'Reference', 'Ref' },
            { 'EnumMember', 'EnumMbr' },
            { 'Constant', 'Const' },
            { 'TypeParameter', 'TypeParam' },
          })
        -- source
        vim_item.menu = ({
          buffer = '⌨',
          nvim_lsp = '◌',
          luasnip = '☇',
          nvim_lua = '◉',
          latex_symbols = '∑',
        })[entry.source.name]
        return vim_item
      end,
    },
  })

  -- CMP SETUP: COMMAND-LINE
  local cmdline_mapping = {
    ['<F2>,'] = { c = cmp.mapping.complete() },

    -- completion menu
    ['<Tab>'] = {
      c = cmp_mapping('v', cmp.select_next_item, function()
        local cmd_type = vim.fn.getcmdtype()
        if (cmd_type == '/') or (cmd_type == '?') then
          cmp.complete()
        else
          Lpke_feedkeys('<Tab>', 'tn')
        end
      end),
    },
    ['<S-Tab>'] = {
      c = cmp_mapping('v', cmp.select_prev_item, function()
        Lpke_feedkeys('<S-Tab>', 'tn')
      end),
    },
    ['<C-n>'] = { c = cmp_mapping('v', cmp.select_next_item) },
    ['<C-p>'] = { c = cmp_mapping('v', cmp.select_prev_item) },
    ['<F2>j'] = { c = cmp_mapping('v', cmp.select_next_item) },
    ['<F2>k'] = { c = cmp_mapping('v', cmp.select_prev_item) },
    -- preview/'docs' window
    ['<C-k>'] = {
      c = cmp_mapping('vd', function()
        cmp.scroll_docs(-4)
      end),
    },
    ['<C-j>'] = {
      c = cmp_mapping('vd', function()
        cmp.scroll_docs(4)
      end),
    },
    -- confirm/abort
    ['<F2><CR>'] = {
      c = cmp_mapping('', function()
        cmp.confirm({ select = true })
      end),
    },
    ['<C-c>'] = { c = cmp_mapping('v', cmp.abort) },
  }
  cmp.setup.cmdline({ '/', '?' }, {
    mapping = cmdline_mapping,
    sources = {
      { name = 'buffer', keyword_length = 3 },
    },
  })
  cmp.setup.cmdline(':', {
    mapping = cmdline_mapping,
    sources = cmp.config.sources({
      { name = 'path' },
      { name = 'cmdline' },
    }),
    completion = {
      autocomplete = false,
    },
  })
end

return {
  'hrsh7th/nvim-cmp',
  event = 'VeryLazy',
  dependencies = {
    'hrsh7th/cmp-buffer', -- source for text in buffer
    'hrsh7th/cmp-path', -- source for file system paths
    'hrsh7th/cmp-cmdline', -- source for cmdline : suggestions
    'L3MON4D3/LuaSnip', -- snippet engine
    'saadparwaiz1/cmp_luasnip', -- snippet autocompletion
  },
  config = config,
}
