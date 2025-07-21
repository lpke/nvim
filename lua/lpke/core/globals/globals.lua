-- like print but can print tables
function Print(
  val,
  max_depth,
  indent_size,
  indent,
  newline_at_end,
  current_depth,
  is_top_level
)
  is_top_level = is_top_level == nil and true or is_top_level
  if type(val) ~= 'table' then
    print(val)
  else
    indent_size = indent_size or 2
    indent = indent or ''
    max_depth = max_depth or 0
    current_depth = current_depth or 0

    if current_depth > max_depth then
      print(indent .. '...')
      return
    end

    local next_indent = indent .. string.rep(' ', indent_size)
    for k, v in pairs(val) do
      local key = tostring(k)
      if type(v) == 'table' then
        print(indent .. key .. ':')
        Print(
          v,
          max_depth,
          indent_size,
          next_indent,
          false,
          current_depth + 1,
          false
        )
      else
        print(indent .. key .. ': ' .. tostring(v))
      end
    end
  end
  if newline_at_end and is_top_level then
    print(' ')
  end
end

---Check if there are any `regex` matches on `str`
---@param str string String to test regex on
---@param regex string Regex string to run on `str`
---@return boolean matched Whether any matches were found in `str` using `regex`
function Match(str, regex)
  return string.match(str, regex) ~= nil
end

-- wrapper for `nvim_replace_termcodes`
---@param string_or_args string|any[]
function Lpke_replace_termcodes(string_or_args)
  if type(string_or_args) == 'string' then
    return vim.api.nvim_replace_termcodes(string_or_args, true, true, true)
  elseif type(string_or_args) == 'table' then
    local str = string_or_args[1]
    local from_part = str[2] ~= nil and str[2] or true
    local do_lt = str[3] ~= nil and str[3] or true
    local special = str[4] ~= nil and str[4] or true
    return vim.api.nvim_replace_termcodes(str, from_part, do_lt, special)
  else
    vim.notify(
      'Lpke_replace_termcodes: `key` must be a string or table',
      vim.log.levels.ERROR
    )
  end
end

---Wrapper for `nvim_feedkeys` which also handles escaping termcodes.
---@param keys_or_args string|any[] String or { args... } to be passed to `nvim_replace_termcodes`
---@param flags? string Mode flags. Any combination of 'm', 'n', 't', 'L', 'i', 'x', '!'. See `:h feedkeys`
---@param escape_ks? boolean Whether to escape termcodes (handled already by default)
function Lpke_feedkeys(keys_or_args, flags, escape_ks)
  -- handle defaults based on args
  local keys
  if (type(escape_ks) == 'boolean') and (type(keys_or_args) == 'string') then
    -- if escape_ks is explicitly set, do not `replace_termcodes`
    keys = keys_or_args
  else
    keys = Lpke_replace_termcodes(keys_or_args)
  end
  flags = flags or 'm'
  if escape_ks == nil then
    escape_ks = false
  end
  vim.api.nvim_feedkeys(keys, flags, escape_ks)
end

-- unload inactive buffers (any not in use)
function Lpke_clean_buffers()
  local active_bufs = Lpke_get_active_bufs()

  -- unload buffers that are not in active_bufs
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not active_bufs[buf] then
      -- dont unload if buffer has unsaved changes
      local modifiable =
        vim.api.nvim_get_option_value('modifiable', { buf = buf })
      local modified = vim.api.nvim_get_option_value('modified', { buf = buf })
      if (modifiable and not modified) or not modifiable then
        vim.api.nvim_buf_delete(buf, { force = false, unload = false })
      end
    end
  end
end

-- run a function silently (temporarily suppresses all logs)
Lpke_vim_notify = vim.notify
function Lpke_silent(func)
  local ok, result = pcall(function()
    Lpke_vim_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
    func()
    vim.notify = Lpke_vim_notify
  end)
  if not ok then
    vim.notify(
      'Error running function silently. Reverting notify function. Error: '
        .. result,
      vim.log.levels.ERROR
    )
    vim.notify = Lpke_vim_notify
  end
end

-- toggle global status line ('laststatus' option 2/3)
function Lpke_toggle_global_status()
  if vim.o.laststatus == 3 then
    vim.o.laststatus = 2
  else
    vim.o.laststatus = 3
  end
end
