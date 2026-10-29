local M = {}
local api = vim.api
local requests, listeners = {}, {}
local ready = false

local function chat_buffer(bufnr)
  return bufnr
    and api.nvim_buf_is_valid(bufnr)
    and vim.bo[bufnr].filetype == 'codecompanion'
end

local function changed(bufnr, busy)
  for _, callback in pairs(listeners) do
    callback(bufnr, busy)
  end
end

-- No-ID events share one fallback request. Finishing it must never clear
-- identified requests; only stop, close or buffer removal cancels those.
local function request_event(args)
  local data = type(args.data) == 'table' and args.data or {}
  local bufnr = tonumber(data.bufnr or data.chat_bufnr)
  if not bufnr or bufnr <= 0 then
    return
  end
  local id = data.id or data.request_id
  local key = id ~= nil and id ~= '' and tostring(id) or false
  local is_chat = data.interaction == 'chat'
    or (data.interaction == nil and chat_buffer(bufnr))
  return bufnr, key, is_chat
end

function M.busy(chat)
  if chat == nil then
    return next(requests) ~= nil
  end
  local bufnr = type(chat) == 'table' and chat.bufnr or chat
  return bufnr ~= nil and requests[bufnr] ~= nil
end

function M.clear(bufnr)
  if requests[bufnr] then
    requests[bufnr] = nil
    changed(bufnr, false)
  end
end

function M.setup()
  if ready then
    return
  end
  ready = true
  local group = api.nvim_create_augroup('LpkeCodeCompanionRequests', {})
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = {
      'CodeCompanionRequestStarted',
      'CodeCompanionRequestFinished',
      'CodeCompanionChatStopped',
      'CodeCompanionChatClosed',
    },
    callback = function(args)
      local bufnr, key, is_chat = request_event(args)
      if not bufnr then
        return
      end
      if
        args.match == 'CodeCompanionChatStopped'
        or args.match == 'CodeCompanionChatClosed'
      then
        M.clear(bufnr)
      elseif is_chat then
        local active = requests[bufnr]
        if
          args.match == 'CodeCompanionRequestStarted' and chat_buffer(bufnr)
        then
          if not active then
            requests[bufnr] = { [key] = true }
            changed(bufnr, true)
          else
            active[key] = true
          end
        elseif active and active[key] then
          active[key] = nil
          if next(active) == nil then
            M.clear(bufnr)
          end
        end
      end
    end,
  })
  api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      M.clear(args.buf)
    end,
  })
end

-- Named subscribers survive component reinitialization without accumulating
-- callbacks. Late subscribers receive the currently active chats.
function M.subscribe(name, callback)
  M.setup()
  listeners[name] = callback
  for bufnr in pairs(requests) do
    callback(bufnr, true)
  end
end

return M
