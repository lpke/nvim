local chat_fns = require('lpke.plugins.ai.helpers.chat_functions')
local helpers = require('lpke.core.helpers')
local ai_config = require('lpke.plugins.ai.helpers.config')
local models = require('lpke.plugins.ai.helpers.model_swap')
local acp_session_options =
  require('lpke.plugins.ai.helpers.acp_session_options')
local cleanup = require('lpke.plugins.ai.helpers.cleanup')
local codex_threads = require('lpke.plugins.ai.helpers.codex_threads')
local chat_history = require('lpke.plugins.ai.helpers.chat_history')
local img_clip = require('lpke.plugins.ai.helpers.img_clip')

local M = {}

function M.setup()
  chat_fns.setup_source_buffer_tracking()

  -- stylua: ignore start
  helpers.keymap_set_multi({
    { 'in', '<A-f>', chat_fns.toggle_chat, { desc = 'CodeCompanion: Toggle chat buffer' }},
    { 'in', '<F2>f', chat_fns.toggle_chat, { desc = 'CodeCompanion: Toggle chat buffer' }},
    { 'in', '<A-F>', chat_fns.open_fullscreen_chat, { desc = 'CodeCompanion: Open fullscreen chat tab' }},
    { 'in', '<F2>F', chat_fns.open_fullscreen_chat, { desc = 'CodeCompanion: Open fullscreen chat tab' }},
    { 'v', '<A-f>', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<F2>f', chat_fns.toggle_chat_with_context_selection, { desc = 'CodeCompanion: Toggle chat buffer, add context and selection' }},
    { 'v', '<A-F>', chat_fns.open_fullscreen_chat_with_context_selection, { desc = 'CodeCompanion: Open fullscreen chat tab with selection' }},
    { 'v', '<F2>F', chat_fns.open_fullscreen_chat_with_context_selection, { desc = 'CodeCompanion: Open fullscreen chat tab with selection' }},
    { 'ni', '<C-l>', chat_fns.open_inline_prompt_with_context, { desc = 'CodeCompanion: Open inline prompt with context' }},
    { 'v', '<C-l>', function() chat_fns.open_inline_prompt_with_context({ visual = true }) end, { desc = 'CodeCompanion: Open inline prompt with context and selection' }},
  })
  helpers.ft_keymap_set_multi('codecompanion', {
    { 'n', '<leader>m', function() models.select(ai_config.adapter_model_cycle(models.get_cur_adapter(0))) end,
      { desc = 'CodeCompanion: Cycle models' }},
    { 'n', '<leader>M', function() models.cycle_adapters(ai_config.adapter_cycle) end,
      { desc = 'CodeCompanion: Cycle adapters' }},
    { 'n', '<leader>r', acp_session_options.show_reasoning,
      { desc = 'CodeCompanion: ACP reasoning effort' }},
    { 'n', '<leader>a', acp_session_options.show_approval,
      { desc = 'CodeCompanion: ACP approval preset' }},
    { 'n', '<leader>X', cleanup.open,
      { desc = 'CodeCompanion: Cleanup chats' }},
    { 'n', 'gA', function() codex_threads.toggle() end,
      { desc = 'CodeCompanion: Toggle current thread subagents' }},
    { 'n', 'go', function()
      chat_history.toggle(require('codecompanion').buf_get_chat(0))
    end,
      { desc = 'CodeCompanion: Toggle older chat history' }},
    { 'n!', '<leader>I', img_clip.paste_image,
      { desc = 'CodeCompanion: Save clipboard image and insert its path' }},
    { 'in', '<A-b>', chat_fns.insert_last_source_path,
      { desc = 'CodeCompanion: Insert last source buffer path' }},
    { 'in', '<F2>b', chat_fns.insert_last_source_path,
      { desc = 'CodeCompanion: Insert last source buffer path' }},
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
        print(':Model <model1> [<model2>...] | eg: son|opus|gpt|astra|sol|terra|luna|gem|<exact>')
      else
        models.select(cmd.fargs)
      end
    end, { desc = 'CodeCompanion: Swap to (or between) models' } },
    { '*', 'Adapter', function(cmd)
      if #cmd.fargs == 0 then print(':Adapter <adapter1> [<adapter2>...] | eg: codex|copilot')
      else models.cycle_adapters(cmd.fargs) end
    end, { desc = 'CodeCompanion: Swap to (or between) adapters' } },
    { '?', 'CodexAgents', codex_threads.command, {
      desc = 'CodeCompanion: Inspect local or Mac Codex subagents',
      complete = codex_threads.complete,
    } },
  })
  -- stylua: ignore end
end

return M
