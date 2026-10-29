-- nvim --headless -u NONE -i NONE -l tests/codecompanion_integrations.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
for _, name in ipairs({
  'codecompanion.nvim',
  'lualine.nvim',
  'img-clip.nvim',
  'plenary.nvim',
}) do
  vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
local api = vim.api
local checks = 0
local function check(value, label)
  checks = checks + 1
  assert(value, label)
end
local function equal(actual, expected, label)
  check(
    vim.deep_equal(actual, expected),
    label
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function flush()
  vim.wait(30, function()
    return false
  end, 5)
end
local function chat_buffer()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'codecompanion'
  return buf
end
local requests = require('lpke.plugins.ai.helpers.request_state')
local spinner = require('lpke.plugins.ai.helpers.chat_spinner')
spinner:init()
local changes = {}
requests.subscribe('integration_test', function(bufnr, busy)
  changes[#changes + 1] = { bufnr, busy }
end)
local lualine = require('lualine')
local original_refresh, refreshes = lualine.refresh, 0
lualine.refresh = function()
  refreshes = refreshes + 1
end
local Status = require('lpke.plugins.ai.helpers.lualine_spinner')
local status = Status({})
local first, second = chat_buffer(), chat_buffer()
local function fire(event, buf, id, interaction)
  api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanion' .. event,
    data = { bufnr = buf, id = id, interaction = interaction or 'chat' },
  })
end
fire('RequestStarted', first, 'one')
local timer = spinner.timer
fire('RequestStarted', first, 'one')
fire('RequestStarted', first, 'two')
fire('RequestStarted', second, 'three')
flush()
check(
  requests.busy(first) and requests.busy({ bufnr = second }),
  'concurrent chats busy'
)
equal(
  #changes,
  2,
  'duplicate and overlapping starts preserve one busy transition'
)
equal(refreshes, 2, 'only busy transitions refresh statusline')
check(
  spinner.timer == timer and timer:is_active(),
  'both chats share one animation timer'
)
check(status:update_status() ~= nil, 'status spinner reads shared busy state')
local namespace = api.nvim_get_namespaces().LpkeCodeCompanionSpinner
local marks =
  api.nvim_buf_get_extmarks(first, namespace, 0, -1, { details = true })
check(#marks == 1, 'one spinner virtual line')
check(
  marks[1][4].virt_lines[1][1][1]:find('Processing...', 1, true),
  'spinner text'
)
equal(marks[1][4].virt_lines[1][1][2], 'Comment', 'muted spinner')
fire('RequestStarted', first, 'inline', 'inline')
fire('RequestFinished', first, 'inline', 'inline')
fire('RequestFinished', first, 'summary', 'background')
fire('RequestFinished', first, 'stale')
fire('RequestFinished', first)
equal(
  #changes,
  2,
  'unrelated, stale and no-ID completions leave identified requests busy'
)
equal(refreshes, 2, 'irrelevant completions do not refresh statusline')
fire('RequestStarted', first)
fire('RequestStarted', first)
fire('RequestFinished', first, 'one')
check(requests.busy(first), 'first finish preserves overlapping requests')
fire('RequestFinished', first, 'two')
check(
  requests.busy(first),
  'no-ID request remains after identified requests finish'
)
fire('RequestFinished', first)
check(
  not requests.busy(first) and requests.busy(second),
  'no-ID finish clears only fallback'
)
check(spinner.buffers[first] == nil, 'idle renderer state removed')
equal(
  #api.nvim_buf_get_extmarks(first, namespace, 0, -1, {}),
  0,
  'idle spinner marks clear'
)
check(
  spinner.timer == timer and status:update_status() ~= nil,
  'other chat keeps animation active'
)
fire('ChatStopped', second)
check(
  not requests.busy() and status:update_status() == nil,
  'stop clears shared busy state'
)
check(
  spinner.timer == nil and timer:is_closing(),
  'last idle transition closes shared timer'
)
equal(refreshes, 4, 'last finishes refresh each affected chat once')
fire('RequestFinished', second, 'three')
equal(refreshes, 4, 'completion after stop does no work')

-- Old event aliases and events without interaction metadata still work.
for _, event in ipairs({ 'Started', 'Finished' }) do
  api.nvim_exec_autocmds('User', {
    pattern = 'CodeCompanionRequest' .. event,
    data = { chat_bufnr = tostring(first), request_id = 'alias' },
  })
  equal(
    requests.busy(first),
    event == 'Started',
    'buffer/request aliases with legacy chat inference'
  )
end
local plain = api.nvim_create_buf(false, true)
fire('RequestStarted', plain, 'non-chat')
fire('RequestStarted', -1, 'invalid')
check(not requests.busy(), 'invalid and non-chat buffers excluded')
api.nvim_buf_delete(plain, { force = true })

fire('RequestStarted', first, 'delete')
api.nvim_buf_delete(first, { force = true })
check(
  spinner.buffers[first] == nil and not requests.busy(),
  'deletion clears renderer and request IDs'
)
check(spinner.timer == nil, 'deletion leaves no timer')
fire('RequestStarted', second, 'close')
fire('ChatClosed', second)
check(
  not requests.busy() and spinner.timer == nil,
  'close clears all identified requests'
)
fire('RequestStarted', second)
fire('RequestFinished', second)
check(
  not requests.busy() and spinner.timer == nil,
  'standalone no-ID request starts and finishes'
)
fire('RequestStarted', second, 'filetype')
vim.bo[second].filetype = 'text'
check(
  vim.wait(500, function()
    return not requests.busy()
  end, 10),
  'changed filetype clears stale request'
)
check(spinner.timer == nil, 'changed filetype leaves no timer')
api.nvim_buf_delete(second, { force = true })
spinner:init()
Status({})
equal(
  #api.nvim_get_autocmds({ group = 'LpkeCodeCompanionRequests', event = 'User' }),
  4,
  'reinitialization keeps one event subscriber'
)
lualine.refresh = original_refresh

-- img-clip inserts literal absolute paths, with Neovim's byte-based cursor API.
require('img-clip').setup({
  filetypes = {
    codecompanion = {
      template = '`$FILE_PATH`',
      use_absolute_path = true,
      embed_image_as_base64 = false,
      insert_mode_after_paste = false,
    },
  },
})
local image = require('lpke.plugins.ai.helpers.img_clip')
image.setup_inline_paste()
local markup = require('img-clip.markup')
local buf = chat_buffer()
api.nvim_set_current_buf(buf)
for _, case in ipairs({
  { '', 0, '`/tmp/example.png`' },
  { 'abc', 0, 'a`/tmp/example.png`bc' },
  { 'abc', 2, 'abc`/tmp/example.png`' },
  { 'xé rest', 1, 'xé`/tmp/example.png` rest' },
}) do
  api.nvim_buf_set_lines(buf, 0, -1, false, { case[1] })
  api.nvim_win_set_cursor(0, { 1, case[2] })
  check(markup.insert_markup('/tmp/example.png', true), 'image path inserts')
  equal(api.nvim_get_current_line(), case[3], 'inline image placement')
end
local old_system, old_paste, old_notify =
  vim.system, require('img-clip').paste_image, vim.notify
local calls, notices = 0, {}
vim.fn.mkdir(image.dir_path(), 'p')
require('img-clip').paste_image = function()
  return true
end
vim.system = function(argv, opts, callback)
  calls = calls + 1
  equal(
    argv,
    { 'du', '-sb', image.dir_path() },
    'image size uses argv, never shell interpolation'
  )
  callback({
    code = 0,
    stdout = tostring(3 * 1024 * 1024 * 1024) .. '\t' .. image.dir_path(),
  })
  return {}
end
vim.notify = function(message, level)
  notices[#notices + 1] = { message, level }
end
image.paste_image()
image.paste_image()
flush()
equal(calls, 1, 'image directory checked once')
check(
  #notices == 1 and notices[1][1]:find('3.00 GB', 1, true),
  'large image directory warning'
)
vim.system, require('img-clip').paste_image, vim.notify =
  old_system, old_paste, old_notify

-- Notices temporarily remove the hit-enter wait and restore exact options.
local notify = require('lpke.plugins.ai.helpers.chat_notify')
local messagesopt = vim.o.messagesopt
vim.o.messagesopt = 'hit-enter,history:123'
vim.notify = function(message)
  equal(
    vim.o.messagesopt,
    'wait:0,history:123',
    'scheduled notice does not block input'
  )
  check(message == 'integration notice', 'exact notice')
end
notify('integration notice')
flush()
equal(vim.o.messagesopt, 'hit-enter,history:123', 'message options restored')
local schedule, notify_error = vim.schedule, nil
vim.schedule = function(callback)
  local ok, err = pcall(callback)
  notify_error = not ok and err or nil
end
vim.notify = function()
  error('fixture notify failure')
end
notify('failing notice')
check(
  notify_error and notify_error:find('fixture notify failure', 1, true),
  'notify failure remains visible'
)
equal(
  vim.o.messagesopt,
  'hit-enter,history:123',
  'message options restored after notify throws'
)
vim.schedule = schedule
vim.notify, vim.o.messagesopt = old_notify, messagesopt

-- The subagent transcript keeps every item type and execution setting readable.
local format = require('lpke.plugins.ai.helpers.codex_threads.format')
local transcript = table.concat(
  format.thread('local', {
    id = 'child',
    parentThreadId = 'parent',
    createdAt = 100,
    cliVersion = 'fixture-cli',
    source = {
      subAgent = {
        thread_spawn = {
          parent_thread_id = 'parent',
          depth = 2,
          agent_path = '/agents/reviewer',
        },
      },
    },
    turns = {
      {
        startedAt = 101,
        status = 'completed',
        items = {
          {
            type = 'userMessage',
            content = {
              { text = 'exact user prompt' },
              { type = 'localImage', path = '/tmp/image.png' },
            },
          },
          { type = 'hookPrompt', fragments = { 'hook text' } },
          {
            type = 'agentMessage',
            phase = 'final_answer',
            text = 'final agent answer',
          },
          {
            type = 'reasoning',
            summary = { { text = 'public reasoning' } },
            content = vim.NIL,
          },
          { type = 'plan', text = 'plan steps' },
          {
            type = 'commandExecution',
            status = 'completed',
            command = { 'echo', 'fixture' },
            cwd = '/tmp',
            exitCode = 0,
            durationMs = 1500,
            aggregatedOutput = 'command output',
          },
          {
            type = 'fileChange',
            status = 'completed',
            changes = { { path = '/tmp/test.lua', kind = 'update' } },
          },
          {
            type = 'mcpToolCall',
            server = 'fixture-server',
            tool = 'fixture-tool',
            arguments = { key = 'arg' },
            result = 'mcp-result',
          },
          {
            type = 'dynamicToolCall',
            tool = 'dynamic-fixture',
            contentItems = 'dynamic-result',
          },
          {
            type = 'collabAgentToolCall',
            tool = 'spawn',
            prompt = 'delegated prompt',
            receiverThreadIds = { 'child-two' },
          },
          {
            type = 'subAgentActivity',
            agentThreadId = 'child-two',
            kind = 'spawn',
            agentPath = '/agents/second',
          },
          { type = 'webSearch', query = 'web query' },
          { type = 'imageView', path = '/tmp/view.png' },
          {
            type = 'imageGeneration',
            status = 'completed',
            revisedPrompt = 'generated image',
          },
          { type = 'enteredReviewMode', review = 'review prompt' },
          { type = 'exitedReviewMode', review = 'review result' },
          { type = 'contextCompaction' },
          { type = 'futureItem', payload = 'unknown item remains visible' },
        },
      },
    },
  }, {
    model = 'test-model',
    reasoningEffort = 'high',
    serviceTier = 'fast',
    modelProvider = 'fixture-provider',
    approvalPolicy = 'on-request',
    activePermissionProfile = 'workspace',
    sandbox = 'workspace-write',
    multiAgentMode = true,
    cwd = '/tmp',
  }, nil, 'full delegated prompt'),
  '\n'
)
for _, value in ipairs({
  'exact user prompt',
  '/tmp/image.png',
  'hook text',
  'final agent answer',
  'public reasoning',
  'plan steps',
  'echo fixture',
  'exit: `0`',
  '1.5s',
  'command output',
  '/tmp/test.lua',
  'fixture-server',
  'mcp-result',
  'dynamic-fixture',
  'dynamic-result',
  'delegated prompt',
  'child-two',
  'web query',
  '/tmp/view.png',
  'generated image',
  'review prompt',
  'review result',
  'futureItem',
  'unknown item remains visible',
  'test-model',
  'high',
  'fast',
  'fixture-provider',
  'on-request',
  'workspace-write',
  'true',
  'fixture-cli',
  'full delegated prompt',
}) do
  check(
    transcript:find(value, 1, true),
    'subagent transcript retains ' .. value
  )
end
equal(
  format.subagent_messages({
    createdAt = 100,
    turns = {
      {
        startedAt = 99,
        items = { { type = 'agentMessage', text = 'inherited parent' } },
      },
      {
        startedAt = 100,
        items = { { type = 'agentMessage', text = 'own answer' } },
      },
    },
  }),
  { { text = 'own answer' } },
  'subagent output excludes inherited parent turns'
)
equal(
  format.delegated_prompt(
    { id = 'child', delegationPrompt = 'gAAAAAencrypted' },
    {
      turns = {
        {
          items = {
            {
              type = 'collabAgentToolCall',
              receiverThreadIds = { 'child' },
              prompt = 'parent delegation',
            },
          },
        },
      },
    }
  ),
  'parent delegation',
  'encrypted prompt falls back to actual parent delegation'
)

-- A real fixture process exercises the JSON-RPC transport and fragmented IO.
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. '/bin', 'p')
local program = [[#!/usr/bin/env python3
import json, sys
for line in sys.stdin:
    message = json.loads(line)
    if 'id' not in message:
        continue
    method = message['method']
    if method == 'timeout':
        continue
    if method == 'exit':
        sys.stderr.write('fixture failure\n'); sys.stderr.flush()
        sys.exit(7)
    if method == 'error':
        response = {'id': message['id'], 'error': {'message': 'fixture error'}}
    else:
        response = {'id': message['id'], 'result': {'method': method, 'params': message.get('params')}}
    encoded = json.dumps(response)
    sys.stdout.write(encoded[:7]); sys.stdout.flush()
    sys.stdout.write(encoded[7:] + '\n'); sys.stdout.flush()
]]
vim.fn.writefile(
  vim.split(program, '\n', { plain = true }),
  fixture .. '/bin/codex'
)
vim.fn.setfperm(fixture .. '/bin/codex', 'rwx------')
local original_path = vim.env.PATH
vim.env.PATH = fixture .. '/bin:' .. original_path
local transport = require('lpke.plugins.ai.helpers.codex_threads.client')
local client = transport.get('local')
check(client == transport.get('local'), 'client cached by host')
local replies = {}
client:request('thread/list', { limit = 500 }, function(result, err)
  replies.list = { result, err }
end)
client:request('thread/read', { threadId = 'fixture-id' }, function(result, err)
  replies.read = { result, err }
end)
check(
  vim.wait(3000, function()
    return replies.list and replies.read
  end, 10),
  'real transport replies'
)
equal(replies.list[1].params.limit, 500, 'list parameters survive wire')
equal(
  replies.read[1].params.threadId,
  'fixture-id',
  'thread identity survives wire'
)
check(
  client.ready and next(client.pending) == nil,
  'initialization and request queue complete'
)
local failure
client:request('error', {}, function(_, err)
  failure = err
end)
check(
  vim.wait(1000, function()
    return failure ~= nil
  end, 10),
  'error reply delivered'
)
equal(failure, 'fixture error', 'error text survives transport')
failure = nil
client:request('timeout', {}, function(_, err)
  failure = err
end, 20)
check(
  vim.wait(1000, function()
    return failure ~= nil
  end, 10),
  'timeout delivered'
)
check(
  failure:find('timed out on timeout', 1, true),
  'timeout names failed method'
)
failure = nil
client:request('exit', {}, function(_, err)
  failure = err
end)
check(
  vim.wait(2000, function()
    return failure ~= nil
  end, 10),
  'process death fails pending requests'
)
check(
  failure:find('exited with code 7', 1, true),
  'process exit status preserved'
)
local unknown
transport.get('unsupported'):start(function(ok, err)
  unknown = not ok and err
end)
check(
  unknown and unknown:find('Unknown Codex thread host', 1, true),
  'unknown host rejected'
)
transport.stop_all()
vim.env.PATH = original_path
vim.fn.delete(fixture, 'rf')
print(('PASS %d integration checks'):format(checks))
vim.cmd('qa!')
