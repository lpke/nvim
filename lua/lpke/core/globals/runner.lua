local helpers = require('lpke.core.helpers')

local filetype_commands = {
  javascript = 'node',
  js = 'node',
  typescript = 'ts-node',
  ts = 'ts-node',
  python = 'python3',
  lua = 'lua',
  sh = 'bash',
  bash = 'bash',
  zsh = 'zsh',
  ruby = 'ruby',
  go = 'go run',
  rust = 'cargo run',
  php = 'php',
  perl = 'perl',
  -- stylua: ignore start
    html = 'node -e "' ..
      'let jsdom; ' ..
      'try { ' ..
        'jsdom = require(\'jsdom\'); ' ..
      '} catch (e) { ' ..
        'console.error(\'[HTML Runner Error] jsdom module not found. Install with: npm install -g jsdom\'); ' ..
        'process.exit(1); ' ..
      '} ' ..
      'const { JSDOM } = jsdom; ' ..
      'const fs = require(\'fs\'); ' ..
      'const html = fs.readFileSync(process.argv[1], \'utf8\'); ' ..
      'const dom = new JSDOM(html, { ' ..
        'runScripts: \'dangerously\', ' ..
        'resources: \'usable\', ' ..
        'pretendToBeVisual: true ' ..
      '}); ' ..
      'const originalConsole = { ' ..
        'log: console.log, ' ..
        'error: console.error, ' ..
        'warn: console.warn, ' ..
        'info: console.info ' ..
      '}; ' ..
      'dom.window.console.log = (...args) => originalConsole.log(\'[HTML Console]\', ...args); ' ..
      'dom.window.console.error = (...args) => originalConsole.error(\'[HTML Console]\', ...args); ' ..
      'dom.window.console.warn = (...args) => originalConsole.warn(\'[HTML Console]\', ...args); ' ..
      'dom.window.console.info = (...args) => originalConsole.info(\'[HTML Console]\', ...args); ' ..
      'dom.window.addEventListener(\'error\', (e) => { ' ..
        'originalConsole.error(\'[HTML Error]\', e.error?.message || e.message); ' ..
      '}); ' ..
      'setTimeout(() => process.exit(0), 1000);"',
  -- stylua: ignore end
}

-- Global variable to track runner output buffer
Lpke_run_buf_output_buf = nil
-- Global function to run current buffer
function Lpke_run_buf()
  local current_buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[current_buf].filetype

  -- Check if filetype is supported
  local command = filetype_commands[filetype]
  if not command then
    vim.notify(
      'No runner configured for filetype: '
        .. (filetype and filetype ~= '' and filetype or '-'),
      vim.log.levels.WARN
    )
    return
  end

  -- Check if buffer is a saved file
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  local is_modified = vim.bo[current_buf].modified
  local use_temp_file = true
  local file_to_run = ''
  local temp_file = nil

  -- Use source file if it's saved and has a valid path
  if
    buf_name ~= ''
    and not is_modified
    and vim.fn.filereadable(buf_name) == 1
  then
    use_temp_file = false
    file_to_run = buf_name
  else
    -- Create temporary file for unsaved/modified buffers
    use_temp_file = true
    temp_file = vim.fn.tempname()
    file_to_run = temp_file

    -- Get buffer contents and write to temp file
    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    local content = table.concat(lines, '\n')

    local file = io.open(temp_file, 'w')
    if not file then
      vim.notify('Failed to create temporary file', vim.log.levels.ERROR)
      return
    end
    file:write(content)
    file:close()
  end

  local output_buf
  local output_win

  -- Check if output buffer already exists and is valid
  if
    Lpke_run_buf_output_buf
    and vim.api.nvim_buf_is_valid(Lpke_run_buf_output_buf)
  then
    output_buf = Lpke_run_buf_output_buf

    -- Find window displaying the buffer or create new split
    local buf_wins = vim.fn.win_findbuf(output_buf)
    if #buf_wins > 0 then
      output_win = buf_wins[1]
      vim.api.nvim_set_current_win(output_win)
    else
      vim.cmd('botright split')
      output_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(output_win, output_buf)
      vim.api.nvim_win_set_height(output_win, 15)
    end

    -- Clear existing content
    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {})
  else
    -- Create new output buffer
    output_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = output_buf })
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = output_buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = output_buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = output_buf })
    vim.api.nvim_set_option_value(
      'filetype',
      'runner-output',
      { buf = output_buf }
    )

    -- Create bottom split and show output buffer
    vim.cmd('botright split')
    output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(output_win, output_buf)
    vim.api.nvim_win_set_height(output_win, 15)

    -- Set buffer name
    vim.api.nvim_buf_set_name(output_buf, '[Runner Output]')

    -- Store buffer reference and set up cleanup autocmd
    Lpke_run_buf_output_buf = output_buf
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = output_buf,
      once = true,
      callback = function()
        Lpke_run_buf_output_buf = nil
      end,
    })
  end

  -- Add initial content
  local run_info = use_temp_file
      and 'Running: `' .. command .. ' ' .. temp_file .. '` (temp file)'
    or 'Running: `' .. command .. ' ' .. file_to_run .. '`'
  vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {
    run_info,
    '',
  })

  -- Build full command
  local full_command = command .. ' ' .. vim.fn.shellescape(file_to_run)

  -- Set up environment for Node.js commands to access global modules
  local env = vim.fn.environ()
  if filetype == 'html' then
    -- Get global npm modules path and set NODE_PATH
    local npm_global_path = vim.fn.system('npm root -g'):gsub('\n', '')
    env.NODE_PATH = npm_global_path
  end

  -- Run command and capture output
  vim.fn.jobstart(full_command, {
    env = env,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          -- Filter out empty strings
          local filtered_data = vim.tbl_filter(function(line)
            return line ~= ''
          end, data)

          if #filtered_data > 0 then
            local line_count = vim.api.nvim_buf_line_count(output_buf)
            vim.api.nvim_buf_set_lines(
              output_buf,
              line_count,
              line_count,
              false,
              filtered_data
            )

            -- Auto-scroll to bottom if window is still valid
            if vim.api.nvim_win_is_valid(output_win) then
              vim.api.nvim_win_set_cursor(
                output_win,
                { vim.api.nvim_buf_line_count(output_buf), 0 }
              )
            end
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          -- Filter out empty strings
          local filtered_data = vim.tbl_filter(function(line)
            return line ~= ''
          end, data)

          if #filtered_data > 0 then
            -- Add stderr prefix to distinguish from stdout
            local prefixed_data = vim.tbl_map(function(line)
              return '[STDERR] ' .. line
            end, filtered_data)

            local line_count = vim.api.nvim_buf_line_count(output_buf)
            vim.api.nvim_buf_set_lines(
              output_buf,
              line_count,
              line_count,
              false,
              prefixed_data
            )

            -- Auto-scroll to bottom if window is still valid
            if vim.api.nvim_win_is_valid(output_win) then
              vim.api.nvim_win_set_cursor(
                output_win,
                { vim.api.nvim_buf_line_count(output_buf), 0 }
              )
            end
          end
        end)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        local line_count = vim.api.nvim_buf_line_count(output_buf)
        vim.api.nvim_buf_set_lines(output_buf, line_count, line_count, false, {
          '',
          'Process exited with code: ' .. exit_code,
        })

        -- Auto-scroll to bottom if window is still valid
        if vim.api.nvim_win_is_valid(output_win) then
          vim.api.nvim_win_set_cursor(
            output_win,
            { vim.api.nvim_buf_line_count(output_buf), 0 }
          )
        end

        -- Clean up temporary file only if one was created
        if use_temp_file and temp_file then
          vim.fn.delete(temp_file)
        end
      end)
    end,
  })

  -- Return focus to original window
  vim.cmd('wincmd p')
end

-- Global function to close runner output buffer
function Lpke_close_run_output()
  if
    Lpke_run_buf_output_buf
    and vim.api.nvim_buf_is_valid(Lpke_run_buf_output_buf)
  then
    -- Find all windows displaying the output buffer
    local buf_wins = vim.fn.win_findbuf(Lpke_run_buf_output_buf)

    -- Close all windows displaying the buffer
    for _, win_id in ipairs(buf_wins) do
      if vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, false)
      end
    end

    -- Clear the global reference
    Lpke_run_buf_output_buf = nil
  end
end


-- stylua: ignore start
helpers.keymap_set_multi({
  { 'n', '<BS>rr', Lpke_run_buf, { desc = 'Run the current buffer code and show output' } },
  { 'n', '<BS>rx', Lpke_close_run_output, { desc = 'Close the runner output buffer' } },
})
-- stylua: ignore end
