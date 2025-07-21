---@class lpke.core.helpers.get
local M = {}

local util = require('lpke.core.helpers.util')
local format = require('lpke.core.helpers.format')

M.is_wsl = vim.fn.exists('$WSL_DISTRO_NAME') == 1

-- get current session name
function M.get_session_name(fallback)
  return util.safe_call(
    require('auto-session.lib').current_session_name,
    true,
    fallback
  )
end

-- check if session exists and matches cwd
function M.session_in_cwd()
  local cwd = helpers.get_cwd_folder()
  local session = M.get_session_name()
  return session and not (cwd == session)
end

-- get buf file type (current if omitted)
function M.get_file_type(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_get_option_value('filetype', { buf = bufnr })
end

return M
