local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
local helpers = require('lpke.core.helpers')

local M = {}

function M.setup()
  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'in', '<A-f>', chat_fns.toggle_cc_with_default_tools, { desc = 'CodeCompanion: Toggle chat buffer with default tools' }},
    { 'in', '<F2>f', chat_fns.toggle_cc_with_default_tools, { desc = 'CodeCompanion: Toggle chat buffer with default tools' }},
    { 'in', '<A-F>', chat_fns.open_new_chat_with_tools, { desc = 'CodeCompanion: Open new chat with default tools' }},
    { 'in', '<F2>F', chat_fns.open_new_chat_with_tools, { desc = 'CodeCompanion: Open new chat with default tools' }},
    { 'v', '<A-f>', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<F2>f', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<A-F>', chat_fns.open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'v', '<F2>F', chat_fns.open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'ni', '<C-l>', chat_fns.open_inline_prompt_with_context, { desc = 'CodeCompanion: Open inline prompt with context' }},
    { 'v', '<C-l>', ":<C-u>'<,'>CodeCompanion<cr>#{buffer} ", { desc = 'CodeCompanion: Open inline prompt with context and selection' }},
  })
  helpers.ft_keymap_set_multi('codecompanion', {
    { 'n', '<leader>m', function() Lpke_cc_model({ 'son', 'gpt' }) end,
      { desc = 'CodeCompanion: Cycle between AI models' }},
    { 'in', '<A-a>', function() vim.api.nvim_put({'@{agent} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<F2>a', function() vim.api.nvim_put({'@{agent} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<A-A>', function() vim.api.nvim_put({'@{agent} @{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<F2>A', function() vim.api.nvim_put({'@{agent} @{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<A-S>', function() vim.api.nvim_put({'@{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<F2>S', function() vim.api.nvim_put({'@{web_search} @{fetch_webpage} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<A-b>', function() vim.api.nvim_put({'#{buffer} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<F2>b', function() vim.api.nvim_put({'#{buffer} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<A-B>', function() vim.api.nvim_put({'#{buffers} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert all buffers context' }},
    { 'in', '<F2>B', function() vim.api.nvim_put({'#{buffers} '}, 'c', vim.fn.mode() == 'n', true) end,
      { desc = 'CodeCompanion: Insert all buffers context' }},
  })
  helpers.command_set_multi({
    { '*', 'Model', function(cmd)
      if #cmd.fargs == 0 then
        print(':Model <model1> [<model2>...] | eg: son|opus|gpt|gem|<exact>')
      else
        Lpke_cc_model(cmd.fargs)
      end
    end, { desc = 'CodeCompanion: Swap to (or between) models' } },
  })
  -- stylua: ignore end
end

return M
