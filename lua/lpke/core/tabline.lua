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
    local is_active = tab_index == cur_tab_index
    local hl_var = is_active and '%#TabLineSel#' or '%#TabLine#'
    local tab_var = '%' .. tab_index .. 'T'
    local mod_hl_var = is_active and '%#LpkeTabLineModSel#'
      or '%#LpkeTabLineMod#'
    local readonly_hl_var = is_active and '%#LpkeTabLineReadonlySel#'
      or '%#LpkeTabLineReadonly#'

    -- collect info
    local win_id = vim.api.nvim_tabpage_get_win(tab_id)
    local cur_bufnr = vim.api.nvim_win_get_buf(win_id)
    local cur_bufname =
      helpers.remove_protocol(vim.api.nvim_buf_get_name(cur_bufnr))
    local file_type = vim.api.nvim_buf_get_option(cur_bufnr, 'filetype')

    -- parse path into segments
    local file_path = helpers.transform_path(
      cur_bufname,
      { include_filename = false, dir_tail_slash = false }
    )
    local file_name = vim.fn.fnamemodify(cur_bufname, ':t:r')
    local file_ext = vim.fn.fnamemodify(cur_bufname, ':e')

    -- handle modified
    local cur_modified = vim.api.nvim_buf_get_option(cur_bufnr, 'modified')
      and (file_type ~= 'TelescopePrompt')
    local has_modified = cur_modified
    local windows = vim.api.nvim_tabpage_list_wins(tab_id)
    if not cur_modified then
      for _, win in ipairs(windows) do
        local buf = vim.api.nvim_win_get_buf(win)
        local is_modified = vim.api.nvim_buf_get_option(buf, 'modified')
        local is_telescope = vim.api.nvim_buf_get_option(buf, 'filetype')
          == 'TelescopePrompt'
        if is_modified and not is_telescope then
          has_modified = true
          break
        end
      end
    end

    -- handle tab title
    local tab_title = ''
    if file_type == 'oil' then
      local unaltered_path = vim.api.nvim_buf_get_name(cur_bufnr)
      local oil_trash = string.match(unaltered_path, '^oil%-trash://')
      tab_title = (oil_trash and 'T:' or '')
        .. helpers.shorten_path(file_path)
        .. '/'
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
        file_name = file_name:sub(1, (max_fn_len - 4)) .. '…'
      end
      tab_title = file_name .. ((file_ext ~= '') and ('.' .. file_ext) or '')
    end

    -- handle readonly
    local cur_readonly = vim.api.nvim_buf_get_option(cur_bufnr, 'readonly')

    -- add this tab to string
    tabline = tabline
      .. hl_var
      .. tab_var
      .. ' '
      .. tab_title
      .. readonly_hl_var
      .. (cur_readonly and (' ' .. symbols.readonly) or '')
      .. mod_hl_var
      .. (has_modified and (' ' .. (cur_modified and symbols.modified or '+')) or '')
      .. ' '
  end

  -- fill remaining space and reset tab number
  tabline = tabline .. '%#TabLineFill#%T'

  return tabline
end
