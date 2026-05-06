local helpers = require('lpke.core.helpers')

local runner_config = {
  javascript = {
    run_command = 'node',
    dependencies = { 'node' },
    temp_file_extension = 'js',
  },
  js = {
    run_command = 'node',
    dependencies = { 'node' },
    temp_file_extension = 'js',
  },
  typescript = {
    run_command = 'tsx',
    dependencies = { 'tsx' },
    temp_file_extension = 'ts',
  },
  ts = {
    run_command = 'tsx',
    dependencies = { 'tsx' },
    temp_file_extension = 'ts',
  },
  python = {
    run_command = 'python3',
    dependencies = { 'python3' },
    temp_file_extension = 'py',
  },
  lua = {
    run_command = 'lua',
    dependencies = { 'lua' },
    temp_file_extension = 'lua',
  },
  sh = {
    run_command = 'bash',
    dependencies = { 'bash' },
    temp_file_extension = 'sh',
  },
  bash = {
    run_command = 'bash',
    dependencies = { 'bash' },
    temp_file_extension = 'bash',
  },
  zsh = {
    run_command = 'zsh',
    dependencies = { 'zsh' },
    temp_file_extension = 'zsh',
  },
  ruby = {
    run_command = 'ruby',
    dependencies = { 'ruby' },
    temp_file_extension = 'rb',
  },
  go = {
    run_command = 'go run',
    dependencies = { 'go' },
    temp_file_extension = 'go',
  },
  rust = {
    run_command = 'cargo run',
    dependencies = { 'cargo' },
    temp_file_extension = 'rs',
  },
  php = {
    run_command = 'php',
    dependencies = { 'php' },
    temp_file_extension = 'php',
  },
  perl = {
    run_command = 'perl',
    dependencies = { 'perl' },
    temp_file_extension = 'pl',
  },
  -- stylua: ignore start
  html = {
    run_command = 'node -e "' ..
      'let jsdom; ' ..
      'try { ' ..
        'jsdom = require(\'jsdom\'); ' ..
      '} catch (e) { ' ..
        'console.error(\'[Runner] \\`jsdom\\` module not found. Install with: \\`npm install -g jsdom\\`\'); ' ..
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
    dependencies = { 'node' },
    temp_file_extension = 'html',
  },
  -- stylua: ignore end
}

-- Function to check if jsdom is available
local function check_jsdom_availability(env)
  local check_command =
    "node -e \"try { require('jsdom'); console.log('OK'); } catch (e) { console.error('ERROR'); process.exit(1); }\""

  -- Run the check synchronously
  local result = vim.fn.system({
    'bash',
    '-c',
    'NODE_PATH=' .. (env.NODE_PATH or '') .. ' ' .. check_command,
  })

  -- Check if the command succeeded and returned "OK"
  return result:match('OK') ~= nil
end

-- Function to check if a command is available in PATH
local function check_command_availability(cmd)
  -- Extract just the command name (remove arguments like "go run" -> "go")
  local command_name = cmd:match('^(%S+)')
  if not command_name then
    return false
  end
  -- Use 'which' command to check if it exists in PATH
  local result = vim.fn.system(
    'which ' .. vim.fn.shellescape(command_name) .. ' 2>/dev/null'
  )
  return vim.v.shell_error == 0 and result:match('%S') ~= nil
end

-- Global variable to track runner output buffer
Lpke_run_buf_output_buf = nil
-- Global function to run current buffer
function Lpke_run_buf()
  local current_buf = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[current_buf].filetype

  -- Check if filetype is supported
  local config = runner_config[filetype]
  if not config then
    vim.notify(
      'Runner: No command configured for filetype: '
        .. (filetype and filetype ~= '' and filetype or '-'),
      vim.log.levels.ERROR
    )
    return
  end

  local command = config.run_command
  local dependencies = config.dependencies or {}

  -- Check if the required dependencies are available
  for _, dep in ipairs(dependencies) do
    if not check_command_availability(dep) then
      vim.notify(
        'Runner: Command `'
          .. dep
          .. '` is required to run `'
          .. filetype
          .. '` files',
        vim.log.levels.ERROR
      )
      return
    end
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
    if config.temp_file_extension then
      temp_file = temp_file .. '.' .. config.temp_file_extension
    end
    file_to_run = temp_file

    -- Get buffer contents and write to temp file
    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    local content = table.concat(lines, '\n')

    local file = io.open(temp_file, 'w')
    if not file then
      vim.notify(
        'Runner: Failed to create temporary file',
        vim.log.levels.ERROR
      )
      return
    end
    file:write(content)
    file:close()
  end

  -- Set up environment for Node.js commands and check dependencies early
  local env = vim.fn.environ()
  if filetype == 'html' then
    -- Get global npm modules path and set NODE_PATH
    local npm_global_path = vim.fn.system('npm root -g'):gsub('\n', '')
    env.NODE_PATH = npm_global_path

    -- Check if jsdom is available before proceeding
    if not check_jsdom_availability(env) then
      vim.notify(
        'Runner: `jsdom` node module not found. Install with: `npm install -g jsdom`',
        vim.log.levels.ERROR
      )
      -- Clean up temporary file if one was created
      if use_temp_file and temp_file then
        vim.fn.delete(temp_file)
      end
      return
    end
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
      vim.api.nvim_win_set_height(output_win, 20)
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
    vim.api.nvim_win_set_height(output_win, 20)

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
