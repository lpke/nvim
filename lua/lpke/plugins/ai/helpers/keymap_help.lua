local M = {}

local mode_names = {
  n = 'Normal',
  i = 'Insert',
  v = 'Visual',
}

local mode_order = { 'n', 'i', 'v' }

local sections = {
  {
    title = 'Global Keymaps',
    keymaps = {
      {
        description = 'Toggle sidebar chat with HTTP tools',
        modes = { n = { '<A-f>', '<F2>f' }, i = { '<A-f>', '<F2>f' } },
      },
      {
        description = 'Toggle chat with selection and context',
        modes = { v = { '<A-f>', '<F2>f' } },
      },
      {
        description = 'Open fullscreen chat tab',
        modes = { n = { '<A-F>', '<F2>F' }, i = { '<A-F>', '<F2>F' } },
      },
      {
        description = 'Open fullscreen chat tab with selection',
        modes = { v = { '<A-F>', '<F2>F' } },
      },
      {
        description = 'Open inline prompt with context',
        modes = { n = '<C-l>', i = '<C-l>' },
      },
      {
        description = 'Open inline prompt with context and selection',
        modes = { v = '<C-l>' },
      },
    },
  },
  {
    title = 'Chat Buffer Keymaps',
    keymaps = {
      {
        description = 'Open file reference at its line and column',
        modes = { n = 'gd' },
      },
      { description = 'Cycle between AI models', modes = { n = '<leader>m' } },
      {
        description = 'Cycle between AI adapters',
        modes = { n = '<leader>M' },
      },
      {
        description = 'ACP reasoning effort',
        modes = { n = '<leader>r' },
      },
      {
        description = 'ACP approval preset',
        modes = { n = '<leader>a' },
      },
      { description = 'Cleanup chats', modes = { n = '<leader>X' } },
      { description = 'Paste image', modes = { n = '<leader>I' } },
      {
        description = 'Insert agent tool',
        modes = { n = { '<A-a>', '<F2>a' }, i = { '<A-a>', '<F2>a' } },
      },
      {
        description = 'Insert agent and web tools',
        modes = { n = { '<A-A>', '<F2>A' }, i = { '<A-A>', '<F2>A' } },
      },
      {
        description = 'Insert web tools',
        modes = { n = { '<A-S>', '<F2>S' }, i = { '<A-S>', '<F2>S' } },
      },
      {
        description = 'Insert last source path or Oil directory',
        modes = { n = { '<A-b>', '<F2>b' }, i = { '<A-b>', '<F2>b' } },
      },
      {
        description = 'Insert diagnostics context',
        modes = { n = { '<A-d>', '<F2>d' }, i = { '<A-d>', '<F2>d' } },
      },
      {
        description = 'Send and scroll submitted prompt to top',
        modes = { n = { '<CR>', '<C-s>' }, i = '<C-s>' },
      },
      {
        description = 'Insert all buffers context',
        modes = { n = { '<A-B>', '<F2>B' }, i = { '<A-B>', '<F2>B' } },
      },
    },
  },
  {
    title = 'History Picker Keymaps',
    keymaps = {
      {
        description = 'Saved Chats: rename saved chat',
        modes = { n = 'gr', i = '<M-r>' },
      },
      {
        description = 'Saved Chats: find in saved chats',
        modes = { n = '<A-s>', i = '<A-s>' },
      },
      {
        description = 'Find in Chats: return to saved chat list',
        modes = { n = '<A-s>', i = '<A-s>' },
      },
    },
  },
}

local function max_description_length()
  local max_length = 0
  for _, section in ipairs(sections) do
    for _, keymap in ipairs(section.keymaps) do
      max_length = math.max(max_length, #keymap.description)
    end
  end
  return max_length
end

local function pad(str, max_length)
  return str .. string.rep(' ', max_length - #str + 4)
end

local function format_keys(key)
  if type(key) == 'table' then
    return '`' .. table.concat(key, '|') .. '`'
  end
  return '`' .. key .. '`'
end

local function format_modes(modes)
  local output = {}

  for _, mode in ipairs(mode_order) do
    local key = modes[mode]
    if key then
      table.insert(
        output,
        format_keys(key) .. ' in ' .. mode_names[mode] .. ' mode'
      )
    end
  end

  return table.concat(output, ' and ')
end

function M.extra_lines()
  local lines = {
    '',
    '',
    '### LPKE Custom CodeCompanion Help',
  }
  local max_length = max_description_length()

  for _, section in ipairs(sections) do
    table.insert(lines, '')
    table.insert(lines, '#### ' .. section.title)

    for _, keymap in ipairs(section.keymaps) do
      table.insert(
        lines,
        ' '
          .. pad('_' .. keymap.description .. '_', max_length)
          .. ' '
          .. format_modes(keymap.modes)
      )
    end
  end

  return lines
end

local function insert_extra_lines(lines)
  local extended_lines = vim.deepcopy(lines)

  vim.list_extend(extended_lines, M.extra_lines())

  return extended_lines
end

function M.setup()
  local ok, keymaps = pcall(require, 'codecompanion.interactions.chat.keymaps')
  if not ok or not keymaps.options or keymaps.options._lpke_patched then
    return
  end

  local original_callback = keymaps.options.callback

  keymaps.options.callback = function(...)
    local config = require('codecompanion.config')
    local ui_utils = require('codecompanion.utils.ui')

    local options_config = config.interactions.chat.keymaps.options
    local original_hide = options_config and options_config.hide
    local original_create_float = ui_utils.create_float

    if options_config then
      options_config.hide = false
    end

    ui_utils.create_float = function(lines, opts)
      return original_create_float(insert_extra_lines(lines), opts)
    end

    local ok_callback, err = pcall(original_callback, ...)

    ui_utils.create_float = original_create_float
    if options_config then
      options_config.hide = original_hide
    end

    if not ok_callback then
      error(err)
    end
  end

  keymaps.options._lpke_patched = true
end

return M
