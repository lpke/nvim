local helpers = require('lpke.core.helpers')

local function data_folder()
  return vim.fn.stdpath('data') .. '/apidocs-data/'
end

local doc_indexes = {}
local derived_source_urls = {}
local installed_source_urls = {}

local function sanitize_fname(fname)
  return fname:gsub('/', '_'):gsub("'", '_'):sub(1, 255 - 8)
end

local function doc_path_parts(docs_path)
  local relative_path = docs_path:sub(#data_folder() + 1)
  local source, filename = relative_path:match('^([^/]+)/(.+)$')
  if not source or not filename then
    return nil, nil, 'invalid documentation path'
  end
  return source, filename
end

local function resolve_doc_index(source, callback)
  if doc_indexes[source] then
    callback(doc_indexes[source])
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
      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if
        result.code ~= 0
        or not ok
        or type(data) ~= 'table'
        or type(data.entries) ~= 'table'
      then
        callback(nil, 'failed to fetch source index')
        return
      end

      local index = {
        paths = { ['index#index.html.md'] = '' },
        filenames = { [''] = 'index#index.html.md' },
      }
      for _, entry in ipairs(data.entries) do
        local filename = sanitize_fname(entry.name .. '#' .. entry.path)
          .. '.html.md'
        index.paths[filename] = entry.path
        index.filenames[entry.path] = filename
      end
      doc_indexes[source] = index
      callback(index)
    end)
  )
end

local function resolve_doc_web_url(docs_path, callback)
  local source, filename, err = doc_path_parts(docs_path)
  if not source then
    callback(nil, err)
    return
  end

  resolve_doc_index(source, function(index, index_err)
    if not index then
      callback(nil, index_err)
      return
    end

    local path = index.paths[filename]
    if path == nil then
      callback(nil, 'source page not found')
      return
    end
    callback('https://devdocs.io/' .. source .. '/' .. path)
  end)
end

local function valid_url(url)
  return type(url) == 'string' and url:match('^https?://') and url or nil
end

local function installed_source_url(source, filename)
  if installed_source_urls[source] then
    return valid_url(installed_source_urls[source][filename])
  end

  local path = data_folder() .. source .. '/.source_urls.json'
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, urls = pcall(vim.json.decode, table.concat(vim.fn.readfile(path)))
  if not ok or type(urls) ~= 'table' then
    return nil
  end

  installed_source_urls[source] = urls
  return valid_url(urls[filename])
end

local function attribution_url_from_doc(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local last_url
  for line in io.lines(path) do
    local url = line:match('^%s*%d+%.%s+(https?://%S+)%s*$')
    if url then
      last_url = url
    end
  end
  return last_url
end

local function resolve_doc_source_url(docs_path, callback)
  local source, filename, err = doc_path_parts(docs_path)
  if not source then
    callback(nil, nil, err)
    return
  end

  local installed_url = installed_source_url(source, filename)
  if installed_url then
    callback(installed_url)
    return
  end

  if derived_source_urls[docs_path] then
    callback(derived_source_urls[docs_path])
    return
  end

  resolve_doc_index(source, function(index, index_err)
    if not index then
      callback(nil, nil, index_err)
      return
    end

    local entry_path = index.paths[filename]
    if entry_path == nil then
      callback(nil, nil, 'source page not found')
      return
    end

    local devdocs_url = 'https://devdocs.io/' .. source .. '/' .. entry_path
    local base_path = entry_path:match('^[^#]*')
    local base_filename = index.filenames[base_path]
    local source_url = base_filename
        and attribution_url_from_doc(
          data_folder() .. source .. '/' .. base_filename
        )
      or nil
    local fragment = entry_path:match('#(.+)$')
    if source_url and fragment then
      source_url = source_url:gsub('#.*$', '') .. '#' .. fragment
    end

    if source_url then
      derived_source_urls[docs_path] = source_url
    end
    callback(source_url, devdocs_url)
  end)
end

local function open_url(url, err)
  if not url then
    vim.notify('Apidocs: ' .. err, vim.log.levels.ERROR)
    return
  end
  vim.ui.open(url)
end

local function open_doc_url(docs_path)
  resolve_doc_source_url(docs_path, function(source_url, devdocs_url, err)
    open_url(source_url or devdocs_url, err)
  end)
end

local function open_doc_web_url(docs_path)
  resolve_doc_web_url(docs_path, function(url, err)
    open_url(url, err)
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
  if helpers.open_url_under_cursor() then
    return
  end

  local target = reference_target(line)
  if not target then
    return
  end

  if target:match('^https?://') then
    helpers.open_url(target)
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

local function follow_reference_under_cursor()
  follow_reference(vim.api.nvim_get_current_line())
end

open_doc_in_cur_window = function(docs_path, section)
  local buf = open_file_buffer(docs_path)
  if not buf then
    return nil
  end

  local follow_link_keymap = Config and Config.follow_link_keymap or '<C-]>'
  helpers.keymap_set({
    'n',
    follow_link_keymap,
    follow_reference_under_cursor,
    { buffer = buf, desc = 'API docs: Open URL or follow reference' },
  })

  jump_to_section(section)
  return buf
end

local function current_tab_is_empty_no_name()
  local current_win = vim.api.nvim_get_current_win()
  local non_float_wins = vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ''
  end, vim.api.nvim_tabpage_list_wins(0))
  if #non_float_wins ~= 1 or non_float_wins[1] ~= current_win then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(buf) == ''
    and vim.bo[buf].buftype == ''
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
end

local function open_doc_in_new_window(docs_path)
  if vim.fn.filereadable(docs_path) ~= 1 then
    vim.notify(
      'Apidocs: file not readable: ' .. docs_path,
      vim.log.levels.ERROR
    )
    return nil
  end

  if current_tab_is_empty_no_name() then
    local no_name_buf = vim.api.nvim_get_current_buf()
    local buf = open_doc_in_cur_window(docs_path)
    if buf then
      vim.wo.winfixbuf = true
      pcall(vim.api.nvim_buf_delete, no_name_buf, { force = false })
    end
    return buf
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
  open_doc_url = open_doc_url,
  open_doc_web_url = open_doc_web_url,
  reference_target = reference_target,
  follow_reference = follow_reference,
  follow_reference_under_cursor = follow_reference_under_cursor,
}
