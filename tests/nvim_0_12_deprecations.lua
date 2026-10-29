-- Run with: run-nvim --headless -u NONE -l tests/nvim_0_12_deprecations.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
table.unpack = table.unpack or unpack
vim.o.columns = 160
vim.o.lines = 60

local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end

local deprecations = {}
local deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  deprecations[#deprecations + 1] = debug.traceback(name, 2)
  return deprecate(name, ...)
end

require('lpke.core.globals.globals')
local helpers = require('lpke.core.helpers')
local first = vim.api.nvim_get_current_buf()
local second = vim.api.nvim_create_buf(true, false)
helpers.keymap_set({ 'n', '<F12>', '<Nop>', { buf = first } })
check(#vim.api.nvim_buf_get_keymap(first, 'n') == 1, 'local keymap target')
check(#vim.api.nvim_buf_get_keymap(second, 'n') == 0, 'local keymap scope')
helpers.keymap_set({ 'nD', '<F12>', '', { buf = first } })
check(#vim.api.nvim_buf_get_keymap(first, 'n') == 0, 'local keymap deletion')
helpers.ft_keymap_set_multi('lpke_deprecation_test', {
  { 'n', '<F12>', '<Nop>' },
})
vim.bo[second].filetype = 'lpke_deprecation_test'
check(#vim.api.nvim_buf_get_keymap(second, 'n') == 1, 'filetype keymap target')
check(#vim.api.nvim_buf_get_keymap(first, 'n') == 0, 'filetype keymap scope')

-- Buffer autocmds still clean up the messages view and return focus.
require('lpke.core.globals.messages')
Lpke_toggle_messages()
local messages = Lpke_messages_buf_id
check(messages ~= nil, 'messages buffer opened')
vim.api.nvim_buf_delete(messages, { force = true })
check(
  vim.wait(1000, function()
    return Lpke_messages_buf_id == nil
  end),
  'messages cleanup callback'
)
check(vim.api.nvim_get_current_buf() == first, 'messages focus restored')

-- A real terminal channel works for both sending input and stopping the job.
require('lpke.core.globals.float')
local terminal = Lpke_term(nil, { command = { 'cat' } })
check(terminal.chan_id > 0, 'floating terminal channel')
check(
  vim.bo[terminal.buf].channel == terminal.chan_id,
  'terminal channel option'
)
vim.api.nvim_chan_send(terminal.chan_id, 'deprecation test\n')
check(
  vim.wait(1000, function()
    return table
      .concat(vim.api.nvim_buf_get_lines(terminal.buf, 0, -1, false), '\n')
      :find('deprecation test', 1, true) ~= nil
  end),
  'terminal input reached process'
)
helpers.stop_term()
check(
  vim.wait(1000, function()
    return vim.fn.jobwait({ terminal.chan_id }, 0)[1] ~= -1
  end),
  'terminal job stopped'
)
vim.api.nvim_win_close(terminal.win, true)
vim.api.nvim_buf_delete(terminal.buf, { force = true })

-- Use an actual libuv listener to exercise HTTP, heartbeat, and timer cleanup.
local uv = vim.uv
local listener = assert(uv.new_tcp())
assert(listener:bind('127.0.0.1', 0))
local port = listener:getsockname().port
local received = {}
assert(listener:listen(8, function(err)
  assert(not err, err)
  local peer = assert(uv.new_tcp())
  listener:accept(peer)
  peer:read_start(function(read_err, data)
    assert(not read_err, read_err)
    if not data then
      return
    end
    received[#received + 1] = data
    peer:read_stop()
    local body = '{"active_heartbeat_count":1}'
    peer:write(
      'HTTP/1.1 200 OK\r\nContent-Length: ' .. #body .. '\r\n\r\n' .. body,
      function()
        peer:shutdown(function()
          peer:close()
        end)
      end
    )
  end)
end))
local heartbeat = require('lpke.core.html_server.heartbeat')
local server =
  { path = vim.fn.tempname() .. '.html', port = port, token = 'test' }
heartbeat.attach(server)
check(
  vim.wait(2000, function()
    return server.active_heartbeat_count == 1
  end),
  'HTTP heartbeat response'
)
check(
  received[1]:find('POST /__lpke_live_reload_heartbeat', 1, true),
  'heartbeat request'
)
check(
  received[1]:find('X-LPKE-OHS-Token: test', 1, true),
  'heartbeat authentication'
)
check(heartbeat.is_attached(server.path), 'heartbeat tracked')
heartbeat.detach(server)
check(not heartbeat.is_attached(server.path), 'heartbeat detached')
heartbeat.stop()
listener:close()

local html_config = require('lpke.core.html_server.config')
local original_registry_dir, original_registry_path =
  html_config.registry_dir, html_config.registry_path
local registry_dir = vim.fn.tempname()
html_config.registry_dir = registry_dir
html_config.registry_path = registry_dir .. '/servers.json'
local registry = require('lpke.core.html_server.registry')
check(registry.upsert(server), 'registry atomic write')
check(registry.find(server.path).port == port, 'registry read after rename')
check(registry.remove(server.path, 'test'), 'registry removal')
html_config.registry_dir, html_config.registry_path =
  original_registry_dir, original_registry_path
vim.fn.delete(registry_dir, 'rf')

-- Save a real unnamed-buffer backup using the current libuv clock.
require('lpke.core.globals.yank_layout')
local no_name = require('lpke.core.globals.no_name')
local backup_dir = vim.fn.tempname()
no_name.config.backup_dir = backup_dir
vim.cmd('new')
local unnamed = vim.api.nvim_get_current_buf()
vim.bo.filetype = 'lua'
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { 'local saved = true' })
no_name.close_current()
local backups = vim.fn.glob(backup_dir .. '/*_no-name.lua', false, true)
check(#backups == 1, 'unnamed backup timestamp')
check(
  vim.fn.readfile(backups[1])[1] == 'local saved = true',
  'unnamed backup contents'
)
check(not vim.api.nvim_buf_is_valid(unnamed), 'unnamed buffer closed')
vim.fn.delete(backup_dir, 'rf')

-- API docs create native buffer-local mappings without replacing keymap.set.
local docs = vim.fn.tempname() .. '.html.md'
vim.fn.writefile({ '# Documentation', 'Test paragraph' }, docs)
Config = { follow_link_keymap = 'gd' }
local common = require('lpke.local_plugins_src.apidocs.common')
local native_keymap_set = vim.keymap.set
local docs_buf = common.open_doc_in_cur_window(docs)
check(docs_buf ~= nil, 'API docs opened')
check(
  vim.fn.maparg('gd', 'n', false, true).buffer == 1,
  'API docs local mapping'
)
check(vim.keymap.set == native_keymap_set, 'native keymap function retained')
vim.api.nvim_buf_delete(docs_buf, { force = true })
vim.fn.delete(docs)

local plugin_root = vim.fn.stdpath('data') .. '/lazy/'
vim.opt.runtimepath:append(plugin_root .. 'plenary.nvim')
vim.opt.runtimepath:append(plugin_root .. 'telescope.nvim')
local fixture_dir = common.data_folder() .. 'lpke-deprecation-fixture'
vim.fn.mkdir(fixture_dir, 'p')
vim.fn.writefile(
  { '# API fixture', 'needle' },
  fixture_dir .. '/example#index.html.md'
)
local apidocs_spec = require('lpke.plugins.apidocs')
apidocs_spec.init()
apidocs_spec.config()
local pickers = require('telescope.pickers')
local builtin = require('telescope.builtin')
local original_new, original_live_grep = pickers.new, builtin.live_grep
local apidocs = require('lpke.local_plugins_src.apidocs.api')
apidocs.apidocs_open({ picker = 'telescope' })
local state = require('telescope.actions.state')
local function picker_named(name)
  local ok, picker =
    pcall(state.get_current_picker, vim.api.nvim_get_current_buf())
  return ok and picker ~= nil and picker.prompt_title == name
end
check(
  vim.wait(1000, function()
    return picker_named('API docs')
  end),
  'API docs picker opened'
)
check(
  vim.fn.maparg('<CR>', 'i', false, true).buffer == 1,
  'API docs Telescope local mapping'
)
vim.fn.maparg('<A-s>', 'i', false, true).callback()
check(
  vim.wait(1000, function()
    return picker_named('API docs search')
  end),
  'API docs search toggle'
)
vim.fn.maparg('<A-s>', 'i', false, true).callback()
check(
  vim.wait(1000, function()
    return picker_named('API docs')
  end),
  'API docs open toggle'
)
require('telescope.actions').close(vim.api.nvim_get_current_buf())
check(
  pickers.new == original_new and builtin.live_grep == original_live_grep,
  'Telescope wrappers restored'
)
check(
  vim.keymap.set == native_keymap_set,
  'API docs retained native keymap setter'
)
vim.fn.delete(fixture_dir, 'rf')

-- Exercise the configured diagnostic mappings with native diagnostics and floats.
Lpke_theme_colors = setmetatable({}, {
  __index = function()
    return '#aaaaaa'
  end,
})
vim.opt.runtimepath:append(plugin_root .. 'cmp-nvim-lsp')
require('lpke.lsp.globals')
local lsp_settings = require('lpke.lsp')
local servers = lsp_settings.enabled_language_servers
lsp_settings.enabled_language_servers = {}
require('lpke.plugins.lsp.lspconfig').config()
lsp_settings.enabled_language_servers = servers
local diag_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(diag_buf)
vim.api.nvim_buf_set_lines(
  diag_buf,
  0,
  -1,
  false,
  { 'first line', 'second line', 'third line' }
)
local namespace = vim.api.nvim_create_namespace('lpke_deprecation_test')
vim.diagnostic.set(namespace, diag_buf, {
  {
    lnum = 1,
    col = 0,
    message = 'next diagnostic',
    severity = vim.diagnostic.severity.ERROR,
  },
  {
    lnum = 2,
    col = 0,
    message = 'last diagnostic',
    severity = vim.diagnostic.severity.ERROR,
  },
})
local original_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(original_win, { 1, 0 })
vim.fn.maparg(']l', 'n', false, true).callback()
check(
  vim.api.nvim_win_get_cursor(original_win)[1] == 2,
  'next diagnostic position'
)
local function diagnostic_float()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= '' then
      return win
    end
  end
end
check(vim.wait(1000, diagnostic_float), 'diagnostic float opened')
local float = diagnostic_float()
check(
  vim.api.nvim_get_current_win() == original_win,
  'diagnostic float did not take focus'
)
check(
  vim.api.nvim_win_get_config(float).border[1] == '╭',
  'diagnostic float rounded border'
)
check(
  table
    .concat(
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false),
      '\n'
    )
    :find('next diagnostic', 1, true),
  'diagnostic float contents'
)
vim.api.nvim_win_close(float, true)
vim.fn.maparg(']l', 'n', false, true).callback()
check(
  vim.api.nvim_win_get_cursor(original_win)[1] == 3,
  'second diagnostic position'
)
vim.fn.maparg('[l', 'n', false, true).callback()
check(
  vim.api.nvim_win_get_cursor(original_win)[1] == 2,
  'previous diagnostic position'
)
vim.wait(50)

-- A sparse attached_buffers map must clear unused diagnostics in every buffer.
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'other diagnostic' })
local client = {
  id = 314159,
  config = {},
  attached_buffers = { [diag_buf] = true, [other] = true },
  notify = function()
    return true
  end,
}
local client_namespace = vim.lsp.diagnostic.get_namespace(client.id)
for bufnr in pairs(client.attached_buffers) do
  vim.diagnostic.set(client_namespace, bufnr, {
    { lnum = 0, col = 0, code = 6133, message = 'unused value' },
    { lnum = 0, col = 0, code = 2304, message = 'missing name' },
  })
end
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
  return { client }
end
require('lpke.lsp.helpers.ts_diagnostics').toggle_unused(false)
vim.lsp.get_clients = get_clients
for bufnr in pairs(client.attached_buffers) do
  local diagnostics =
    vim.diagnostic.get(bufnr, { namespace = client_namespace })
  check(
    #diagnostics == 1 and diagnostics[1].code == 2304,
    'unused diagnostic filtering in buffer ' .. bufnr
  )
end

vim.deprecate = deprecate
check(
  #deprecations == 0,
  'deprecated calls: ' .. table.concat(deprecations, ', ')
)
print(('nvim_0_12_deprecations: %d checks passed'):format(checks))
vim.cmd('qa!')
