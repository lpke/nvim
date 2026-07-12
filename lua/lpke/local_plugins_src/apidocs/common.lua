local function data_folder()
  return vim.fn.stdpath('data') .. '/apidocs-data/'
end

local doc_web_paths = {}

local function sanitize_fname(fname)
  return fname:gsub('/', '_'):gsub("'", '_'):sub(1, 255 - 8)
end

local function resolve_doc_web_url(docs_path, callback)
  local relative_path = docs_path:sub(#data_folder() + 1)
  local source, filename = relative_path:match('^([^/]+)/(.+)$')
  if not source or not filename then
    callback(nil, 'invalid documentation path')
    return
  end

  local function resolve(paths)
    local path = paths[filename]
    if not path then
      callback(nil, 'source page not found')
      return
    end
    callback('https://devdocs.io/' .. source .. '/' .. path)
  end

  if doc_web_paths[source] then
    resolve(doc_web_paths[source])
    return
  end

  vim.system(
    {
      'curl',
      '-fLsS',
      'https://documents.devdocs.io/' .. source .. '/index.json',
    },
    { text = true },
    vim.schedule_wrap(function(result)
      local ok, index = pcall(vim.json.decode, result.stdout or '')
      if
        result.code ~= 0
        or not ok
        or type(index) ~= 'table'
        or type(index.entries) ~= 'table'
      then
        callback(nil, 'failed to fetch source index')
        return
      end

      local paths = { ['index#index.html.md'] = '' }
      for _, entry in ipairs(index.entries) do
        local local_name = sanitize_fname(entry.name .. '#' .. entry.path)
          .. '.html.md'
        paths[local_name] = entry.path
      end
      doc_web_paths[source] = paths
      resolve(paths)
    end)
  )
end

local function open_doc_web_url(docs_path)
  resolve_doc_web_url(docs_path, function(url, err)
    if not url then
      vim.notify('Apidocs: ' .. err, vim.log.levels.ERROR)
      return
    end
    vim.ui.open(url)
  end)
end

-- https://stackoverflow.com/a/34953646/516188
local function escape_pattern(text)
  return text:gsub('([^%w])', '%%%1')
end

local function load_doc_in_buffer(buf, filepath)
  if vim.fn.filereadable(filepath) == 1 then
    local lines = {}
    for line in io.lines(filepath) do
      -- nbsp so that neovim doesn't highlight this as a quoted paragraph
      table.insert(lines, (line:gsub('^    ', '    ')))
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].filetype = 'markdown'
  else
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { 'File not readable: ' .. filepath }
    )
  end
end

local function open_file_buffer(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then
    vim.notify('Apidocs: file not readable: ' .. filepath, vim.log.levels.ERROR)
    return nil
  end

  local buf = vim.fn.bufadd(filepath)
  -- Buffer-load autocmds may switch buffers, so unlock the window first.
  vim.wo.winfixbuf = false
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.bo[buf].filetype = 'markdown'

  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.conceallevel = 2
  vim.wo.concealcursor = 'n'
  vim.wo.list = false
  vim.wo.wrap = false

  return buf
end

local function jump_to_section(section)
  if not section or section == '' then
    return
  end

  local ok, line = pcall(vim.fn.search, section, 'w')
  if ok and line > 0 then
    vim.cmd('normal! zt')
  end
end

local open_doc_in_cur_window

local function reference_target(line)
  local target = line:match('^%s+%d+%. (%S+)') or line:match('^\t(%S+)')
  if not target then
    return nil
  end

  -- Drop marker added when an ID reference cannot be resolved.
  return target:gsub('\t%+.+$', '')
end

local function follow_reference(line)
  local target = reference_target(line)
  if not target then
    return
  end

  if target:match('^https?://') then
    vim.ui.open(target)
    return
  end

  if not vim.startswith(target, 'local://') then
    return
  end

  target = target:sub(#'local://' + 1)
  local components = vim.split(target, '#')
  if #components == 2 then
    -- plain file name
    open_doc_in_cur_window(data_folder() .. target .. '.html.md')
  elseif #components == 3 then
    -- file name+section ID
    open_doc_in_cur_window(
      data_folder() .. components[1] .. '#' .. components[2] .. '.html.md',
      components[3]
    )
  elseif #components == 4 then
    -- file name with two hashes+section ID (happens for lua)
    open_doc_in_cur_window(
      data_folder()
        .. components[1]
        .. '#'
        .. components[2]
        .. '#'
        .. components[3]
        .. '.html.md',
      components[4]
    )
  end
end

open_doc_in_cur_window = function(docs_path, section)
  local buf = open_file_buffer(docs_path)
  if not buf then
    return nil
  end

  local follow_link_keymap = Config and Config.follow_link_keymap or '<C-]>'
  vim.keymap.set('n', follow_link_keymap, function()
    local line = vim.api.nvim_buf_get_lines(
      0,
      vim.fn.line('.') - 1,
      vim.fn.line('.'),
      false
    )[1]
    follow_reference(line)
  end, { buffer = buf })

  require('lpke.core.helpers').keymap_set({
    'n',
    '<leader><CR>',
    function()
      open_doc_web_url(docs_path)
    end,
    { buffer = buf, desc = 'API docs: Open source page' },
  })

  jump_to_section(section)
  return buf
end

local function open_doc_in_new_window(docs_path)
  if vim.fn.filereadable(docs_path) ~= 1 then
    vim.notify(
      'Apidocs: file not readable: ' .. docs_path,
      vim.log.levels.ERROR
    )
    return nil
  end

  local previous_win = vim.api.nvim_get_current_win()
  local ok, err = pcall(vim.cmd, '100vsplit')
  if not ok then
    vim.notify(
      'Apidocs: failed to open docs split: ' .. err,
      vim.log.levels.ERROR
    )
    return nil
  end

  local docs_win = vim.api.nvim_get_current_win()
  local buf = open_doc_in_cur_window(docs_path)
  if not buf then
    if vim.api.nvim_win_is_valid(docs_win) then
      vim.api.nvim_win_close(docs_win, true)
    end
    if vim.api.nvim_win_is_valid(previous_win) then
      vim.api.nvim_set_current_win(previous_win)
    end
    return nil
  end

  vim.wo[docs_win].winfixbuf = true
  return buf
end

-- convert filename to picker display string
local function filename_to_display(filename)
  local components = vim.split(filename, '#')
  local display = components[1]
  -- little hack: In some languages the filename contains "Class#method", which messes
  -- up our "#" - separated schema. So if there are 4 "components" in the filename,
  -- the first two (separated by "#") have to be the actual key to display.
  if #components == 4 then
    display = display .. '#' .. components[2]
  end
  return display
end

return {
  data_folder = data_folder,
  escape_pattern = escape_pattern,
  load_doc_in_buffer = load_doc_in_buffer,
  open_doc_in_cur_window = open_doc_in_cur_window,
  open_doc_in_new_window = open_doc_in_new_window,
  filename_to_display = filename_to_display,
  open_doc_web_url = open_doc_web_url,
  reference_target = reference_target,
  follow_reference = follow_reference,
}
