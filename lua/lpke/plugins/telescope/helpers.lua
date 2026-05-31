local builtin = require('telescope.builtin')
local path_helpers = require('lpke.core.helpers')

local M = {}

local function trim(str)
  return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.normalize_cwd(cwd)
  cwd = cwd or vim.fn.getcwd()
  if cwd == '' then
    cwd = vim.fn.getcwd()
  end
  cwd = path_helpers.expand_home(cwd)
  if not path_helpers.is_absolute_path(cwd) then
    cwd = vim.fn.fnamemodify(cwd, ':p')
  end
  return path_helpers.normalize_path(cwd) or vim.fn.getcwd()
end

function M.resolve_prompt_cwd(cwd_arg, base_cwd)
  if cwd_arg == nil or cwd_arg == '' then
    return M.normalize_cwd(base_cwd)
  end

  local expanded_cwd_arg = path_helpers.expand_home(cwd_arg)
  if path_helpers.is_absolute_path(expanded_cwd_arg) then
    return path_helpers.normalize_path(expanded_cwd_arg) or expanded_cwd_arg
  end
  return path_helpers.normalize_path(
    vim.fs.joinpath(M.normalize_cwd(base_cwd), expanded_cwd_arg)
  )
end

function M.prompt_cwd_path_arg(cwd_arg)
  if cwd_arg == nil or cwd_arg == '' then
    return nil
  end

  return path_helpers.expand_home(cwd_arg)
end

function M.parse_prompt_cwd(prompt, base_cwd)
  prompt = prompt or ''
  base_cwd = M.normalize_cwd(base_cwd)

  local unrestricted_prefix, cwd_arg, rest = prompt:match('^@(%*?)(.-)  (.*)$')
  if not cwd_arg then
    return {
      raw_prompt = prompt,
      prompt = prompt,
      base_cwd = base_cwd,
      cwd = base_cwd,
      cwd_arg = nil,
      path_arg = nil,
      has_cwd_arg = false,
      unrestricted = false,
      valid_cwd = true,
    }
  end

  cwd_arg = trim(cwd_arg)
  local cwd = M.resolve_prompt_cwd(cwd_arg, base_cwd)
  local path_arg = M.prompt_cwd_path_arg(cwd_arg)
  return {
    raw_prompt = prompt,
    prompt = rest or '',
    base_cwd = base_cwd,
    cwd = cwd,
    cwd_arg = path_arg and cwd_arg or nil,
    path_arg = path_arg,
    has_cwd_arg = path_arg ~= nil,
    unrestricted = unrestricted_prefix == '*',
    valid_cwd = vim.fn.isdirectory(cwd) == 1,
  }
end

function M.parse_multigrep_prompt(prompt, base_cwd)
  local parsed = M.parse_prompt_cwd(prompt, base_cwd)
  local pieces = vim.split(parsed.prompt, '  ', {
    plain = true,
    trimempty = false,
  })

  parsed.search = pieces[1] or ''
  parsed.globs = {}
  for i = 2, #pieces do
    local glob = trim(pieces[i])
    if glob ~= '' then
      table.insert(parsed.globs, glob)
    end
  end

  return parsed
end

-- refresh a telescope picker and optionally remember selection location
function M.refresh_picker(bufnr, remember, selection_defer_time)
  selection_defer_time = selection_defer_time or 5
  if remember == nil then
    remember = true
  end
  local ok, result = pcall(function()
    local actions_state = require('telescope.actions.state')
    local picker = actions_state.get_current_picker(bufnr)
    local index = picker._selection_row
    picker:refresh()
    if remember then
      vim.defer_fn(function()
        picker:set_selection(index)
      end, selection_defer_time)
    end
  end)

  if not ok then
    vim.notify('Error refreshing picker: ' .. result, vim.log.levels.ERROR)
  end
end

-- iterate over selection/s in a telescope picker
function M.telescope_sel_foreach(bufnr, func)
  local actions_state = require('telescope.actions.state')
  local actions_utils = require('telescope.actions.utils')

  local selections = {}
  actions_utils.map_selections(bufnr, function(entry)
    table.insert(selections, entry)
  end)

  if #selections == 0 then
    local selection = actions_state.get_selected_entry(bufnr)
    func(selection)
  else
    for _, v in ipairs(selections) do
      func(v)
    end
  end
end

-- workaround since breaking change where this can't be accessed with:
-- require('auto-session.session-lens.actions').delete_session()
function M.delete_session(bufnr)
  local auto_session = require('auto-session')
  local action_state = require('telescope.actions.state')
  local current_picker = action_state.get_current_picker(bufnr)
  current_picker:delete_selection(function(selection)
    if selection then
      auto_session.DeleteSessionFile(selection.path, selection.display())
    end
  end)
end

-- custom mapping functions
function M.remove_selected_from_qflist(bufnr)
  local qflist = vim.fn.getqflist()
  M.telescope_sel_foreach(bufnr, function(sel)
    for i, item in ipairs(qflist) do
      if item.bufnr == sel.bufnr and item.lnum == sel.lnum then
        table.remove(qflist, i)
        break
      end
    end
  end)
  vim.fn.setqflist(qflist)
  M.refresh_picker(bufnr)
  builtin.quickfix()
end

function M.force_delete_selected_bufs(bufnr)
  M.telescope_sel_foreach(bufnr, function(sel)
    vim.api.nvim_buf_delete(sel.bufnr, { force = true })
  end)
  builtin.buffers()
end

function M.remove_selected_from_harpoon(bufnr)
  M.telescope_sel_foreach(bufnr, function(sel)
    local filename = sel.value.filename and sel.value.filename or sel.filename
    require('harpoon.mark').rm_file(filename)
  end)
  vim.cmd('Telescope harpoon marks')
  pcall(function()
    require('lualine').refresh()
  end)
end

function M.remove_selected_from_codecompanion(bufnr)
  local cc_history = require('codecompanion').extensions.history
  M.telescope_sel_foreach(bufnr, function(sel)
    local save_id = sel.save_id
    cc_history.delete_chat(save_id)
  end)
  vim.cmd('CodeCompanionHistory')
  pcall(function()
    require('lualine').refresh()
  end)
end

return M
