-- Optional personal integrations live outside the shared Neovim repository.
local M = {}
local callbacks = {}

function M.setup()
  if Lpke_is_work_device then
    return
  end
  local root = vim.fn.stdpath('config') .. '-local'
  if vim.fn.filereadable(root .. '/init.lua') == 0 then
    return
  end
  vim.opt.runtimepath:append(root)
  callbacks = dofile(root .. '/init.lua') or {}
end

function M.call(name, ...)
  if type(callbacks[name]) == 'function' then
    return callbacks[name](...)
  end
end

return M
