local M = {}

local api = vim.api
local references = require('lpke.core.helpers.references')
local return_state_var = 'lpke_codecompanion_reference_jump'

local function return_state(tab)
  local ok, state = pcall(api.nvim_tabpage_get_var, tab, return_state_var)
  if ok and type(state) == 'table' then
    return state
  end
end

local function clear_return_state(tab)
  pcall(api.nvim_tabpage_del_var, tab, return_state_var)
end

local function source_is_live(state)
  return type(state.source_buf) == 'number'
    and type(state.source_tab) == 'number'
    and type(state.source_win) == 'number'
    and api.nvim_buf_is_valid(state.source_buf)
    and api.nvim_tabpage_is_valid(state.source_tab)
    and api.nvim_win_is_valid(state.source_win)
    and api.nvim_win_get_tabpage(state.source_win) == state.source_tab
    and api.nvim_win_get_buf(state.source_win) == state.source_buf
end

local function setup_return_handler()
  local group = api.nvim_create_augroup('LpkeCodeCompanionReferenceJump', {
    clear = true,
  })

  api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(event)
      local target_tab = api.nvim_get_current_tabpage()
      local state = return_state(target_tab)
      if not state or event.buf ~= state.source_buf then
        return
      end

      local jumps, jump_index = unpack(vim.fn.getjumplist())
      -- Neovim may deduplicate old entries, shifting the saved jump's index.
      if
        jump_index >= #jumps
        or not vim.deep_equal(jumps[jump_index + 1], state.return_jump)
      then
        clear_return_state(target_tab)
        return
      end

      local target_win = api.nvim_get_current_win()
      local target_is_unchanged = target_win == state.target_win
        and #api.nvim_tabpage_list_wins(target_tab) == 1
      if not target_is_unchanged or not source_is_live(state) then
        clear_return_state(target_tab)
        return
      end

      clear_return_state(target_tab)
      vim.schedule(function()
        if
          not api.nvim_tabpage_is_valid(target_tab)
          or api.nvim_get_current_tabpage() ~= target_tab
          or api.nvim_get_current_win() ~= target_win
          or api.nvim_get_current_buf() ~= state.source_buf
          or #api.nvim_tabpage_list_wins(target_tab) ~= 1
          or not source_is_live(state)
        then
          return
        end

        if
          pcall(vim.cmd.tabclose) and api.nvim_win_is_valid(state.source_win)
        then
          api.nvim_set_current_win(state.source_win)
        end
      end)
    end,
  })
end

setup_return_handler()

local function is_pasted_image(reference)
  local image_dir =
    vim.fs.normalize(require('lpke.plugins.ai.helpers.img_clip').dir_path())
  return vim.fs.dirname(reference.path) == image_dir
end

M.reference_at = references.reference_at

function M.open_under_cursor()
  if require('lpke.core.helpers').open_url_under_cursor() then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local reference =
    M.reference_at(vim.api.nvim_get_current_line(), cursor[2] + 1)
  if not reference then
    vim.notify(
      'CodeCompanion: no URL or readable file reference under cursor',
      vim.log.levels.INFO
    )
    return
  end

  if is_pasted_image(reference) then
    require('lpke.core.helpers').open_directory(vim.fs.dirname(reference.path))
    return
  end

  local source_buf = api.nvim_get_current_buf()
  local source_tab = api.nvim_get_current_tabpage()
  local source_win = api.nvim_get_current_win()
  local tab_count = #api.nvim_list_tabpages()
  local target_win = references.open_file_reference(reference, { tab = true })
  local target_tab = api.nvim_win_get_tabpage(target_win)

  if #api.nvim_list_tabpages() > tab_count then
    local jumps, jump_index = unpack(vim.fn.getjumplist(target_win))
    local return_jump = jumps[jump_index]
    if return_jump and return_jump.bufnr == source_buf then
      api.nvim_tabpage_set_var(target_tab, return_state_var, {
        source_buf = source_buf,
        source_tab = source_tab,
        source_win = source_win,
        target_win = target_win,
        return_jump = return_jump,
      })
    end
  elseif target_tab ~= source_tab then
    clear_return_state(target_tab)
  end
end

return M
