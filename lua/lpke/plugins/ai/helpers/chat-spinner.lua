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

function M:get_buffer_state(buf)
  if not self.buffers[buf] then
    self.buffers[buf] = {
      processing = false,
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
  local state = self:get_buffer_state(buf)

  if not state.processing then
    self:stop_spinner(buf)
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    self:cleanup_buffer(buf)
    return
  end

  state.spinner_index = (state.spinner_index % #self.spinner_symbols) + 1

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
    virt_lines_above = true,
  })
end

function M:start_spinner(buf)
  local state = self:get_buffer_state(buf)
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

function M:stop_spinner(buf)
  local state = self.buffers[buf]
  if not state then
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

function M:setup_buffer_autocmds(buf)
  local group = vim.api.nvim_create_augroup(
    'CodeCompanionChatSpinner_' .. buf,
    { clear = true }
  )

  vim.api.nvim_create_autocmd({ 'User' }, {
    pattern = 'CodeCompanionRequest*',
    group = group,
    callback = function(request)
      -- Only handle events for the current buffer
      local current_buf_valid, current_buf = pcall(vim.api.nvim_get_current_buf)
      local buf_filetype_valid, buf_filetype = pcall(function()
        return vim.bo[buf] and vim.bo[buf].filetype
      end)

      if
        (current_buf_valid and current_buf == buf)
        or (buf_filetype_valid and buf_filetype == self.filetype)
      then
        if request.match == 'CodeCompanionRequestStarted' then
          self:start_spinner(buf)
        elseif request.match == 'CodeCompanionRequestFinished' then
          self:stop_spinner(buf)
        end
      end
    end,
  })

  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    buffer = buf,
    group = group,
    callback = function()
      self:cleanup_buffer(buf)
    end,
  })
end

function M:init()
  -- Set up autocmd to initialize spinner for codecompanion buffers
  vim.api.nvim_create_augroup('CodeCompanionSpinnerInit', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = self.filetype,
    group = vim.api.nvim_create_augroup('CodeCompanionSpinnerInit', {}),
    callback = function(args)
      self:setup_buffer_autocmds(args.buf)
    end,
  })

  -- Also set up for any existing codecompanion buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == self.filetype
    then
      self:setup_buffer_autocmds(buf)
    end
  end
end

return M
