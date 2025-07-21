Lpke_messages_win_open = false
Lpke_messages_win_id = nil
Lpke_messages_buf_id = nil
function Lpke_toggle_messages()
  local function reset_messages_win_state()
    Lpke_messages_win_open = false
    Lpke_messages_win_id = nil
    Lpke_messages_buf_id = nil
  end

  local function format_content()
    vim.cmd('silent! /^\\s*$/,/\\S/-1delete _') -- remove all whitespace-only lines from the start of the file
    vim.cmd('silent! g/^\\d\\+ more lines$/d') -- remove "X more lines" lines (shouldn't happen but just in case)
    vim.cmd([[silent! g/^\s*$/s/.*/]]) -- replace whitespace-only lines with empty lines (for easier navigation)
    vim.cmd('normal! G') -- move cursor to bottom (most recent command)
  end

  local function update_messages_content()
    if
      Lpke_messages_buf_id and vim.api.nvim_buf_is_valid(Lpke_messages_buf_id)
    then
      vim.api.nvim_buf_set_lines(Lpke_messages_buf_id, 0, -1, false, {})
      vim.api.nvim_buf_call(Lpke_messages_buf_id, function()
        vim.cmd("silent! put =execute('messages')")
        format_content()
      end)
    end
  end

  -- ensure valid state values
  if
    (Lpke_messages_win_open or Lpke_messages_win_id or Lpke_messages_buf_id)
    and (
      not (Lpke_messages_win_id and Lpke_messages_buf_id)
      or not vim.api.nvim_win_is_valid(Lpke_messages_win_id)
    )
  then
    vim.notify(
      'Toggle messages window: State is invalid. Resetting state before proceeding.',
      vim.log.levels.WARN
    )
    reset_messages_win_state()
  end

  local cur_win = vim.api.nvim_get_current_win()

  -- if window is already open, update content and focus it
  if Lpke_messages_win_open and Lpke_messages_win_id then
    update_messages_content()
    vim.api.nvim_set_current_win(Lpke_messages_win_id)
    return
  end

  -- open messages window in new bottom split
  vim.cmd('botright new')
  vim.cmd(
    "silent! enew | silent! put =execute('messages') | silent! set nomodified buftype=nofile bufhidden=wipe"
  )
  format_content()
  Lpke_messages_win_open = true
  Lpke_messages_win_id = vim.api.nvim_get_current_win()
  Lpke_messages_buf_id = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(Lpke_messages_buf_id, 'Message History')
  vim.api.nvim_set_option_value(
    'filetype',
    'messages',
    { buf = Lpke_messages_buf_id }
  )

  -- handle messages window close
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = Lpke_messages_buf_id,
    callback = function()
      vim.schedule(function()
        -- focus previous window if possible
        if vim.api.nvim_win_is_valid(cur_win) then
          vim.api.nvim_set_current_win(cur_win)
        end
        reset_messages_win_state()
      end)
      return true -- cleanup
    end,
    desc = 'Return to original window when :Mes buffer is closed',
  })
end
