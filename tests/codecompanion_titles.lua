-- nvim --headless -u NONE -l tests/codecompanion_titles.lua
-- Real chat submission, history storage, UI and title process wrapper; fake transport.
table.unpack = table.unpack or unpack
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, plugin in ipairs({
  'codecompanion.nvim',
  'codecompanion-history.nvim',
  'plenary.nvim',
  'nvim-treesitter',
  'telescope.nvim',
}) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
local api = vim.api
vim.o.columns, vim.o.lines = 160, 48
require('telescope').setup({ defaults = { initial_mode = 'normal' } })
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
local function flush()
  vim.wait(25, function()
    return false
  end)
end
local jobs = {}
local fail_spawn = false
local real_system = vim.system
vim.system = function(command, opts, callback)
  if fail_spawn then
    error('Fixture process startup failed')
  end
  local job = { command = command, opts = opts, callback = callback }
  for index, arg in ipairs(command) do
    if arg == '--output-last-message' then
      job.output = command[index + 1]
    end
  end
  assert(job.output, 'Unexpected process: ' .. vim.inspect(command))
  table.insert(jobs, job)
  return {
    kill = function()
      job.killed = true
    end,
  }
end
local function respond(job, text, code)
  if text and vim.fn.isdirectory(job.opts.cwd) == 1 then
    vim.fn.writefile(vim.split(text, '\n'), job.output)
  end
  job.callback({ code = code or 0, stdout = 'unrelated stdout', stderr = '' })
  flush()
  eq(vim.fn.isdirectory(job.opts.cwd), 0, 'Temporary Codex files leaked')
end

local dir = vim.env.LPKE_TITLE_TEST_HISTORY or vim.fn.tempname()
local auth_dir = vim.fn.tempname()
vim.fn.mkdir(auth_dir, 'p')
vim.fn.writefile({ '{}' }, auth_dir .. '/auth.json')
vim.env.CODEX_HOME = auth_dir
local cc = require('codecompanion')
cc.setup({
  display = { chat = { start_in_insert_mode = false, show_settings = false } },
  interactions = {
    chat = {
      adapter = 'ollama',
      opts = {
        completion_provider = 'default',
        prompt_decorator = function(prompt)
          return 'DECORATOR_CONTEXT_MUST_NOT_APPEAR\n' .. prompt
        end,
      },
    },
  },
  extensions = {
    history = {
      enabled = true,
      opts = {
        dir_to_save = dir,
        expiration_days = 0,
        auto_save = true,
        auto_generate_title = true,
        picker = 'telescope',
        picker_keymaps = { rename = { n = 'gr', i = '<M-r>' } },
        title_generation_opts = { refresh_every_n_prompts = 1 },
      },
    },
  },
})
local Chat = require('codecompanion.interactions.chat')
Chat._submit_http = function() end
Chat._submit_acp = function() end
local scope = require('lpke.plugins.ai.helpers.history_scope')
scope.setup()
require('lpke.plugins.ai.helpers.history_acp').setup()
local titles = require('lpke.plugins.ai.helpers.chat_titles')
local history = cc.extensions.history
local Storage = require('codecompanion._extensions.history.storage')
local store = Storage.new({ dir_to_save = dir, expiration_days = 0 })
local count = 0
local function new_chat(opts)
  count = count + 1
  opts = vim.tbl_extend('force', {
    adapter = 'ollama',
    save_id = 'title-' .. count,
    buffer_context = {
      bufnr = api.nvim_get_current_buf(),
      filetype = 'lua',
      filename = 'test.lua',
      lines = {},
    },
  }, opts or {})
  if opts.save_id == false then
    opts.save_id = nil
  end
  local chat = assert(Chat.new(opts))
  chat:add_message(
    { role = 'user', content = 'SECRET_RULES_FROM_AGENTS' },
    { visible = false, _meta = { tag = 'rules' } }
  )
  chat:add_message(
    { role = 'user', content = 'SECRET_SKILL_REFERENCE' },
    { context = { id = 'skill' } }
  )
  chat:add_message(
    { role = 'user', content = 'SECRET_FILE_REFERENCE' },
    { reference = true }
  )
  flush()
  return chat
end
local function submit(chat, prompt)
  chat:reset()
  api.nvim_set_current_buf(chat.bufnr)
  api.nvim_buf_set_lines(chat.bufnr, -1, -1, false, vim.split(prompt, '\n'))
  chat:submit()
  flush()
end
local function saved(chat)
  return assert(history.load_chat(chat.opts.save_id))
end
local function assert_title(chat, title)
  eq(chat.opts.title, title, 'Live opts title')
  eq(chat.title, title, 'Chat title')
  eq(chat.ui.title, title, 'UI title')
  assert(
    vim.endswith(api.nvim_buf_get_name(chat.bufnr), title),
    'Buffer name not updated'
  )
  eq(
    require('codecompanion.interactions.shared.registry').get(chat.bufnr).description,
    title,
    'Chat picker title'
  )
  eq(saved(chat).title, title, 'Saved title')
  eq(
    history.get_chats()[chat.opts.save_id].title,
    title,
    'History picker title'
  )
end
local function event(chat, name)
  api.nvim_exec_autocmds(
    'User',
    { pattern = name, data = { bufnr = chat.bufnr, interaction = 'chat' } }
  )
  flush()
end

local function open_picker(chat)
  history.browse_chats(function(data)
    return data.save_id == chat.opts.save_id
  end)
  flush()
  local picker = require('telescope.actions.state').get_current_picker(
    api.nvim_get_current_buf()
  )
  assert(
    vim.wait(1000, function()
      return picker.manager and picker.manager:num_results() == 1
    end),
    'History picker did not populate'
  )
  return picker
end
local function picker_title(picker, expected)
  assert(
    vim.wait(1000, function()
      return picker.manager
        and picker.manager:num_results() == 1
        and picker.manager:get_entry(1).value.title == expected
    end),
    'Open history picker did not update to ' .. expected
  )
end

if vim.env.LPKE_TITLE_TEST_RELOAD then
  local reloaded = new_chat({ save_id = vim.env.LPKE_TITLE_TEST_RELOAD })
  assert(titles.restore(reloaded))
  eq(reloaded.opts.lpke_title.status, 'done')
  event(reloaded, 'CodeCompanionChatSubmitted')
  eq(#jobs, 0, 'Fresh Neovim restarted title generation')
  vim.fn.delete(auth_dir, 'rf')
  print('PASS: fresh Neovim restored an interrupted title without a request')
  return
end

local prompt = 'Explain Lua iteration with café and Unicode.\n'
  .. vim.trim(string.rep('Only my typed prompt. ', 90))
local chat = new_chat()
submit(chat, prompt)
eq(#jobs, 1)
eq(jobs[1].opts.stdin, prompt, 'Title input includes context or was truncated')
local command = table.concat(jobs[1].command, '\n')
assert(command:find('gpt-5.6-luna', 1, true))
assert(command:find('model_reasoning_effort="low"', 1, true))
assert(command:find('--ephemeral', 1, true))
assert(command:find('skills.include_instructions=false', 1, true))
assert(jobs[1].opts.cwd ~= vim.fn.getcwd())
assert(jobs[1].opts.env.CODEX_HOME ~= (vim.env.HOME .. '/.codex'))
eq(vim.uv.fs_lstat(jobs[1].opts.env.CODEX_HOME .. '/auth.json').type, 'link')
eq(jobs[1].opts.timeout, 30000)
eq(saved(chat).lpke_title.status, 'pending')
local default_title = chat.title
assert_title(chat, default_title)
-- Even repeated submissions/events while pending cannot start another process.
event(chat, 'CodeCompanionChatSubmitted')
event(chat, 'CodeCompanionRequestFinished')
eq(#jobs, 1)
local picker = open_picker(chat)
picker_title(picker, default_title)
chat:add_message({
  role = 'llm',
  content = 'Response arrived while generating the title',
})
store:save_chat(chat)
local saved_messages = saved(chat).messages
respond(jobs[1], 'Lua Unicode Iteration')
assert_title(chat, 'Lua Unicode Iteration')
eq(saved(chat).messages, saved_messages, 'Title replaced newer saved messages')
picker_title(picker, 'Lua Unicode Iteration')
require('telescope.actions').close(picker.prompt_bufnr)
flush()
eq(saved(chat).lpke_title, { status = 'done', source = 'generated' })
chat:ready_for_input()
submit(chat, 'A completely different second topic')
eq(#jobs, 1, 'Second user prompt triggered title generation')
assert_title(chat, 'Lua Unicode Iteration')

-- ACP autosave, session resume and session title updates preserve final titles.
chat.adapter = { name = 'codex', type = 'acp' }
chat.acp_session_id = 'acp-title-fixture'
store:save_chat(chat)
chat:set_title('Unwanted ACP session title')
event(chat, 'CodeCompanionRequestFinished')
assert_title(chat, 'Lua Unicode Iteration')
local resumed = new_chat({ save_id = 'new-resume-buffer' })
resumed.acp_session_id = chat.acp_session_id
assert(titles.restore(resumed))
eq(resumed.opts.save_id, chat.opts.save_id)
eq(resumed.title, chat.title)
event(resumed, 'CodeCompanionChatSubmitted')
eq(#jobs, 1, 'Resumed session regenerated its title')

-- The actual gr rename handler must update immediately and stay permanent.
local renamed = new_chat()
submit(renamed, 'Help me with the renamed fixture')
local rename_job = jobs[#jobs]
local fallback_name = renamed.title
assert(store:rename_chat(renamed.opts.save_id, fallback_name))
assert(rename_job.killed, 'Rename did not cancel pending generation')
eq(saved(renamed).lpke_title.source, 'manual')
assert(store:save_summary({
  summary_id = 'title-summary',
  chat_id = renamed.opts.save_id,
  chat_title = fallback_name,
  content = 'Summary fixture',
  generated_at = os.time(),
}))
picker = open_picker(renamed)
local input = vim.ui.input
vim.ui.input = function(_, callback)
  callback('  Manual Permanent Title  ')
end
local rename_map = vim.fn.maparg('gr', 'n', false, true)
assert(type(rename_map.callback) == 'function', 'Missing gr rename map')
rename_map.callback()
vim.ui.input = input
flush()
assert_title(renamed, 'Manual Permanent Title')
eq(
  store:get_summaries()['title-summary'].chat_title,
  'Manual Permanent Title',
  'Summary kept stale title'
)
picker_title(picker, 'Manual Permanent Title')
eq(api.nvim_get_current_buf(), picker.prompt_bufnr, 'Rename reopened picker')
respond(rename_job, 'Late Generated Title')
assert_title(renamed, 'Manual Permanent Title')
require('telescope.actions').close(picker.prompt_bufnr)
flush()
event(renamed, 'CodeCompanionChatSubmitted')
eq(jobs[#jobs], rename_job)
-- A queued upstream UI write cannot replace the manual title either.
local ui = require('codecompanion._extensions.history.ui').new(
  { default_buf_title = '[CodeCompanion] ' },
  store,
  {}
)
ui:_set_buf_title(renamed.bufnr, 'Deciding title...')
ui:_set_buf_title(renamed.bufnr, 'Manual Permanent Title with stale suffix')
flush()
assert_title(renamed, 'Manual Permanent Title')
ui:update_chat_title(renamed, '(📝)')
flush()
assert(
  vim.endswith(
    api.nvim_buf_get_name(renamed.bufnr),
    'Manual Permanent Title (📝)'
  ),
  'Summary indicator disappeared'
)
ui:update_chat_title(renamed)
flush()
assert_title(renamed, 'Manual Permanent Title')

-- A different process/helper may edit saved history directly.
local external = new_chat()
submit(external, 'Workspace connection fixture')
local external_job = jobs[#jobs]
local data = saved(external)
data.title = 'Mac Workspace Title'
assert(
  require('codecompanion._extensions.history.utils').write_json(
    store.chats_dir .. '/' .. data.save_id .. '.json',
    data
  ).ok
)
respond(external_job, 'Late workspace title')
store:save_chat(external)
assert_title(external, 'Mac Workspace Title')

-- Process failures, bad responses, and timeout all settle once to the fallback.
for _, result in ipairs({
  { nil, 1 },
  { '', 0 },
  { 'two\nlines', 0 },
  { string.rep('x', 121), 0 },
  { nil, 124 },
}) do
  local failed = new_chat()
  submit(failed, 'Fallback fixture ' .. count)
  local job = jobs[#jobs]
  local title = failed.title
  respond(job, result[1], result[2])
  assert_title(failed, title)
  eq(saved(failed).lpke_title.source, 'fallback')
  local before = #jobs
  event(failed, 'CodeCompanionChatSubmitted')
  eq(#jobs, before, 'Failed title request retried')
end
fail_spawn = true
local failed = new_chat()
submit(failed, 'Spawn failure fixture')
assert_title(failed, 'Spawn failure fixture')
eq(saved(failed).lpke_title.source, 'fallback')
fail_spawn = false

-- Closing a buffer preserves the asynchronous result, deleting history does not.
local closed = new_chat()
submit(closed, 'Closed buffer fixture')
local closed_id, closed_job = closed.opts.save_id, jobs[#jobs]
closed:close()
respond(closed_job, 'Closed Buffer Title')
eq(history.load_chat(closed_id).title, 'Closed Buffer Title')
local deleted = new_chat()
submit(deleted, 'Deleted history fixture')
local deleted_id, deleted_job = deleted.opts.save_id, jobs[#jobs]
assert(store:delete_chat(deleted_id))
respond(deleted_job, 'Must Not Reappear')
assert(not history.load_chat(deleted_id))

-- Simulate restart from a saved pending attempt. There is no active request ID.
local interrupted = new_chat()
interrupted.opts.title = 'Interrupted Fallback'
interrupted.opts.lpke_title = { status = 'pending', id = 'previous-process' }
store:save_chat(interrupted)
local reload = real_system({
  vim.v.progpath,
  '--headless',
  '-u',
  'NONE',
  '-l',
  'tests/codecompanion_titles.lua',
}, {
  text = true,
  env = {
    LPKE_TITLE_TEST_HISTORY = dir,
    LPKE_TITLE_TEST_RELOAD = interrupted.opts.save_id,
  },
}):wait()
eq(reload.code, 0, reload.stderr)
interrupted.opts.title, interrupted.opts.lpke_title = nil, nil
interrupted._lpke_history_title_locked = nil
local before = #jobs
assert(titles.restore(interrupted))
eq(interrupted.opts.lpke_title.status, 'done')
event(interrupted, 'CodeCompanionChatSubmitted')
eq(#jobs, before, 'Restart retried a pending attempt')
assert_title(interrupted, 'Interrupted Fallback')

-- No context-only/empty chat should start generation.
local blank = new_chat()
event(blank, 'CodeCompanionChatSubmitted')
eq(#jobs, before)

-- Preloaded or decorated historical prompts are never sent to the title model.
blank:add_message({
  role = 'user',
  content = 'Existing prompt with expanded context',
})
event(blank, 'CodeCompanionChatSubmitted')
eq(#jobs, before, 'Used historical content instead of a captured draft')

-- A fallback or manual title can legitimately match an upstream placeholder.
local reserved = new_chat()
submit(reserved, 'CodeCompanion')
respond(jobs[#jobs], nil, 1)
before = #jobs
event(reserved, 'CodeCompanionChatSubmitted')
eq(#jobs, before, 'Fallback matching a placeholder retried')
assert(store:rename_chat(reserved.opts.save_id, 'Refreshing title...'))
event(reserved, 'CodeCompanionChatSubmitted')
eq(#jobs, before, 'Manual title matching a placeholder retried')
assert_title(reserved, 'Refreshing title...')

-- New chats created in the same second must not inherit each other's titles.
local time, now = os.time, os.time()
os.time = function()
  return now
end
local first = new_chat({ save_id = false })
local second = new_chat({ save_id = false })
os.time = time
assert(
  first.opts.save_id ~= second.opts.save_id,
  'New chats share a history ID'
)
before = #jobs
submit(first, 'First concurrent prompt')
submit(second, 'Second concurrent prompt')
eq(#jobs, before + 2)
respond(jobs[before + 2], 'Second Concurrent Title')
respond(jobs[before + 1], 'First Concurrent Title')
assert_title(first, 'First Concurrent Title')
assert_title(second, 'Second Concurrent Title')

vim.fn.delete(dir, 'rf')
vim.fn.delete(auth_dir, 'rf')
print(
  'PASS: exact typed prompt, one attempt, immediate UI/storage, ACP resume, renames, failures, close/delete, and restart'
)
