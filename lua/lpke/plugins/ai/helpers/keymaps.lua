local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
local helpers = require('lpke.core.helpers')
local ai_config = require('lpke.plugins.ai.helpers.config')
local model_swap = require('lpke.plugins.ai.helpers.model_swap')

local M = {}

function M.setup()
  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'in', '<A-f>', chat_fns.toggle_cc_with_default_tools, { desc = 'CodeCompanion: Toggle chat buffer with HTTP tools' }},
    { 'in', '<F2>f', chat_fns.toggle_cc_with_default_tools, { desc = 'CodeCompanion: Toggle chat buffer with HTTP tools' }},
    { 'in', '<A-F>', chat_fns.open_new_chat_with_tools, { desc = 'CodeCompanion: Open new chat with HTTP tools' }},
    { 'in', '<F2>F', chat_fns.open_new_chat_with_tools, { desc = 'CodeCompanion: Open new chat with HTTP tools' }},
    { 'v', '<A-f>', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<F2>f', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<A-F>', chat_fns.open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'v', '<F2>F', chat_fns.open_new_chat_with_context_selection, { desc = 'CodeCompanion: Open a new chat buffer with context and selection' }},
    { 'ni', '<C-l>', chat_fns.open_inline_prompt_with_context, { desc = 'CodeCompanion: Open inline prompt with context' }},
    { 'v', '<C-l>', ":<C-u>'<,'>CodeCompanion<cr>#{buffer} ", { desc = 'CodeCompanion: Open inline prompt with context and selection' }},
  })
  helpers.ft_keymap_set_multi('codecompanion', {
    { 'n', '<leader>m', function()
      if model_swap.is_codex_chat(0) then
        Lpke_cc_model(ai_config.adapter_model_cycle('codex'))
      else
        Lpke_cc_model(ai_config.adapter_model_cycle('copilot'))
      end
    end,
      { desc = 'CodeCompanion: Cycle between AI models' }},
    { 'n', '<leader>M', function() Lpke_cc_adapter(ai_config.adapter_cycle) end,
      { desc = 'CodeCompanion: Cycle between AI adapters' }},
    { 'in', '<A-a>', function() chat_fns.insert_http_tool_text('@{agent} ') end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<F2>a', function() chat_fns.insert_http_tool_text('@{agent} ') end,
      { desc = 'CodeCompanion: Insert agent tool' }},
    { 'in', '<A-A>', function() chat_fns.insert_http_tool_text('@{agent} @{fetch_webpage} @{web_search} ') end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<F2>A', function() chat_fns.insert_http_tool_text('@{agent} @{fetch_webpage} @{web_search} ') end,
      { desc = 'CodeCompanion: Insert agent + web tools' }},
    { 'in', '<A-S>', function() chat_fns.insert_http_tool_text('@{fetch_webpage} @{web_search} ') end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<F2>S', function() chat_fns.insert_http_tool_text('@{fetch_webpage} @{web_search} ') end,
      { desc = 'CodeCompanion: Insert web tools' }},
    { 'in', '<A-b>', function() chat_fns.insert_context_text('#{buffer} ') end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<F2>b', function() chat_fns.insert_context_text('#{buffer} ') end,
      { desc = 'CodeCompanion: Insert buffer context' }},
    { 'in', '<A-d>', function() chat_fns.insert_context_text('#{diagnostics} ') end,
      { desc = 'CodeCompanion: Insert diagnostics context' }},
    { 'in', '<F2>d', function() chat_fns.insert_context_text('#{diagnostics} ') end,
      { desc = 'CodeCompanion: Insert diagnostics context' }},
    { 'in', '<A-B>', function() chat_fns.insert_context_text('#{buffers} ') end,
      { desc = 'CodeCompanion: Insert all buffers context' }},
    { 'in', '<F2>B', function() chat_fns.insert_context_text('#{buffers} ') end,
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
    { '*', 'Adapter', function(cmd)
      if #cmd.fargs == 0 then
        print(':Adapter <adapter1> [<adapter2>...] | eg: codex|copilot')
      else
        Lpke_cc_adapter(cmd.fargs)
      end
    end, { desc = 'CodeCompanion: Swap to (or between) adapters' } },
  })
  -- stylua: ignore end
end

return M
