-- nvim --headless -u NONE -l tests/codecompanion_titles.lua
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end

local api = vim.api
local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    (label or 'mismatch')
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end

-- Exercise the real HTTP client and Copilot parsers without network requests.
local token_state = { oauth_token = 'fixture', copilot_token = 'fixture' }
local token = require('codecompanion.adapters.http.copilot.token')
token.fetch = function()
  return token_state
end
token.init = function()
  return token_state.copilot_token ~= nil
end
require('codecompanion.adapters.http.copilot.get_models').choices = function()
  return {
    ['gpt-4.1'] = { endpoint = 'completions', opts = {} },
    ['gpt-5-mini'] = { endpoint = 'responses', opts = {} },
  }
end
local pending = {}
local cancelled = false
require('codecompanion.http').static.methods.post.default = function(opts)
  table.insert(pending, opts)
  return {
    shutdown = function()
      cancelled = true
    end,
  }
end

local dir = vim.fn.tempname()
local cc = require('codecompanion')
cc.setup({
  display = { chat = { start_in_insert_mode = false, show_settings = false } },
  interactions = {
    chat = { adapter = 'ollama', opts = { completion_provider = 'default' } },
  },
  extensions = {
    history = {
      enabled = true,
      opts = {
        dir_to_save = dir,
        expiration_days = 0,
        auto_save = true,
        auto_generate_title = true,
        title_generation_opts = {
          adapter = 'copilot',
          model = 'gpt-5-mini',
          refresh_every_n_prompts = 0,
        },
      },
    },
  },
})
local scope = require('lpke.plugins.ai.helpers.history_scope')
scope.setup()
require('lpke.plugins.ai.helpers.history_acp').setup()
local history = cc.extensions.history
local Storage = require('codecompanion._extensions.history.storage')
local storage = Storage.new({ dir_to_save = dir, expiration_days = 0 })
local counter = 0
local function chat()
  counter = counter + 1
  local instance = require('codecompanion.interactions.chat').new({
    adapter = 'ollama',
    save_id = 'title-fixture-' .. counter,
    buffer_context = {
      bufnr = api.nvim_get_current_buf(),
      filetype = 'lua',
      filename = 'test.lua',
      lines = {},
    },
  })
  instance.adapter = { name = 'codex', type = 'acp' }
  instance.acp_session_id = 'fixture-session-' .. counter
  instance:add_message({
    role = 'user',
    content = 'Private editor rules must not become the title',
  }, { visible = false, _meta = { tag = 'rules' } })
  instance:add_message({
    role = 'user',
    content = 'Explain Lua table iteration',
  })
  return instance
end
local function submit(instance)
  api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanionChatSubmitted',
    data = { bufnr = instance.bufnr },
  })
  vim.wait(50, function()
    return false
  end)
end
local function respond(status, body)
  local request = assert(table.remove(pending, 1), 'Missing title request')
  request.callback({ status = status, body = body })
  vim.wait(50, function()
    return false
  end)
  return request
end
local function title(instance, expected)
  eq(instance.opts.title, expected, 'Live title')
  eq(history.load_chat(instance.opts.save_id).title, expected, 'Saved title')
  eq(history.get_chats()[instance.opts.save_id].title, expected, 'Picker title')
end
local response = vim.json.encode({
  output = {
    { type = 'reasoning', summary = {} },
    {
      type = 'message',
      content = { { type = 'output_text', text = 'Lua Table Iteration' } },
    },
  },
})

local generated = chat()
submit(generated)
local request = assert(pending[1])
eq(
  request.url,
  'https://api.githubcopilot.com/responses',
  'Title model endpoint'
)
local body = table.concat(vim.fn.readfile(request.body), '\n')
assert(body:find('Explain Lua table iteration', 1, true))
assert(not body:find('Private editor rules', 1, true))
respond(200, response)
title(generated, 'Lua Table Iteration')
submit(generated)
eq(#pending, 0, 'Named chat generated another title')

local limited = chat()
submit(limited)
respond(429, 'quota exceeded')
title(limited, 'Explain Lua table iteration')

local empty = chat()
submit(empty)
respond(200, '{}')
title(empty, 'Explain Lua table iteration')

token_state = { oauth_token = 'fixture' }
local unauthorized = chat()
submit(unauthorized)
title(unauthorized, 'Explain Lua table iteration')
eq(#pending, 0, 'Unauthorized title request')
token_state = { oauth_token = 'fixture', copilot_token = 'fixture' }

local init = token.init
token.init = function()
  return false
end
local setup_failed = chat()
submit(setup_failed)
title(setup_failed, 'Explain Lua table iteration')
eq(#pending, 0, 'Failed adapter setup sent a request')
token.init = init

local disconnected = chat()
submit(disconnected)
table
  .remove(pending, 1)
  .on_error({ message = 'Offline', stderr = { code = 6 } })
vim.wait(50, function()
  return false
end)
title(disconnected, 'Explain Lua table iteration')

local timeout
local defer = vim.defer_fn
vim.defer_fn = function(callback, delay)
  if delay == 15000 then
    timeout = callback
    return
  end
  return defer(callback, delay)
end
local stalled = chat()
submit(stalled)
vim.defer_fn = defer
assert(timeout, 'Missing title request timeout')()
assert(cancelled, 'Timed-out title request was not cancelled')
title(stalled, 'Explain Lua table iteration')
respond(200, response)
title(stalled, 'Explain Lua table iteration')

-- The history picker's gr action writes storage and then fires TitleRenamed.
local renamed = chat()
submit(renamed)
assert(storage:rename_chat(renamed.opts.save_id, 'Manual title'))
api.nvim_exec_autocmds('User', {
  pattern = 'CodeCompanionHistoryTitleRenamed',
  data = { title = 'Manual title' },
})
title(renamed, 'Manual title')
respond(200, response)
title(renamed, 'Manual title')
eq(renamed.title, 'Manual title', 'Late title replaced manual rename')
renamed:set_title('ACP session title')
storage:save_chat(renamed)
title(renamed, 'Manual title')

-- External helpers can rename the saved chat while a request is pending.
local linked = chat()
submit(linked)
assert(storage:rename_chat(linked.opts.save_id, 'Mac workspace title'))
respond(429, 'quota exceeded')
title(linked, 'Mac workspace title')
local restored = { opts = {}, acp_session_id = linked.acp_session_id }
assert(scope.restore_saved_title(restored))
eq(restored.opts.title, 'Mac workspace title', 'Resume lost workspace title')

vim.fn.delete(dir, 'rf')
print(
  'PASS: generated titles, failure/timeout fallback, gr, external rename, and resume'
)
