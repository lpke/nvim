local config = require('lpke.core.html_server.config')
local paths = require('lpke.core.html_server.paths')

local uv = vim.uv or vim.loop

local M = {}

M.path = config.registry_path

local function empty_registry()
  return { version = 1, servers = vim.empty_dict() }
end

local function normalize_servers_for_json(data)
  if type(data.servers) ~= 'table' or next(data.servers) == nil then
    data.servers = vim.empty_dict()
  end
  return data
end

local function ensure_dir()
  vim.fn.mkdir(config.registry_dir, 'p')
end

function M.read()
  local ok, lines = pcall(vim.fn.readfile, config.registry_path)
  if not ok then
    return empty_registry()
  end

  local raw = table.concat(lines, '\n')
  if raw == '' then
    return empty_registry()
  end

  local decode_ok, data = pcall(vim.json.decode, raw)
  if not decode_ok or type(data) ~= 'table' then
    return empty_registry(), 'invalid'
  end

  data.version = 1
  if type(data.servers) ~= 'table' then
    data.servers = {}
  end
  return data
end

function M.write(data)
  ensure_dir()
  data.version = 1
  normalize_servers_for_json(data)

  local encoded = vim.json.encode(data)
  local tmp = string.format(
    '%s.tmp.%s.%d',
    config.registry_path,
    vim.fn.getpid(),
    math.random(100000, 999999)
  )

  local ok, err = pcall(vim.fn.writefile, { encoded }, tmp)
  if not ok then
    return false, err
  end

  local rename_ok, rename_err = uv.fs_rename(tmp, config.registry_path)
  if not rename_ok then
    pcall(vim.fn.delete, tmp)
    return false, rename_err
  end

  return true
end

function M.entries()
  local data, err = M.read()
  local entries = {}
  for key, entry in pairs(data.servers or {}) do
    if type(entry) == 'table' then
      entry.path = paths.normalize(entry.path or key)
      if entry.path then
        table.insert(entries, entry)
      end
    end
  end
  table.sort(entries, function(a, b)
    return (a.path or '') < (b.path or '')
  end)
  return entries, err
end

function M.upsert(entry)
  if not entry or not entry.path then
    return false, 'missing path'
  end

  local path = paths.normalize(entry.path)
  if not path then
    return false, 'invalid path'
  end

  local data = M.read()
  local current = data.servers[path] or {}
  entry.path = path
  data.servers[path] = vim.tbl_deep_extend('force', current, entry)
  return M.write(data)
end

function M.remove(path, token)
  path = paths.normalize(path)
  if not path then
    return false
  end

  local data = M.read()
  local entry = data.servers[path]
  if not entry then
    return false
  end
  if token and entry.token ~= token then
    return false
  end

  data.servers[path] = nil
  M.write(data)
  return true
end

function M.remove_many(entries)
  if not entries or #entries == 0 then
    return 0
  end

  local data = M.read()
  local removed = 0
  for _, entry in ipairs(entries) do
    local path = paths.normalize(entry.path)
    local current = path and data.servers[path]
    if current and (not entry.token or current.token == entry.token) then
      data.servers[path] = nil
      removed = removed + 1
    end
  end

  if removed > 0 then
    M.write(data)
  end
  return removed
end

function M.find(target)
  if type(target) == 'number' then
    for _, entry in ipairs(M.entries()) do
      if tonumber(entry.port) == target then
        return entry
      end
    end
    return nil
  end

  if type(target) ~= 'string' or target == '' then
    return nil
  end

  local port = tonumber(target)
  if port then
    return M.find(port)
  end

  local target_path = paths.normalize(vim.fn.expand(target))
  if not target_path then
    return nil
  end

  local data = M.read()
  local entry = data.servers[target_path]
  if type(entry) == 'table' then
    entry.path = target_path
    return entry
  end
  return nil
end

return M
