local M = {}

local function data(args)
  if type(args) ~= 'table' or type(args.data) ~= 'table' then
    return nil
  end

  return args.data
end

local function positive_number(value)
  local number = tonumber(value)
  if number and number > 0 then
    return number
  end
end

function M.bufnr(args)
  local event_data = data(args)
  if not event_data then
    return nil
  end

  return positive_number(event_data.bufnr or event_data.chat_bufnr)
end

function M.key(args, bufnr)
  local event_data = data(args)
  local id = event_data and (event_data.id or event_data.request_id)

  if id ~= nil and id ~= '' then
    return tostring(bufnr) .. ':' .. tostring(id)
  end

  return tostring(bufnr)
end

function M.is_chat(args, bufnr)
  local event_data = data(args)
  if not event_data then
    return false
  end

  if event_data.interaction ~= nil then
    return event_data.interaction == 'chat'
  end

  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local ok, filetype = pcall(function()
    return vim.bo[bufnr].filetype
  end)

  return ok and filetype == 'codecompanion'
end

return M
