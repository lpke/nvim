local function config()
  local ls = require('luasnip')
  local helpers = require('lpke.core.helpers')
  local snippets = require('lpke.snippets')

  -- stylua: ignore start
  helpers.keymap_set_multi({
    {'i', '<Tab>', function()
      local snippet_expanded = ls.expand()
      if snippet_expanded ~= true then
        Lpke_feedkeys('<Tab>', 'tn')
      end
    end, { desc = 'Luasnip: Expand snippet' }},
    {'inv!', [[<F2>']], function() pcall(function() ls.jump(1) end) end,
      { desc = 'Luasnip: Jump forward in snippet' }},
    {'inv!', [[<F2>"]], function() pcall(function() ls.jump(-1) end) end,
      { desc = 'Luasnip: Jump backward in snippet' }},
  })
  -- stylua: ignore end

  ls.config.set_config({
    enable_autosnippets = true,
    -- store_selection_keys = '<Tab>',
  })

  ls.add_snippets(nil, snippets)
end

return {
  'L3MON4D3/LuaSnip',
  version = 'v2.*', -- follow latest release
  build = 'make install_jsregexp',
  config = config,
}
