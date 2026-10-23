local M = {}
local api = vim.api
local draft = require('lpke.plugins.ai.helpers.chat_draft')
local notify = require('lpke.plugins.ai.helpers.chat_notify')
local jobs, attached = {}, setmetatable({}, { __mode = 'k' })
local next_id = 0
local units = { s = 1000, m = 60000, h = 3600000, d = 86400000 }

local function duration(text)
  local total, consumed = 0, ''
  for amount, unit in text:gmatch('(%d+)([smhd])') do
    total = total + tonumber(amount) * units[unit]
    consumed = consumed .. amount .. unit
  end
  if consumed ~= text or total < 1 or total > 2147483647 then
    error(
      'Use a positive duration such as 30s, 1m, 2h or 1h30m (under 25 days)',
      0
    )
  end
  return total
end

local function cancel(job, reason)
  if jobs[job.chat.bufnr] ~= job then
    return
  end
  jobs[job.chat.bufnr] = nil
  if job.timer and not job.timer:is_closing() then
    job.timer:stop()
    job.timer:close()
  end
  notify(
    ('SendIn #%d [chat %d] cancelled: %s'):format(
      job.id,
      job.chat.bufnr,
      reason
    )
  )
end

local function cancel_chat(chat, reason)
  local job = jobs[chat.bufnr]
  if job then
    cancel(job, reason)
  end
end

local function attach(chat)
  if attached[chat] then
    return
  end
  local state = { submissions = 0 }
  attached[chat] = state
  for _, event in ipairs({ 'on_submitted', 'on_cancelled', 'on_closed' }) do
    chat:add_callback(event, function()
      if event == 'on_submitted' then
        state.submissions = state.submissions + 1
      end
      cancel_chat(chat, event:sub(4))
    end)
  end
  api.nvim_buf_attach(chat.bufnr, false, {
    on_lines = function()
      local job = jobs[chat.bufnr]
      if job then
        -- Leave the textlock before notifying or releasing the timer.
        vim.schedule(function()
          cancel(job, 'buffer edited')
        end)
      end
    end,
    on_detach = function()
      vim.schedule(function()
        cancel_chat(chat, 'buffer unloaded')
      end)
    end,
  })
end

local function available(chat)
  return api.nvim_buf_is_loaded(chat.bufnr)
    and require('codecompanion').buf_get_chat(chat.bufnr) == chat
    and not chat.current_request
    and (not chat.status or chat.status == '')
    and vim.bo[chat.bufnr].modifiable
    and chat._last_role == require('codecompanion.config').constants.USER_ROLE
end

local function schedule(chat, text)
  local delay = duration(text)
  if not available(chat) or not draft.has_prompt(chat) then
    error('SendIn needs an idle chat with a non-empty prompt', 0)
  end
  attach(chat)
  cancel_chat(chat, 'replaced')
  next_id = next_id + 1
  local job = {
    id = next_id,
    chat = chat,
    cycle = chat.cycle,
    adapter = chat.adapter,
    session = chat.acp_connection and chat.acp_connection.session_id,
    draft = draft.read(chat),
    tick = api.nvim_buf_get_changedtick(chat.bufnr),
    due = os.time() + math.ceil(delay / 1000),
  }
  jobs[chat.bufnr] = job
  job.timer = vim.defer_fn(function()
    if jobs[chat.bufnr] ~= job then
      return
    end
    if
      not available(chat)
      or chat.cycle ~= job.cycle
      or chat.adapter ~= job.adapter
      or (chat.acp_connection and chat.acp_connection.session_id) ~= job.session
      or api.nvim_buf_get_changedtick(chat.bufnr) ~= job.tick
      or draft.read(chat) ~= job.draft
      or not draft.has_prompt(chat)
    then
      return cancel(job, 'chat or draft changed')
    end
    -- Remove first so submission callbacks cannot cancel a send in progress.
    jobs[chat.bufnr] = nil
    local submissions = attached[chat].submissions
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    local restore_insert = api.nvim_get_current_buf() ~= chat.bufnr
      and (mode == 'i' or mode == 't')
    local ok, err = pcall(api.nvim_buf_call, chat.bufnr, function()
      chat:submit()
    end)
    if restore_insert then
      vim.cmd.startinsert()
    end
    if not ok then
      notify(
        ('SendIn #%d failed: %s'):format(job.id, tostring(err)),
        vim.log.levels.ERROR
      )
    elseif attached[chat].submissions > submissions then
      notify(
        ('SendIn #%d [chat %d] sent at %s'):format(
          job.id,
          chat.bufnr,
          os.date('%H:%M:%S')
        )
      )
    else
      notify(
        ('SendIn #%d was not submitted; draft retained'):format(job.id),
        vim.log.levels.WARN
      )
    end
  end, delay)
  notify(
    ('SendIn #%d [chat %d] queued for %s'):format(
      job.id,
      chat.bufnr,
      os.date('%Y-%m-%d %H:%M:%S', job.due)
    )
  )
end

local function list(chat, all)
  local rows = {}
  for _, job in pairs(jobs) do
    if all or job.chat == chat then
      rows[#rows + 1] = ('#%d [chat %d] %s (%s)'):format(
        job.id,
        job.chat.bufnr,
        os.date('%Y-%m-%d %H:%M:%S', job.due),
        job.chat.ui.title or 'Untitled'
      )
    end
  end
  table.sort(rows)
  notify(#rows > 0 and table.concat(rows, '\n') or 'No scheduled sends')
end

local function command(args)
  local chat = require('codecompanion').buf_get_chat(api.nvim_get_current_buf())
  if not chat then
    error('SendIn works only in CodeCompanion chat buffers', 0)
  end
  local action, scope = args.fargs[1], args.fargs[2]
  if #args.fargs == 1 and action ~= 'list' and action ~= 'cancel' then
    return schedule(chat, action)
  elseif
    action == 'list'
    and #args.fargs <= 2
    and (not scope or scope == 'all')
  then
    return list(chat, scope == 'all')
  elseif action == 'cancel' and #args.fargs <= 2 then
    if not scope then
      if not jobs[chat.bufnr] then
        return notify('No scheduled sends for this chat')
      end
      return cancel_chat(chat, 'requested')
    elseif scope == 'all' then
      local pending = vim.tbl_values(jobs)
      if #pending == 0 then
        return notify('No scheduled sends')
      end
      for _, job in ipairs(pending) do
        cancel(job, 'requested')
      end
      return
    elseif scope:match('^%d+$') then
      for _, job in pairs(jobs) do
        if job.id == tonumber(scope) then
          return cancel(job, 'requested')
        end
      end
      error('No scheduled send #' .. scope, 0)
    end
  end
  error('Use SendIn <time>, list [all], or cancel [id|all]', 0)
end

function M.setup()
  api.nvim_create_user_command('SendIn', function(args)
    local ok, err = pcall(command, args)
    if not ok then
      notify(tostring(err), vim.log.levels.ERROR)
    end
  end, {
    nargs = '+',
    desc = 'Schedule, list or cancel a CodeCompanion prompt',
    complete = function(lead, line)
      local choices = { '1m', '2h', 'list', 'cancel' }
      if line:match('^%s*SendIn%s+%S+%s') then
        choices = { 'all' }
        if line:match('^%s*SendIn%s+cancel%s') then
          for _, job in pairs(jobs) do
            choices[#choices + 1] = tostring(job.id)
          end
        end
      end
      return vim.tbl_filter(function(value)
        return value:sub(1, #lead) == lead
      end, choices)
    end,
  })
  api.nvim_create_autocmd('User', {
    group = api.nvim_create_augroup(
      'LpkeCodeCompanionSendIn',
      { clear = true }
    ),
    pattern = { 'CodeCompanionChatAdapter', 'CodeCompanionChatModel' },
    callback = function(args)
      local job = args.data and jobs[args.data.bufnr]
      if job then
        cancel(job, 'adapter or model changed')
      end
    end,
  })
end

return M
