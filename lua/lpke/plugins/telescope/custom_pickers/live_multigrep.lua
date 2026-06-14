-- https://www.youtube.com/watch?v=xdXE1tOT-qg

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local sorters = require('telescope.sorters')
local make_entry = require('telescope.make_entry')
local config_values = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local ts_helpers = require('lpke.plugins.telescope.helpers')
local ignore = require('lpke.plugins.telescope.ignore')

local function switch_to_file_picker(prompt_bufnr, initial_mode, toggle_target)
  local smart_find_ai = require('lpke.plugins.telescope.smart_find_ai')
  local current_picker = action_state.get_current_picker(prompt_bufnr)
  local current_query = current_picker:_get_prompt()
  local target_func = toggle_target == 'directories'
      and smart_find_ai.find_directories
    or smart_find_ai.find_files
  local opts = ts_helpers.telescope_file_grep_toggle_opts({
    initial_mode = initial_mode,
    default_text = current_query,
  }, toggle_target)

  if current_picker.cwd then
    opts.cwd = current_picker.cwd
  end

  actions.close(prompt_bufnr)
  target_func(opts)
end

local live_multigrep = function(opts)
  opts = opts or {}
  ts_helpers.telescope_file_grep_toggle_opts(opts)
  opts.cwd = ts_helpers.normalize_cwd(opts.cwd or vim.fn.getcwd())

  local parsed_prompt = ts_helpers.parse_multigrep_prompt('', opts.cwd)
  opts.on_input_filter_cb = function(prompt)
    parsed_prompt = ts_helpers.parse_multigrep_prompt(prompt, opts.cwd)
    return { prompt = parsed_prompt.search }
  end

  local finder = finders.new_async_job({
    cwd = opts.cwd,
    -- What the entry in the results list should show
    -- (using a telescope-provided helper for grepping)
    entry_maker = make_entry.gen_from_vimgrep(opts),
    -- Expects a table list of arg pieces for the command to be run
    -- eg: { 'rg', '-e', 'hello', '-g', '*.lua', '--color=never', ...}
    command_generator = function(search_str)
      if not search_str or search_str == '' or not parsed_prompt.valid_cwd then
        return nil
      end

      local args = { 'rg' }
      if opts.fixed_strings then
        table.insert(args, '--fixed-strings')
      end
      vim.list_extend(args, { '-e', search_str })

      for _, glob in ipairs(parsed_prompt.globs) do
        table.insert(args, '-g')
        table.insert(args, glob)
      end

      if parsed_prompt.unrestricted then
        vim.list_extend(args, ignore.rg_grep_args(true))
      else
        vim.list_extend(args, ignore.rg_grep_args(false))
      end

      if parsed_prompt.has_cwd_arg then
        vim.list_extend(args, {
          '--',
          parsed_prompt.path_arg,
        })
      end

      return args
    end,
  })

  local original_attach_mappings = opts.attach_mappings
  opts.attach_mappings = function(prompt_bufnr, map)
    if original_attach_mappings then
      original_attach_mappings(prompt_bufnr, map)
    end

    local toggle_target = ts_helpers.telescope_file_grep_toggle_target(opts)
    map('i', '<A-/>', function()
      switch_to_file_picker(prompt_bufnr, 'insert', toggle_target)
    end)
    map('n', '<A-/>', function()
      switch_to_file_picker(prompt_bufnr, 'normal', toggle_target)
    end)
    return true
  end

  pickers
    .new(opts, {
      prompt_title = 'Find in Filtered Files',
      initial_mode = 'insert',
      finder = finder,
      debounce = 50,
      previewer = config_values.grep_previewer(opts),
      sorter = sorters.highlighter_only(opts), -- highlight in results
    })
    :find()
end

return live_multigrep
