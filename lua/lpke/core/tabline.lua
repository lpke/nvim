local helpers = require('lpke.core.helpers')
local symbols = require('lpke.core.options').custom_opts.symbols

-- configures and renders the tabline (call it again to refresh)
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
    local zoom_hl_var = is_active and '%#LpkeTabLineZoomSel#'
      or '%#LpkeTabLineZoom#'

    -- collect info
    local win_id = vim.api.nvim_tabpage_get_win(tab_id)
    local cur_bufnr = vim.api.nvim_win_get_buf(win_id)
    local raw_cur_bufname = helpers.get_buf_name(cur_bufnr)
    local cur_bufname = helpers.remove_protocol(raw_cur_bufname)
    local file_type =
      vim.api.nvim_get_option_value('filetype', { buf = cur_bufnr })
    local tab_zoomed = Lpke_zoomed[tab_id]

    -- parse path into segments
    local file_path = helpers.transform_path(
      cur_bufname,
      { include_filename = false, dir_tail_slash = false }
    )
    local file_name = vim.fn.fnamemodify(cur_bufname, ':t:r')
    local file_ext = vim.fn.fnamemodify(cur_bufname, ':e')

    -- handle modified
    local cur_modified = vim.api.nvim_get_option_value(
      'modified',
      { buf = cur_bufnr }
    ) and (file_type ~= 'TelescopePrompt')
    local has_modified = cur_modified
    local windows = vim.api.nvim_tabpage_list_wins(tab_id)
    if not cur_modified then
      for _, win in ipairs(windows) do
        local buf = vim.api.nvim_win_get_buf(win)
        local is_modified =
          vim.api.nvim_get_option_value('modified', { buf = buf })
        local is_telescope = vim.api.nvim_get_option_value(
          'filetype',
          { buf = buf }
        ) == 'TelescopePrompt'
        if is_modified and not is_telescope then
          has_modified = true
          break
        end
      end
    end

    -- TAB TITLE
    local tab_title = ''
    -- TODO: move and use this in other parts of the file
    local b = Lpke_buf_details(cur_bufnr)
    -- filename dependent naming
    local filetype_tabtitle_maps = {
      ['qf'] = 'Quickfix',
      ['TelescopePrompt'] = 'Telescope',
      ['harpoon'] = 'Harpoon',
      ['lazy'] = 'Lazy',
      ['mason'] = 'Mason',
      ['undotree'] = 'Undotree',
      ['codecompanion'] = 'CodeCompanion',
      ['gitcommit'] = 'G:Commit',
      ['diff'] = 'G:Diff',
      ['fugitive'] = 'G:F-Status',
      ['fugitiveblame'] = 'G:F-Blame',
      ['gitsigns-blame'] = 'G:GS-Blame',
      ['DiffviewFiles'] = 'G:DV-Diff',
      ['DiffviewFileHistory'] = 'G:DV-History',
    }
    -- filetype dependent titles
    if filetype_tabtitle_maps[b.file_type] then
      tab_title = filetype_tabtitle_maps[b.file_type]
    elseif b.file_type == 'oil' then
      tab_title = (b.custom_buf_type == 'oil_trash' and 'T:' or '')
        .. helpers.shorten_path(file_path)
        .. '/'
    elseif b.file_type == '' or b.buf_name == '[No Name]' then
      tab_title = symbols.unnamed
    -- git buffers (not already explicitly handled in the map above)
    -- TODO: improve handling here for more cases
    elseif Match(b.custom_buf_type, '^git') then
      if b.custom_buf_type == 'git_diffview' then
        tab_title = 'G:Diffview'
      elseif b.custom_buf_type == 'git_fugitive' then
        tab_title = 'G:Fugitive'
      else
        tab_title = 'G:' .. helpers.shorten_path(file_path)
      end
    else
      local max_fn_len = 20
      if #file_name > max_fn_len then
        file_name = file_name:sub(1, (max_fn_len - 4)) .. '…'
      end
      tab_title = file_name .. ((file_ext ~= '') and ('.' .. file_ext) or '')
    end
    -- if no tab title, fall back
    if tab_title == '' then
      tab_title = symbols.unnamed
    end

    -- handle readonly
    local cur_readonly = vim.api.nvim_get_option_value(
      'readonly',
      { buf = cur_bufnr }
    ) or (not vim.api.nvim_get_option_value(
      'modifiable',
      { buf = cur_bufnr }
    ))

    -- add this tab to string
    tabline = tabline
      .. tab_var
      .. zoom_hl_var
      .. ' '
      .. (tab_zoomed and '▣ ' or '')
      .. hl_var
      .. (tab_title or '-')
      .. readonly_hl_var
      .. (cur_readonly and (' ' .. symbols.readonly) or '')
      .. mod_hl_var
      .. (has_modified and (' ' .. (cur_modified and symbols.modified or '+')) or '')
      .. ' '
  end

  -- fill remaining space, reset tab number, add close button
  tabline = tabline .. '%#TabLineFill#%T%=%#LpkeTabLineClose#%999X✖ '

  return tabline
end
