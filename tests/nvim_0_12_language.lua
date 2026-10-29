-- Run with the isolated data directory: run-nvim --headless -u NONE -l tests/nvim_0_12_language.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
table.unpack = table.unpack or unpack
local plugin_root = vim.fn.stdpath('data') .. '/lazy/'
local plugins = {
  'LuaSnip',
  'cmp-buffer',
  'cmp-cmdline',
  'cmp-nvim-lsp',
  'cmp-path',
  'cmp_luasnip',
  'conform.nvim',
  'mason-lspconfig.nvim',
  'mason-tool-installer.nvim',
  'mason.nvim',
  'nvim-autopairs',
  'nvim-cmp',
  'nvim-lint',
  'nvim-lspconfig',
  'nvim-treesitter',
  'nvim-treesitter-context',
  'nvim-treesitter-textobjects',
  'nvim-ts-context-commentstring',
  'Comment.nvim',
  'copilot.lua',
}
for _, plugin in ipairs(plugins) do
  vim.opt.runtimepath:append(plugin_root .. plugin)
end
vim.opt.runtimepath:prepend(vim.fn.stdpath('data') .. '/site')
vim.opt.runtimepath:append(vim.fn.getcwd() .. '/after')
vim.cmd.runtime('plugin/filetypes.lua')
require('mason').setup()
Lpke_theme_colors = setmetatable({}, {
  __index = function()
    return '#aaaaaa'
  end,
})
require('lpke.core.globals.globals')
require('lpke.core.globals.git')
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function setup(name)
  require('lpke.plugins.' .. name).config()
end
local function buffer(ft, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { '' })
  return bufnr
end

-- Compile every configured snippet, including formatter bodies and inheritance.
setup('luasnip')
local snippet_count = 0
for _, snippets in pairs(require('lpke.snippets')) do
  snippet_count = snippet_count + #snippets
end
check(snippet_count > 100, 'custom snippets did not load')
local ls = require('luasnip')
buffer('lua')
ls.lsp_expand('local ${1:name} = ${2:value}')
check(
  vim.api.nvim_get_current_line() == 'local name = value',
  'LuaSnip expansion'
)
check(ls.jumpable(1), 'LuaSnip jump state')
ls.unlink_current()
buffer('lpke_missing_parser', { 'x' })
check(
  require('lpke.snippets.ls_helpers').has_ts_ancestor('function')('x') == false,
  'missing parser must not crash snippet conditions'
)

setup('comment_ts_context')
setup('comment')
vim.bo.commentstring = '# %s'
require('Comment.api').toggle.linewise.current()
check(
  vim.api.nvim_get_current_line() == '# x',
  'comment fallback without a parser'
)
require('Comment.api').toggle.linewise.current()
check(
  vim.api.nvim_get_current_line() == 'x',
  'uncomment fallback without a parser'
)

-- Exercise queries for each installed grammar, including injections and offsets.
local grammar_count, query_count = 0, 0
local query_errors = {}
for _, lang in ipairs(require('nvim-treesitter').get_installed('parsers')) do
  grammar_count = grammar_count + 1
  check(vim.treesitter.language.add(lang), 'parser load: ' .. lang)
  for _, kind in ipairs({
    'highlights',
    'indents',
    'folds',
    'injections',
    'locals',
    'textobjects',
    'context',
  }) do
    local ok, query = pcall(vim.treesitter.query.get, lang, kind)
    if not ok then
      query_errors[#query_errors + 1] = lang
        .. '/'
        .. kind
        .. ': '
        .. tostring(query)
    elseif query then
      query_count = query_count + 1
    end
  end
end
check(#query_errors == 0, table.concat(query_errors, '\n'))
check(grammar_count >= 25, 'configured parsers are missing')
check(vim.treesitter.language.get_lang('jsonc') == 'json', 'jsonc parser alias')
check(
  vim.treesitter.language.get_lang('typescriptreact') == 'tsx',
  'tsx parser alias'
)
setup('treesitter_textobjects')
buffer('lua', { 'local function example()', '  return 1', 'end' })
vim.treesitter.start()
check(
  vim.treesitter.get_parser():parse()[1]:root():has_error() == false,
  'Lua parse'
)
check(
  #require('nvim-treesitter-textobjects.shared').available_textobjects(
      'lua',
      'textobjects'
    ) > 0,
  'textobject captures'
)
setup('treesitter_context')
check(
  pcall(require('treesitter-context.context').get),
  'Treesitter context query'
)

-- Existing parsers still attach when an update fails before installing anything.
local treesitter = require('nvim-treesitter')
local update, install = treesitter.update, treesitter.install
treesitter.update = function()
  return {
    await = function(_, callback)
      callback('offline')
    end,
  }
end
treesitter.install = function()
  return {
    await = function(_, callback)
      callback()
    end,
  }
end
local offline_buffer = buffer('lua', { 'local x = 1' })
require('lpke.plugins.helpers.treesitter').setup({ 'lua' })
check(
  vim.wait(1000, function()
    return vim.treesitter.highlighter.active[offline_buffer] ~= nil
  end),
  'existing parsers attach offline'
)
check(vim.bo.syntax == '', 'regex syntax stays disabled with Treesitter')
check(
  vim.bo.indentexpr == "v:lua.require'nvim-treesitter'.indentexpr()",
  'Treesitter indentation'
)
treesitter.update, treesitter.install = update, install
vim.api.nvim_del_augroup_by_name('LpkeTreesitter')

buffer(
  'typescriptreact',
  { 'const element = (', '  <div>', '    hello', '  </div>', ');' }
)
vim.treesitter.get_parser():parse(true)
vim.api.nvim_win_set_cursor(0, { 3, 4 })
require('Comment.api').toggle.linewise.current()
check(
  vim.api.nvim_get_current_line():find('{/%*') ~= nil,
  'JSX comments inside markup'
)
require('Comment.api').toggle.linewise.current()
check(vim.api.nvim_get_current_line() == '    hello', 'JSX uncomment')
buffer('html', { '<script>', 'const value = 1;', '</script>' })
vim.treesitter.get_parser():parse(true)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
require('Comment.api').toggle.linewise.current()
check(
  vim.api.nvim_get_current_line() == '// const value = 1;',
  'JavaScript comments inside HTML'
)

setup('nvim_cmp')
setup('autopairs')
check(
  #require('nvim-autopairs').get_rules('`') == 0,
  'backticks must remain unpaired'
)
for _, ft in ipairs({ 'lua', 'javascriptreact', 'codecompanion' }) do
  local bufnr = buffer(ft)
  local keys = require('nvim-autopairs').autopairs_map(bufnr, '(')
  check(keys:find('()', 1, true) ~= nil, 'parenthesis pairing: ' .. ft)
  buffer(ft, { 'word ' })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  check(
    require('nvim-autopairs').autopairs_map(0, '"') == '"',
    'quotes after identifiers: ' .. ft
  )
end
local cmp = require('cmp')
check(
  cmp.get_config().window.documentation.border == 'rounded',
  'completion docs border'
)
for _, response in ipairs({
  { items = { { label = 'alphabet' } }, itemDefaults = vim.NIL },
  { items = vim.NIL },
}) do
  buffer('text', { 'alpha' })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local source = require('cmp.source').new('audit', {
    complete = function(_, _, callback)
      callback(response)
    end,
  })
  local done = false
  source:complete(
    require('cmp.context').new(nil, {
      reason = require('cmp.types').cmp.ContextReason.Manual,
    }),
    function()
      done = true
    end
  )
  check(
    vim.wait(1000, function()
      return done
    end),
    'completion JSON null response'
  )
  check(
    #source.entries == (response.items == vim.NIL and 0 or 1),
    'completion null entry count'
  )
end
Lpke_toggle_auto_cmp()
check(Lpke_auto_cmp == false, 'automatic completion disabled')
Lpke_toggle_auto_cmp()
check(Lpke_auto_cmp == true, 'automatic completion restored')
check(
  require('cmp_nvim_lsp').default_capabilities().textDocument.completion.completionItem.snippetSupport,
  'LSP snippet capability'
)
check(
  require('cmp_luasnip').new():is_available(),
  'snippet completion provider'
)
check(
  type(require('cmp_buffer').complete) == 'function',
  'buffer completion provider'
)
check(
  type(require('cmp_path').new().complete) == 'function',
  'path completion provider'
)
check(
  type(require('cmp_cmdline').new().complete) == 'function',
  'cmdline completion provider'
)

-- The configured diagnostic workflows use the current enable/filter signature.
require('lpke.plugins.lsp.lspconfig')
require('lpke.lsp')
vim.diagnostic.config(Lpke_diagnostic_config)
Lpke_toggle_diagnostics(false)
check(vim.diagnostic.is_enabled() == false, 'diagnostics disabled')
Lpke_toggle_diagnostics(true)
check(vim.diagnostic.is_enabled(), 'diagnostics enabled')
Lpke_toggle_diagnostic_signs()
check(
  vim.diagnostic.config().signs.text[vim.diagnostic.severity.ERROR] == '■',
  'diagnostic signs'
)
Lpke_toggle_diagnostic_signs()
check(vim.diagnostic.config().signs == false, 'diagnostic signs restored')
Lpke_toggle_diagnostics_hl()
check(
  vim.diagnostic.config().virtual_lines == true,
  'diagnostic virtual lines enabled'
)
Lpke_toggle_diagnostics_hl()
check(
  vim.diagnostic.config().virtual_lines == false,
  'diagnostic virtual text restored'
)
Lpke_toggle_virtual_text_current_line()
check(
  vim.diagnostic.config().virtual_text.current_line == true,
  'current-line virtual text'
)
Lpke_toggle_dim_virtual_text()
check(
  Lpke_diagnostics_virtual_text_enabled == false,
  'diagnostic virtual text dimmed'
)
Lpke_toggle_dim_virtual_text()
local ts_diagnostics = require('lpke.lsp.helpers.ts_diagnostics')
check(
  ts_diagnostics.should_keep({ code = 2304 }, true),
  'missing-name diagnostics retained'
)
check(
  not ts_diagnostics.should_keep({ code = 80004 }, true),
  'JS migration suggestions filtered'
)
check(
  not ts_diagnostics.should_keep({ code = 2322 }, true),
  'relaxed inferred JS diagnostics'
)
ts_diagnostics.toggle_inferred_mode('full')
check(
  ts_diagnostics.should_keep({ code = 2322 }, true),
  'full inferred JS diagnostics'
)
ts_diagnostics.toggle_inferred_mode('relaxed')

setup('formatting')
buffer('lua', { 'local x={a=1}' })
local formatted =
  require('conform').format({ async = false, timeout_ms = 5000 })
check(
  formatted == true and vim.api.nvim_get_current_line() == 'local x = { a = 1 }',
  'Stylua formatting'
)
setup('nvim_lint')
Lpke_toggle_linting()
check(Lpke_linting_enabled == false, 'lint disabled')
Lpke_toggle_linting()
check(Lpke_linting_enabled == true, 'lint restored')

-- A real Neovim LSP client with an in-process transport catches URI and
-- changetracking regressions without contacting Copilot or requesting tokens.
local chat = buffer('codecompanion', { '# Chat', '', 'Hello' })
vim.api.nvim_buf_set_name(chat, 'lpke-audit-old-chat')
local notifications, sequence = {}, 0
local transport = {
  request = function(method, _, callback)
    sequence = sequence + 1
    if method == 'initialize' then
      vim.schedule(function()
        callback(nil, {
          capabilities = {
            textDocumentSync = { openClose = true, change = 2 },
          },
        })
      end)
    elseif callback then
      vim.schedule(function()
        callback(nil, nil)
      end)
    end
    return true, sequence
  end,
  notify = function(method, params)
    notifications[#notifications + 1] = { method = method, params = params }
    return true
  end,
  is_closing = function()
    return false
  end,
  terminate = function() end,
}
local client_id = vim.lsp.start({
  name = 'lpke-audit',
  cmd = function()
    return transport
  end,
})
local client = vim.lsp.get_client_by_id(client_id)
check(
  vim.wait(1000, function()
    return client.initialized
  end),
  'mock LSP initialization'
)
local group = vim.api.nvim_create_augroup('copilot.client', { clear = true })
local original_calls = 0
vim.api.nvim_create_autocmd('BufFilePost', {
  group = group,
  desc = '[copilot] (client) buffer filename changed',
  callback = function()
    original_calls = original_calls + 1
  end,
})
local saved_copilot_client = package.loaded['copilot.client']
package.loaded['copilot.client'] = {
  augroup = group,
  get = function()
    return client
  end,
  buf_is_attached = function(bufnr)
    return vim.lsp.buf_is_attached(bufnr, client_id)
  end,
}
local copilot_config = require('lpke.plugins.ai.copilot').config
local patch
for index = 1, 50 do
  local name, value = debug.getupvalue(copilot_config, index)
  if not name then
    break
  end
  if name == 'patch_copilot_codecompanion_title_changes' then
    patch = value
  end
end
check(type(patch) == 'function', 'Copilot rename patch found')
patch()
notifications = {}
vim.api.nvim_buf_set_name(chat, 'lpke-audit-new-chat')
vim.api.nvim_buf_set_name(chat, 'lpke-audit-final-chat')
vim.wait(100, function()
  return #notifications >= 2
end)
check(original_calls == 0, 'chat rename must avoid Copilot detach/reattach')
local documents = vim.tbl_filter(function(event)
  return event.method == 'textDocument/didClose'
    or event.method == 'textDocument/didOpen'
end, notifications)
check(#documents == 2, 'rename must close once and reopen once')
check(
  documents[1].method == 'textDocument/didClose'
    and documents[1].params.textDocument.uri:match('lpke%-audit%-old%-chat$'),
  'old URI closed'
)
check(
  documents[2].method == 'textDocument/didOpen'
    and documents[2].params.textDocument.uri:match('lpke%-audit%-final%-chat$'),
  'final URI opened'
)
check(
  vim.lsp.buf_is_attached(chat, client_id),
  'Copilot client remains attached'
)
vim.api.nvim_buf_set_lines(chat, 2, 3, false, { 'Edited after rename' })
check(
  vim.wait(1000, function()
    return vim.tbl_contains(
      vim.tbl_map(function(event)
        return event.method
      end, notifications),
      'textDocument/didChange'
    )
  end),
  'document changes continue after rename'
)
require('vim.lsp._changetracking')._send_did_save(chat)
documents = vim.tbl_filter(function(event)
  return event.method == 'textDocument/didClose'
    or event.method == 'textDocument/didOpen'
end, notifications)
check(#documents == 2, 'saving renamed document must not reopen a stale URI')
package.loaded['copilot.client'] = saved_copilot_client
client:stop(true)
print(
  ('PASS %d checks, %d snippet entries, %d grammars, %d queries'):format(
    checks,
    snippet_count,
    grammar_count,
    query_count
  )
)
vim.cmd('qa!')
