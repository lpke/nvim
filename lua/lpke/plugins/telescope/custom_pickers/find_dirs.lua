local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local sorters = require('telescope.sorters')
local make_entry = require('telescope.make_entry')
local config_values = require('telescope.config').values

local find_dirs = function(opts)
  opts = opts or {}
  opts.cwd = opts.cwd or vim.fn.getcwd(-1, -1)

  -- local finder = finders.new_async_job({
  --   cwd = opts.cwd,
  --   -- What the entry in the results list should show
  --   -- (using a telescope-provided helper for grepping)
  --   entry_maker = make_entry.gen_from_vimgrep(opts),
  --   -- Expects a table list of arg pieces for the command to be run
  --   -- eg: { 'rg', '-e', 'hello', '-g', '*.lua', '--color=never', ...}
  --   command_generator = function(prompt)
  --     if not prompt or prompt == '' then
  --       return nil
  --     end
  --
  --     -- will hold all parts of the command to be run
  --     local args = { 'rg' }
  --
  --     -- get inputs from the prompt
  --     local prompt_pieces = vim.split(prompt, '  ')
  --     local search_str = prompt_pieces[1]
  --     local filter_str = prompt_pieces[2]
  --
  --     -- add inputs to the command
  --     if search_str then
  --       table.insert(args, '-e')
  --       table.insert(args, search_str)
  --     end
  --     if filter_str then
  --       table.insert(args, '-g')
  --       table.insert(args, filter_str)
  --     end
  --
  --     -- add ripgrep options to the command
  --     vim.list_extend(args, {
  --       '--color=never',
  --       '--no-heading',
  --       '--with-filename',
  --       '--line-number',
  --       '--column',
  --       '--smart-case',
  --     })
  --
  --     return args
  --   end,
  -- })
  --
  -- pickers
  --   .new(opts, {
  --     prompt_title = 'Find in Filtered Files',
  --     initial_mode = 'insert',
  --     finder = finder,
  --     debounce = 100, -- for performance / less spam
  --     previewer = config_values.grep_previewer(opts),
  --     sorter = sorters.highlighter_only(opts), -- highlight in results
  --   })
  --   :find()
end

return find_dirs
