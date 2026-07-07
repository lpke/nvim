local function config()
  local apidocs = require('lpke.local_plugins_src.apidocs.api')
  local apidocs_common = require('lpke.local_plugins_src.apidocs.common')
  local apidocs_telescope = require('lpke.local_plugins_src.apidocs.telescope')
  local next_open_default_text = nil
  local next_search_default_text = nil

  local function with_keymap_buf_alias(fn)
    return function(...)
      local original_keymap_set = vim.keymap.set

      rawset(vim.keymap, 'set', function(mode, lhs, rhs, opts)
        if opts and opts.buf ~= nil and opts.buffer == nil then
          opts = vim.tbl_extend('force', {}, opts, { buffer = opts.buf })
          opts.buf = nil
        end

        return original_keymap_set(mode, lhs, rhs, opts)
      end)

      local ok, result = pcall(fn, ...)
      rawset(vim.keymap, 'set', original_keymap_set)

      if not ok then
        error(result, 2)
      end
      return result
    end
  end

  local function with_telescope_insert_mode(fn)
    return function(...)
      local pickers = require('telescope.pickers')
      local builtin = require('telescope.builtin')
      local original_new = pickers.new
      local original_live_grep = builtin.live_grep

      local function with_toggle_mapping(kind, original_attach)
        return function(prompt_bufnr, map)
          local original_result = true
          if original_attach then
            original_result = original_attach(prompt_bufnr, map)
            if original_result == false then
              return false
            end
          end

          local function toggle()
            local actions = require('telescope.actions')
            local action_state = require('telescope.actions.state')
            local prompt = action_state.get_current_line()

            actions.close(prompt_bufnr)
            vim.schedule(function()
              if kind == 'open' then
                next_search_default_text = prompt
                require('lpke.local_plugins_src.apidocs.api').apidocs_search({ picker = 'telescope' })
              else
                next_open_default_text = prompt
                require('lpke.local_plugins_src.apidocs.api').apidocs_open({ picker = 'telescope' })
              end
            end)
          end

          map('i', '<A-s>', toggle, { desc = 'API docs: Toggle picker mode' })
          map('n', '<A-s>', toggle, { desc = 'API docs: Toggle picker mode' })

          return true
        end
      end

      pickers.new = function(opts, picker_opts)
        if picker_opts and picker_opts.prompt_title == 'API docs' then
          picker_opts.initial_mode = 'insert'
          picker_opts.default_text = next_open_default_text
            or picker_opts.default_text
          next_open_default_text = nil
          picker_opts.attach_mappings =
            with_toggle_mapping('open', picker_opts.attach_mappings)
        end
        return original_new(opts, picker_opts)
      end

      builtin.live_grep = function(opts)
        if opts and opts.prompt_title == 'API docs search' then
          opts.initial_mode = 'insert'
          opts.default_text = next_search_default_text or opts.default_text
          next_search_default_text = nil
          opts.attach_mappings =
            with_toggle_mapping('search', opts.attach_mappings)
        end
        return original_live_grep(opts)
      end

      local ok, result = pcall(fn, ...)
      pickers.new = original_new
      builtin.live_grep = original_live_grep

      if not ok then
        error(result, 2)
      end
      return result
    end
  end

  apidocs_telescope.apidocs_open = with_telescope_insert_mode(
    with_keymap_buf_alias(apidocs_telescope.apidocs_open)
  )
  apidocs_telescope.apidocs_search = with_telescope_insert_mode(
    with_keymap_buf_alias(apidocs_telescope.apidocs_search)
  )
  apidocs_common.open_doc_in_cur_window =
    with_keymap_buf_alias(apidocs_common.open_doc_in_cur_window)
  apidocs_common.open_doc_in_new_window =
    with_keymap_buf_alias(apidocs_common.open_doc_in_new_window)

  apidocs.setup({
    picker = 'telescope',
  })
end

local function init()
  local helpers = require('lpke.core.helpers')

  helpers.keymap_set_multi({
    {
      'nC',
      '<BS>fa',
      'ApidocsOpen',
      { desc = 'API docs: Open docs picker' },
    },
    {
      'nC',
      '<BS>fA',
      'ApidocsSearch',
      { desc = 'API docs: Search installed docs' },
    },
  })
end

return {
  name = 'apidocs-local',
  dir = vim.fn.stdpath('config'),
  init = init,
  cmd = {
    'ApidocsInstall',
    'ApidocsOpen',
    'ApidocsSearch',
    'ApidocsSelect',
    'ApidocsUninstall',
  },
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-telescope/telescope.nvim',
  },
  config = config,
}
