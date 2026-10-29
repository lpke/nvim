-- run-nvim --headless -u NONE -l tests/codecompanion_context.lua
local h = dofile('tests/helpers/codecompanion_common.lua')
local api = vim.api
local chat = h.chat()
local source = api.nvim_create_buf(true, false)
local base = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local project, external = base .. '/project', base .. '/external'
vim.fn.mkdir(project, 'p')
vim.fn.mkdir(external, 'p')
vim.cmd.cd(vim.fn.fnameescape(project))
h.write(project .. '/file with spaces.lua', { 'local original = true' })
api.nvim_buf_set_name(source, project .. '/file with spaces.lua')
api.nvim_buf_set_lines(source, 0, -1, false, { 'local original = true' })
vim.bo[source].filetype = 'lua'
chat.buffer_context.bufnr = source

-- Invoke native context renderers through the configured safe wrapper.
local buffer = require('lpke.plugins.ai.helpers.editor_context.buffer')
local context = buffer.new({ Chat = chat, params = 'diff' })
context:chat_render({ bufnr = source })
h.check(
  chat.messages[#chat.messages].content:find('local original = true', 1, true),
  'buffer contents reach model'
)
h.equal(
  chat.context_items[#chat.context_items].source,
  'lpke.plugins.ai.helpers.editor_context.buffer',
  'stored context uses safe wrapper'
)
h.equal(
  chat.context_items[#chat.context_items].opts.sync_diff,
  true,
  'default diff context'
)
h.check(
  buffer.replace('#', '#{buffer}', source):find('file with spaces.lua', 1, true),
  'buffer readable label'
)
local target =
  buffer.new({ Chat = chat, target = project .. '/file with spaces.lua' })
target:chat_render()
h.check(
  chat.messages[#chat.messages].content:find('original', 1, true),
  'explicit context target'
)
local ns = api.nvim_create_namespace('migration-diagnostics')
vim.diagnostic.set(ns, source, {
  {
    lnum = 0,
    end_lnum = 0,
    col = 0,
    end_col = 5,
    severity = vim.diagnostic.severity.WARN,
    message = 'Fixture diagnostic',
  },
})
local diagnostics = require(
  'lpke.plugins.ai.helpers.editor_context.diagnostics'
).new({ Chat = chat })
diagnostics:chat_render()
h.check(
  chat.messages[#chat.messages].content:find('Fixture diagnostic', 1, true),
  'diagnostics reach model'
)
api.nvim_buf_delete(source, { force = true })
_G.codecompanion_current_context = source
local before = #h.notices
context:chat_render()
context:chat_render()
h.equal(#h.notices, before + 1, 'closed buffer warning once')
h.check(
  chat.messages[#chat.messages].opts.visible == false,
  'closed-buffer explanation stays hidden'
)
h.equal(context:cli_render(), nil, 'closed buffer CLI skip')
diagnostics:chat_render()
diagnostics:chat_render()
h.equal(#h.notices, before + 2, 'closed diagnostics warning once')
h.equal(diagnostics:cli_render(), nil, 'closed diagnostics CLI skip')
_G.codecompanion_current_context = nil

-- /fetch is shared URL context: an HTTP reader feeds a still-ACP chat.
local config = require('codecompanion.config')
local fetch_config = config.interactions.chat.slash_commands.fetch
fetch_config.opts.cache_path = base .. '/fetch-cache'
h.equal(fetch_config.opts.adapter, 'jina', 'shared fetch preserves Jina reader')
local http = require('codecompanion.http')
local original_http, original_input, original_select =
  http.new, vim.ui.input, vim.ui.select
local url, content =
  'https://example.invalid/shared-acp-context', 'Offline fetched page contents'
local requests, reader, request_url = 0
http.new = function(opts)
  reader = opts.adapter
  return {
    request = function(_, payload, actions)
      requests = requests + 1
      request_url = payload.url
      actions.callback(
        nil,
        { body = vim.json.encode({ code = 200, data = { text = content } }) }
      )
    end,
  }
end
vim.ui.input = function(_, callback)
  callback(url)
end
vim.ui.select = function(_, opts, callback)
  callback(opts.prompt == 'Select link source' and 'URL' or 'No')
end
local dispatcher = require('codecompanion.interactions.chat.slash_commands')
local connection = chat.acp_connection
local messages_before = #chat.messages
dispatcher.run(
  { label = 'fetch', config = fetch_config, context = { bufnr = chat.bufnr } },
  chat
)
h.equal(requests, 1, 'fetch dispatcher makes one reader request')
h.equal(reader.name, 'jina', 'actual request uses Jina without MarkItDown')
h.equal(reader.url, 'https://r.jina.ai', 'native Jina reader setup executes')
h.equal(
  reader.handlers.set_body(),
  { url = url },
  'native reader retains exact requested URL'
)
h.equal(request_url, url, 'fetch forwards exact URL to transport')
h.equal(
  #chat.messages,
  messages_before + 1,
  'fetched output attached exactly once'
)
local fetched = chat.messages[#chat.messages]
local attachment = '<attachment url="'
  .. url
  .. '">'
  .. content
  .. '</attachment>'
h.equal(
  fetched.content,
  attachment,
  'native fetch formats complete URL content'
)
h.equal(fetched.opts.visible, false, 'fetched contents stay hidden in chat')
h.equal(
  chat.context_items[#chat.context_items].id,
  '<url>' .. url .. '</url>',
  'native fetch adds URL context marker'
)
h.equal(chat.adapter.type, 'acp', 'fetch leaves chat on ACP adapter')
h.equal(chat.acp_connection, connection, 'fetch preserves live ACP connection')
local wire = require('codecompanion.adapters').call_handler(
  chat.adapter,
  'build_messages',
  {
    messages = chat.messages,
    capabilities = { promptCapabilities = {} },
  }
)
h.check(
  vim.iter(wire):any(function(item)
    return item.type == 'text' and item.text == attachment
  end),
  'fetched hidden context reaches native ACP request formatter'
)
vim.ui.input = function(_, callback)
  callback(nil)
end
dispatcher.run(
  { label = 'fetch', config = fetch_config, context = { bufnr = chat.bufnr } },
  chat
)
h.equal(requests, 1, 'cancelled fetch makes no reader request')
h.equal(
  #chat.messages,
  messages_before + 1,
  'cancelled fetch preserves context'
)
http.new, vim.ui.input, vim.ui.select =
  original_http, original_input, original_select

-- Drive the real slash callbacks with a selectable Telescope boundary.
local picker, selection, select_action, maps, close_hooks
local close = setmetatable({
  enhance = function(_, opts)
    close_hooks[#close_hooks + 1] = opts.post
  end,
}, {
  __call = function()
    for _, fn in ipairs(close_hooks) do
      fn()
    end
  end,
})
package.loaded['telescope.actions'] = {
  close = close,
  select_default = {
    replace = function(_, callback)
      select_action = callback
    end,
  },
}
package.loaded['telescope.actions.state'] = {
  get_selected_entry = function()
    return selection
  end,
  get_current_picker = function()
    return {
      _get_prompt = function()
        return 'kept query'
      end,
    }
  end,
}
package.loaded['telescope.finders'] = {
  new_table = function(opts)
    return opts
  end,
  new_oneshot_job = function(argv, opts)
    return { argv = argv, opts = opts }
  end,
}
package.loaded['telescope.previewers'] = {
  vim_buffer_cat = {
    new = function()
      return false
    end,
  },
  new_buffer_previewer = function(opts)
    return opts
  end,
}
package.loaded['telescope.pickers'] = {
  new = function(_, opts)
    picker, maps, close_hooks = opts, {}, {}
    return {
      find = function()
        opts.attach_mappings(999, function(mode, lhs, fn)
          maps[mode .. lhs] = fn
        end)
      end,
    }
  end,
}
local inputs, choices = {}, {}
vim.ui.input = function(_, callback)
  callback(table.remove(inputs, 1))
end
vim.ui.select = function(_, _, callback)
  callback(table.remove(choices, 1))
end
h.run({ 'git', 'init', '-q' }, project)
h.run({ 'git', 'add', '.' }, project)
h.run({
  'git',
  '-c',
  'user.name=Fixture',
  '-c',
  'user.email=fixture@example.test',
  'commit',
  '-qm',
  'first fixture',
}, project)
h.write(project .. '/file with spaces.lua', { 'local changed = true' })
h.run({ 'git', 'add', '.' }, project)
h.run({
  'git',
  '-c',
  'user.name=Fixture',
  '-c',
  'user.email=fixture@example.test',
  'commit',
  '-qm',
  'second fixture',
}, project)
local function last()
  return chat.messages[#chat.messages]
end
local function last_item()
  return chat.context_items[#chat.context_items]
end
h.slash.git_files_list.callback(chat)
h.equal(last_item().id, '<git-files-list files="1" />', 'tracked files tag')
h.equal(last_item().source, 'git', 'tracked files context source')
h.equal(last().content, 'file with spaces.lua\n', 'tracked paths only')
inputs = { '(2)' }
h.slash.git_commit_logs.callback(chat)
h.equal(last_item().id, '<git-commit-logs commits="2" />', 'log context tag')
h.check(last().content:find('second fixture', 1, true), 'commit log metadata')
inputs = { '2' }
h.slash.git_commit_history.callback(chat)
h.equal(
  last_item().id,
  '<git-commit-history versions="2" />',
  'commit history tag'
)
h.check(
  last().content:find('initial commit or no parent diff available', 1, true),
  'initial commit fallback'
)
h.slash.git_file_history.callback(chat)
selection, inputs = { value = 'file with spaces.lua' }, { '2' }
select_action()
h.equal(
  last_item().id,
  '<git-file-history versions="2">file with spaces.lua</git-file-history>',
  'file history tag'
)
h.check(
  last().content:find('-local original = true', 1, true),
  'path-specific diff'
)
h.write(external .. '/outside.txt', { 'external fixture' })
choices, inputs = { 'Absolute path input' }, { external }
h.slash.external_files.callback(chat)
h.equal(
  last_item().id,
  '<external-files>' .. external .. '</external-files>',
  'external context tag'
)
h.check(
  last().content:find('outside.txt', 1, true),
  'external directory file list'
)
local count = #chat.messages
inputs = {}
h.slash.git_commit_logs.callback(chat)
h.equal(#chat.messages, count, 'cancelled slash leaves context intact')
h.equal(#h.slash.image.opts.dirs, 4, 'all image search roots preserved')
api.nvim_set_current_buf(chat.bufnr)
api.nvim_buf_set_lines(
  chat.bufnr,
  chat.header_line,
  -1,
  false,
  { '', 'before after' }
)
api.nvim_win_set_cursor(0, { chat.header_line + 2, 7 })
h.slash.path.callback(chat)
h.check(
  picker.prompt_title:find('Directory', 1, true),
  'path starts in directory mode'
)
maps['n<A-s>']()
h.check(picker.prompt_title:find('File', 1, true), 'path kind toggle')
h.equal(picker.default_text, 'kept query', 'path kind retains query')
h.equal(picker.initial_mode, 'normal', 'path kind retains mode')
maps['i<A-r>']()
h.check(
  picker.prompt_title:find('Filesystem', 1, true),
  'path filesystem toggle'
)
h.equal(picker.finder.argv[1], 'fd', 'native path finder')
selection = { value = external .. '/a`b.txt' }
select_action()
h.check(
  api
    .nvim_get_current_line()
    :find('before `' .. external .. '/a\\`b.txt`after', 1, true),
  'escaped path inserts at saved cursor'
)
vim.cmd.stopinsert()

-- Execute patched completion; it must only remove the slash token.
require('lpke.plugins.ai.helpers.slash_command_completion').patch_cmp()
api.nvim_buf_set_lines(
  chat.bufnr,
  chat.header_line,
  -1,
  false,
  { '', 'keep /git_files_list suffix' }
)
api.nvim_win_set_cursor(0, { chat.header_line + 2, 20 })
local callback_count = 0
require('codecompanion.providers.completion.cmp.slash_commands')
  .new({})
  :execute({
    label = 'git_files_list',
    config = h.slash.git_files_list,
    context = { bufnr = chat.bufnr },
  }, function()
    callback_count = callback_count + 1
  end)
h.equal(
  api.nvim_buf_get_lines(
    chat.bufnr,
    chat.header_line + 1,
    chat.header_line + 2,
    false
  )[1],
  'keep  suffix',
  'slash token removal preserves draft'
)
h.equal(callback_count, 1, 'slash completion callback once')
h.equal(vim.bo[chat.bufnr].buflisted, false, 'completed chat stays unlisted')

vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(base, 'rf')
h.done('common context/slash callbacks')
