-- https://www.youtube.com/watch?v=xdXE1tOT-qg

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local sorters = require('telescope.sorters')
local make_entry = require('telescope.make_entry')
local config_values = require('telescope.config').values
local ts_helpers = require('lpke.plugins.telescope.helpers')
local ignore = require('lpke.plugins.telescope.ignore')

local live_multigrep = function(opts)
  opts = opts or {}
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
