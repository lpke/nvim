---@class lpke.core.helpers.config
local M = {}

local util = require('lpke.core.helpers.util')

-- convert my options table into vim.opt.<key> = <value>
function M.set_options(options)
  for k, v in pairs(options) do
    vim.opt[k] = v
  end
end

-- parses a table containing custom keymap args and sets or deletes the keymap
function M.keymap_set(keymap)
  local mode, lhs, rhs, opts = table.unpack(keymap)
  opts = util.merge_tables({ noremap = true }, opts or {})
  local modes = {}
  local delete_only = false
  local mac_lhs = ''
  local is_cmd = false

  for char in mode:gmatch('.') do
    if char == 'R' then
      opts.noremap = false
    elseif char == 'E' then
      opts.expr = true
    elseif char == 'C' then
      rhs = '<cmd>' .. rhs .. '<cr>'
      is_cmd = true
    elseif char == '!' then
      opts.silent = true
    elseif char == 'D' then
      delete_only = true
    elseif char == 'M' then
      if lhs:find('<C%-') then
        mac_lhs = lhs:gsub('<C%-', '<D-')
      end
    else
      table.insert(modes, char)
    end
  end

  if
    opts.square_repeat
    and not is_cmd
    and (type(rhs) == 'function')
    and Match(lhs, '^[%[%]][a-zA-Z]$') -- is a "square movement" (eg `[q`)
  then
    local orig_rhs = rhs
    rhs = function()
      orig_rhs()
      local movement_key = string.sub(lhs, 2, -1)
      Lpke_square_repeat_key = movement_key
    end
    opts.square_repeat = nil
  end

  if delete_only then
    vim.keymap.del(modes, lhs, opts)
    if mac_lhs ~= '' then
      vim.keymap.del(modes, mac_lhs, opts)
    end
  else
    vim.keymap.set(modes, lhs, rhs, opts)
    if mac_lhs ~= '' then
      vim.keymap.set(modes, mac_lhs, rhs, opts)
    end
  end
end

-- same as above but accepts multiple keymap tables in a table
function M.keymap_set_multi(keymaps)
  for _i, keymap in ipairs(keymaps) do
    M.keymap_set(keymap)
  end
end

-- same as above but requires a filetype, and optionally accepts a condition function
function M.ft_keymap_set_multi(filetype_pattern, keymaps, cond_func)
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter' }, {
    pattern = filetype_pattern,
    callback = function(event)
      local bufnr = event.buf
      -- run `cond_func` if provided
      if type(cond_func) == 'function' and (not cond_func(bufnr)) then
        return
      end
      -- add `buffer` option to every keymap
      for i, keymap in ipairs(keymaps) do
        local mode, lhs, rhs, opts = table.unpack(keymap)
        opts = opts or {}
        opts.buffer = bufnr
        keymaps[i] = { mode, lhs, rhs, opts }
      end
      M.keymap_set_multi(keymaps)
    end,
  })
end

function M.telescope_keymap_set_multi(target_title, keymaps, cond_func)
  M.ft_keymap_set_multi('TelescopePrompt', keymaps, function(bufnr)
    local ok, actions_state = pcall(require, 'telescope.actions.state')
    if not ok then
      return false
    end
    local prompt_title = actions_state.get_current_picker(bufnr).prompt_title
    if
      type(cond_func) == 'function' and (not cond_func(bufnr, prompt_title))
    then
      return false
    end
    return Match(prompt_title, target_title)
  end)
end

-- yank still: upwards (up to `max`)
function M.keymap_set_yank_still_upwards(max)
  for i = 1, max do
    M.keymap_set({ 'nC', ('y' .. i .. 'k'), ('-' .. i .. ',.y') })
  end
end

-- yank still: marks (a-z)
function M.keymap_set_yank_still_marks()
  for i = string.byte('a'), string.byte('z') do
    local letter = string.char(i)
    M.keymap_set({ 'nC!', ("y'" .. letter), ("'" .. letter .. ',.y') })
  end
end

-- parses a table containing custom command args and creates or deletes the command
function M.command_set(command)
  local flags, name, cmd, opts = table.unpack(command)
  opts = util.merge_tables({}, opts or {})
  local delete_only = false

  for char in flags:gmatch('.') do
    if char == 'B' then
      opts.bang = true
    elseif char == 'R' then
      opts.range = true
    elseif char == 'D' then
      delete_only = true
    elseif char == '0' then -- no args allowed
      opts.nargs = 0
    elseif char == '1' then -- 1 arg required, unescaped spaces allowed
      opts.nargs = 1
    elseif char == '?' then -- 1 arg optional, unescaped spaces allowed
      opts.nargs = '?'
    elseif char == '+' then -- required many args
      opts.nargs = '+'
    elseif char == '*' then -- optional many args
      opts.nargs = '*'
    end
  end

  if delete_only then
    vim.api.nvim_del_user_command(name)
  else
    vim.api.nvim_create_user_command(name, cmd, opts)
  end
end

-- same as above but accepts multiple command tables in a table
function M.command_set_multi(commands)
  for _i, command in ipairs(commands) do
    M.command_set(command)
  end
end

-- getter and setters for highlight colors
function M.get_hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end
function M.set_hl(name, hl)
  vim.api.nvim_set_hl(0, name, hl)
end
function M.set_hl_multi(highlights)
  for name, hl in pairs(highlights) do
    M.set_hl(name, hl)
  end
end

return M
