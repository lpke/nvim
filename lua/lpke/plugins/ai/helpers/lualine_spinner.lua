local M = require('lualine.component'):extend()

M.processing = false
M.spinner_index = 1
M.active_requests = {}
M.active_chats = {}

local request_event =
  require('lpke.plugins.ai.helpers.codecompanion_request_event')

local spinner_symbols = {
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
}
local spinner_symbols_len = 10

local function refresh_lualine()
  local ok, lualine = pcall(require, 'lualine')
  if ok then
    pcall(lualine.refresh, { place = { 'statusline' } })
  end
end

function M:sync_processing()
  self.processing = next(self.active_chats) ~= nil
end

function M:clear_key(key)
  local bufnr = self.active_requests[key]
  if not bufnr then
    return
  end

  self.active_requests[key] = nil

  local count = (self.active_chats[bufnr] or 1) - 1
  if count > 0 then
    self.active_chats[bufnr] = count
  else
    self.active_chats[bufnr] = nil
  end
end

function M:clear_buf(bufnr)
  local keys = {}

  for key, request_buf in pairs(self.active_requests) do
    if request_buf == bufnr then
      table.insert(keys, key)
    end
  end

  for _, key in ipairs(keys) do
    self:clear_key(key)
  end
end

function M:start_request(args)
  local bufnr = request_event.bufnr(args)
  if not bufnr or not request_event.is_chat(args, bufnr) then
    return
  end

  local key = request_event.key(args, bufnr)
  if not self.active_requests[key] then
    self.active_requests[key] = bufnr
    self.active_chats[bufnr] = (self.active_chats[bufnr] or 0) + 1
  end

  self:sync_processing()
  refresh_lualine()
end

function M:finish_request(args)
  local bufnr = request_event.bufnr(args)
  if not bufnr then
    return
  end

  local key = request_event.key(args, bufnr)
  if self.active_requests[key] then
    self:clear_key(key)
  else
    self:clear_buf(bufnr)
  end

  self:sync_processing()
  refresh_lualine()
end

-- Initializer
function M:init(options)
  M.super.init(self, options)
  self.processing = false
  self.spinner_index = 1
  self.active_requests = {}
  self.active_chats = {}

  local group = vim.api.nvim_create_augroup('CodeCompanionLualineSpinner', {
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
      if args.match == 'CodeCompanionRequestStarted' then
        self:start_request(args)
      elseif args.match == 'CodeCompanionRequestFinished' then
        self:finish_request(args)
      else
        local bufnr = request_event.bufnr(args)
        if bufnr then
          self:clear_buf(bufnr)
          self:sync_processing()
          refresh_lualine()
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      self:clear_buf(args.buf)
      self:sync_processing()
      refresh_lualine()
    end,
  })
end

-- Function that runs every time statusline is updated
function M:update_status()
  if self.processing and next(self.active_chats) ~= nil then
    self.spinner_index = (self.spinner_index % spinner_symbols_len) + 1
    return spinner_symbols[self.spinner_index]
  else
    return nil
  end
end

return M
