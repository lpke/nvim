-- Custom UI for codecompanion's ask_questions tool.
--
-- Replaces the default vim.ui.select calls (which go through dressing →
-- Telescope and truncate long text) with a purpose-built Telescope picker
-- that wraps the question text in the preview pane and shows full option
-- descriptions.

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')

local fmt = string.format

--- Build preview lines for a given question + currently highlighted option.
---@param question table  The question object from the LLM
---@param opt table|nil   The currently selected option (has .label, .description, .recommended)
---@return string[]       Lines to display in the preview buffer
local function build_preview_lines(question, opt)
  local lines = {}

  -- Question heading
  table.insert(lines, '── Question ──')
  table.insert(lines, '')

  -- Word-wrap the question text at ~72 columns
  for _, paragraph in ipairs(vim.split(question.question, '\n', { plain = true })) do
    local wrapped = vim.split(
      vim.fn.trim(paragraph) ~= '' and paragraph or '',
      '\n',
      { plain = true }
    )
    -- Use Neovim's built-in text wrapping via strdisplaywidth
    for _, line in ipairs(wrapped) do
      if #line <= 72 then
        table.insert(lines, line)
      else
        -- manual word-wrap
        local current = ''
        for word in line:gmatch('%S+') do
          if #current + #word + 1 > 72 then
            table.insert(lines, current)
            current = word
          else
            current = current == '' and word or (current .. ' ' .. word)
          end
        end
        if current ~= '' then
          table.insert(lines, current)
        end
      end
    end
  end

  if opt then
    table.insert(lines, '')
    table.insert(lines, '── Selected Option ──')
    table.insert(lines, '')
    table.insert(lines, opt.label)
    if opt.recommended then
      table.insert(lines, '  (recommended)')
    end
    if opt.description and opt.description ~= '' then
      table.insert(lines, '')
      -- Wrap the description the same way
      local desc_line = opt.description
      if #desc_line <= 72 then
        table.insert(lines, desc_line)
      else
        local current = ''
        for word in desc_line:gmatch('%S+') do
          if #current + #word + 1 > 72 then
            table.insert(lines, current)
            current = word
          else
            current = current == '' and word or (current .. ' ' .. word)
          end
        end
        if current ~= '' then
          table.insert(lines, current)
        end
      end
    end
  end

  return lines
end

--- Present a single question via a custom Telescope picker.
---@param question table           The question object from the LLM
---@param callback fun(answer: string|nil)
local function ask_one(question, callback)
  local options = question.options

  -- No options → fall through to vim.ui.input (dressing handles this fine)
  if not options or #options == 0 then
    vim.ui.input({ prompt = question.question .. ': ' }, function(input)
      if input == nil or input == '' then
        callback(nil)
      else
        callback(input)
      end
    end)
    return
  end

  -- Build entries: each entry carries the full option table
  local entries = {}
  for _, opt in ipairs(options) do
    local display = opt.label
    if opt.recommended then
      display = display .. '  (recommended)'
    end
    if opt.description then
      display = display .. '  —  ' .. opt.description
    end
    table.insert(entries, {
      display = display,
      label = opt.label,
      opt = opt,
    })
  end

  if question.multiSelect then
    -- Multi-select: use confirm prompts (same as upstream – these are
    -- short Yes/No pickers so truncation isn't really an issue)
    local labels = {}
    local label_map = {}
    for _, e in ipairs(entries) do
      table.insert(labels, e.display)
      label_map[e.display] = e.label
    end
    local selected = {}
    local idx = 0
    local function next_option()
      idx = idx + 1
      if idx > #labels then
        if #selected == 0 then
          callback(nil)
        else
          callback(table.concat(selected, ', '))
        end
        return
      end
      local choice_label = labels[idx]
      local prompt_text =
        fmt('%s\n\nInclude \'%s\'?', question.question, label_map[choice_label])
      vim.ui.select({ 'Yes', 'No' }, { prompt = prompt_text }, function(choice)
        if choice == 'Yes' then
          table.insert(selected, label_map[choice_label])
        end
        next_option()
      end)
    end
    next_option()
    return
  end

  -- Single-select: custom Telescope picker with preview.
  -- Use vim.schedule_wrap + callback-swap pattern from telescope-ui-select
  -- to safely handle deferred window closing.
  local cb = vim.schedule_wrap(callback)

  pickers
    .new({}, {
      prompt_title = 'Question: '
        .. (
          #question.question > 60 and question.question:sub(1, 57) .. '...'
          or question.question
        ),
      results_title = 'Options',
      preview_title = 'Details',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.display,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = 'Details',
        define_preview = function(self, entry)
          local lines = build_preview_lines(question, entry.value.opt)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          -- Highlight headings
          local ns = vim.api.nvim_create_namespace('ask_q_preview')
          for i, line in ipairs(lines) do
            if line:match('^── .* ──$') then
              vim.api.nvim_buf_set_extmark(
                self.state.bufnr,
                ns,
                i - 1,
                0,
                { end_col = #line, hl_group = 'Title' }
              )
            end
          end
        end,
      }),
      layout_config = {
        horizontal = {
          width = 0.75,
          height = 0.5,
          preview_width = 0.5,
        },
      },
      wrap_results = true,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          -- Swap cb to a no-op before closing to prevent the
          -- close:enhance post-hook from firing the callback again.
          local chosen = cb
          cb = function() end
          actions.close(prompt_bufnr)
          if entry then
            chosen(entry.value.label)
          else
            chosen(nil)
          end
        end)
        actions.close:enhance({
          post = function()
            cb(nil)
          end,
        })
        return true
      end,
    })
    :find()
end

--- Ask all questions sequentially, collecting answers.
---@param questions table                          Array of question objects
---@param callback  fun(answers: table<string, string>)
local function ask_all(questions, callback)
  local answers = {}
  local idx = 0

  local function next_question()
    idx = idx + 1
    if idx > #questions then
      return callback(answers)
    end

    local question = questions[idx]
    ask_one(question, function(answer)
      if answer then
        answers[question.header] = answer
      else
        answers[question.header] = 'No answer provided'
      end
      next_question()
    end)
  end

  next_question()
end

--- Monkey-patch the ask_questions tool so it uses our custom UI.
--- Call this once after codecompanion.setup().
local function patch()
  local tool_module =
    require('codecompanion.interactions.chat.tools.builtin.ask_questions')

  -- Build a formatted response from collected answers (same as upstream)
  local function format_answers(questions, answers)
    local parts = {}
    for _, q in ipairs(questions) do
      local header = q.header
      local answer = answers[header]
      if answer then
        table.insert(parts, fmt('**%s**: %s', header, answer))
      end
    end
    return table.concat(parts, '\n')
  end

  -- Replace the first (and only) cmd function
  tool_module.cmds[1] = function(_self, args, input)
    local questions = args.questions
    if not questions or #questions == 0 then
      return { status = 'error', data = 'No questions provided' }
    end

    vim.schedule(function()
      ask_all(questions, function(answers)
        local response = format_answers(questions, answers)
        if response == '' then
          response = 'The user did not provide any answers'
        end
        input.output_cb({ status = 'success', data = response })
      end)
    end)
  end
end

return { patch = patch }
