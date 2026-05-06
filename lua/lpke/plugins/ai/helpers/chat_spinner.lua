local M = {
  buffers = {}, -- Track spinner state per buffer
  spinner_symbols = {
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  },
  filetype = 'codecompanion',
}

local request_event =
  require('lpke.plugins.ai.helpers.codecompanion_request_event')

function M:is_chat_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local ok, filetype = pcall(function()
    return vim.bo[buf].filetype
  end)

  return ok and filetype == self.filetype
end

function M:get_buffer_state(buf)
  if not self.buffers[buf] then
    self.buffers[buf] = {
      processing = false,
      active_requests = {},
      spinner_index = 1,
      namespace_id = vim.api.nvim_create_namespace(
        'CodeCompanionSpinner_' .. buf
      ),
      timer = nil,
    }
  end
  return self.buffers[buf]
end

function M:update_spinner(buf)
  local state = self.buffers[buf]
  if not state then
    return
  end

  if not self:is_chat_buf(buf) then
    self:cleanup_buffer(buf)
    return
  end

  if not state.processing then
    self:stop_spinner(buf)
    return
  end

  state.spinner_index = (state.spinner_index % #self.spinner_symbols) + 1

  -- Wrap all buffer operations in pcall to handle race conditions
  local success, _err = pcall(function()
    -- Clear previous virtual text
    vim.api.nvim_buf_clear_namespace(buf, state.namespace_id, 0, -1)

    local last_line = vim.api.nvim_buf_line_count(buf) - 1
    vim.api.nvim_buf_set_extmark(buf, state.namespace_id, last_line, 0, {
      virt_lines = {
        {
          {
            self.spinner_symbols[state.spinner_index] .. ' Processing...',
            'Comment',
          },
        },
      },
      virt_lines_above = false,
    })
  end)

  -- If buffer operations fail, clean up
  if not success then
    self:cleanup_buffer(buf)
  end
end

function M:start_spinner(buf, request_key)
  if not self:is_chat_buf(buf) then
    return
  end

  local state = self:get_buffer_state(buf)
  state.active_requests[request_key or tostring(buf)] = true

  if state.processing and state.timer then
    return
  end

  state.processing = true
  state.spinner_index = 0

  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  state.timer = vim.loop.new_timer()
  state.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      self:update_spinner(buf)
    end)
  )
end

function M:stop_spinner(buf, request_key)
  local state = self.buffers[buf]
  if not state then
    return
  end

  if request_key then
    state.active_requests[request_key] = nil
  else
    state.active_requests = {}
  end

  if next(state.active_requests) then
    return
  end

  state.processing = false

  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, state.namespace_id, 0, -1)
  end
end

function M:cleanup_buffer(buf)
  local state = self.buffers[buf]
  if state then
    self:stop_spinner(buf)
    self.buffers[buf] = nil
  end
end

function M:setup_request_autocmds()
  local group =
    vim.api.nvim_create_augroup('CodeCompanionChatSpinnerRequests', {
      clear = true,
    })

  vim.api.nvim_create_autocmd('User', {
    pattern = {
      'CodeCompanionRequestStarted',
      'CodeCompanionRequestFinished',
      'CodeCompanionChatStopped',
      'CodeCompanionChatClosed',
    },
    group = group,
    callback = function(args)
      local buf = request_event.bufnr(args)
      if not buf or not self:is_chat_buf(buf) then
        return
      end

      if args.match == 'CodeCompanionRequestStarted' then
        if request_event.is_chat(args, buf) then
          self:start_spinner(buf, request_event.key(args, buf))
        end
      elseif args.match == 'CodeCompanionRequestFinished' then
        self:stop_spinner(buf, request_event.key(args, buf))
      else
        self:stop_spinner(buf)
      end
    end,
  })
end

function M:setup_buffer_autocmds(buf)
  local group = vim.api.nvim_create_augroup(
    'CodeCompanionChatSpinner_' .. buf,
    { clear = true }
  )

  -- Clean up when buffer is removed.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    buffer = buf,
    group = group,
    callback = function()
      self:cleanup_buffer(buf)
    end,
  })
end

function M:init()
  self:setup_request_autocmds()

  -- Set up autocmd to initialize spinner for codecompanion buffers
  local init_group = vim.api.nvim_create_augroup('CodeCompanionSpinnerInit', {
    clear = true,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = self.filetype,
    group = init_group,
    callback = function(args)
      self:setup_buffer_autocmds(args.buf)
    end,
  })

  -- Also set up for any existing codecompanion buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if self:is_chat_buf(buf) then
      self:setup_buffer_autocmds(buf)
    end
  end
end

return M
