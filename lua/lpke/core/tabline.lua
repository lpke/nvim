local helpers = require('lpke.core.helpers')
local symbols = require('lpke.core.options').custom_opts.symbols

function Lpke_tabline()
  -- initialise string and get context
  local tabline = ''
  local tabs = vim.api.nvim_list_tabpages()
  local cur_tab_index = vim.fn.tabpagenr()

  -- iterate over each tab page
  for tab_index, tab_id in ipairs(tabs) do
    -- handle vars
    local hl_var = (tab_index == cur_tab_index) and '%#TabLineSel#'
      or '%#TabLine#'
    local tab_var = '%' .. tab_index .. 'T'

    -- collect info
    -- string.match(str, '^ ?oi?l?:?//') then
    -- str:gsub('^ ?oi?l?:?//', '')
    local win_id = vim.api.nvim_tabpage_get_win(tab_id)
    local cur_bufnr = vim.api.nvim_win_get_buf(win_id)
    local cur_bufname = vim.api.nvim_buf_get_name(cur_bufnr)
    local file_type = vim.api.nvim_buf_get_option(cur_bufnr, 'filetype')

    -- handle oil paths
    local is_oil = file_type == 'oil'
    if is_oil then
      cur_bufname = cur_bufname:gsub('^oi?l?:?//', '')
    end

    -- parse path into segments
    local cwd_folder = helpers.get_cwd_folder()
    local file_path = vim.fn.fnamemodify(cur_bufname, ':p:~:.:h')
    local file_name = vim.fn.fnamemodify(cur_bufname, ':t:r')
    local file_ext = vim.fn.fnamemodify(cur_bufname, ':e')
    if file_path == '.' then
      file_path = cwd_folder
    end
    local file_dir = helpers.get_path_tail(file_path)
    local file_path_short = file_path:gsub('([^/%w]?[^/])[^/]*/', '%1/')

    -- handle tab title
    local tab_title = ''
    if file_type == 'oil' then
      tab_title = file_path_short
    elseif file_type == 'harpoon' then
      tab_title = 'harpoon'
    elseif file_type == 'TelescopePrompt' then
      tab_title = 'telescope'
    elseif file_type == 'undotree' then
      tab_title = 'undotree'
    elseif file_type == 'diff' then
      tab_title = 'diff'
    elseif file_name == '' then
      tab_title = symbols.unnamed
    else
      local max_fn_len = 20
      if #file_name > max_fn_len then
        file_name = file_name:sub(1, (max_fn_len - 4))
          .. '…'
      end
      tab_title = file_name .. ((file_ext ~= '') and ('.' .. file_ext) or '')
    end

    -- handle modified
    local windows = vim.api.nvim_tabpage_list_wins(tab_id)
    local has_modified = false
    for _, win in ipairs(windows) do
      local buf = vim.api.nvim_win_get_buf(win)
      local is_modified = vim.api.nvim_buf_get_option(buf, 'modified')
      if is_modified then
        has_modified = true
        break
      end
    end

    -- add this tab to string
    tabline = tabline
      .. hl_var
      .. tab_var
      .. ' '
      .. tab_title
      .. (has_modified and (' ' .. symbols.modified) or '')
      .. ' '
  end

  -- fill remaining space and reset tab number
  tabline = tabline .. '%#TabLineFill#%T'

  return tabline
end
