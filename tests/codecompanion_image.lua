-- run-nvim --headless -u NONE -l tests/codecompanion_image.lua
local h = dofile('tests/helpers/codecompanion_common.lua')
local api = vim.api
local config = require('codecompanion.config')
local chat = h.chat()
chat.adapter.opts.vision = true
api.nvim_set_current_buf(chat.bufnr)
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local png = root .. '/fixture.png'
local data = vim.base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aBv0AAAAASUVORK5CYII='
)
local handle = assert(io.open(png, 'wb'))
handle:write(data)
handle:close()
h.write(root .. '/not-image.txt', { 'not an image' })
local completion = require('codecompanion.providers.completion')
api.nvim_exec_autocmds('User', {
  pattern = 'CodeCompanionChatModel',
  data = {
    bufnr = chat.bufnr,
    adapter = require('codecompanion.adapters').make_safe(chat.adapter),
  },
})
local image_item
for _, item in ipairs(completion.slash_commands('chat')) do
  if item.label == '/image' then
    image_item = item
  end
end
h.check(image_item ~= nil, '/image remains in real slash completion')
h.equal(
  image_item.config.path,
  'lpke.plugins.ai.helpers.slash_image',
  '/image resolves to compatibility wrapper'
)
h.equal(
  image_item.config.opts.filetypes,
  { 'png', 'jpg', 'jpeg', 'gif', 'webp' },
  'original image types'
)
local picker, selected_action
package.loaded['telescope.builtin'] = {
  find_files = function(opts)
    picker = opts
    opts.attach_mappings()
  end,
}
package.loaded['telescope.actions'] = {
  close = function() end,
  select_default = {
    replace = function(_, fn)
      selected_action = fn
    end,
  },
}
package.loaded['telescope.actions.state'] = {
  get_selected_entry = function()
    return { path = png, value = png, [1] = png }
  end,
  get_current_picker = function()
    return {
      get_multi_selection = function()
        return {}
      end,
    }
  end,
}
local source_choice = 'File'
vim.ui.select = function(items, opts, callback)
  h.equal(items, { 'URL', 'File' }, 'original image source chooser')
  h.equal(opts.prompt, 'Select an image source', 'source chooser label')
  callback(source_choice)
end
local dispatcher = require('codecompanion.interactions.chat.slash_commands')
dispatcher.run(image_item, chat)
h.equal(picker.prompt_title, 'Images', 'original image picker title')
h.equal(
  picker.search_dirs,
  vim.list_extend({ vim.fn.getcwd() }, vim.deepcopy(h.slash.image.opts.dirs)),
  'cwd plus all four original image roots'
)
local extensions = {}
for i, token in ipairs(picker.find_command) do
  if token == '--extension' then
    extensions[#extensions + 1] = picker.find_command[i + 1]
  end
end
h.equal(
  extensions,
  image_item.config.opts.filetypes,
  'image-only fd search filters'
)
local before = #chat.messages
selected_action(999)
h.equal(
  #chat.messages,
  before + 1,
  'selected image attached once through native file helper'
)
local image = chat.messages[#chat.messages]
h.check(
  type(image.content) == 'string'
    and image.content:find('iVBOR', 1, true) ~= nil,
  'native image encoding reaches model context'
)
h.equal(image._meta.tag, 'image', 'native image tag')
h.equal(image.context.path, png, 'native image path metadata')

local original_download = require('codecompanion.utils.files').download
local downloads = 0
require('codecompanion.utils.files').download = function(url, opts)
  downloads = downloads + 1
  h.equal(url, 'https://fixture.test/image.png', 'image URL forwarded once')
  opts.callback(nil, { path = png, mimetype = 'image/png' })
end
source_choice = 'URL'
vim.ui.input = function(opts, callback)
  h.equal(opts.prompt, 'Enter the URL: ', 'original URL prompt')
  callback('https://fixture.test/image.png')
end
dispatcher.run(image_item, chat)
h.equal(downloads, 1, 'URL image downloaded once')
h.equal(
  chat.messages[#chat.messages].context.path,
  png,
  'URL attachment uses downloaded file'
)
local count = #chat.messages
vim.ui.input = function(_, callback)
  callback(nil)
end
dispatcher.run(image_item, chat)
h.equal(#chat.messages, count, 'cancelled URL does not attach')
source_choice = nil
dispatcher.run(image_item, chat)
h.equal(#chat.messages, count, 'cancelled source chooser does not attach')
local wrapper = require('lpke.plugins.ai.helpers.slash_image').new({
  Chat = chat,
  config = image_item.config,
})
h.equal(
  wrapper:output({ path = root .. '/not-image.txt' }),
  nil,
  '/image refuses plain text'
)
h.equal(#chat.messages, count, 'plain text never becomes an image attachment')
require('codecompanion.utils.files').download = original_download

-- The default provider also filters its real file scan to image extensions.
image_item.config.opts.provider = 'default'
image_item.config.opts.dirs = { root }
source_choice = 'File'
local calls = 0
vim.ui.select = function(items, opts, callback)
  calls = calls + 1
  if calls == 1 then
    return callback('File')
  end
  h.equal(opts.prompt, 'Images', 'default picker title')
  local selected
  for _, item in ipairs(items) do
    h.check(
      item.path:match('%.png$') ~= nil,
      'default picker excludes text files'
    )
    if item.path == png then
      selected = item
    end
  end
  h.check(selected ~= nil, 'default picker contains fixture image')
  callback(selected)
end
dispatcher.run(image_item, chat)
h.equal(#chat.messages, count + 1, 'default picker attaches native image')
chat.adapter.opts.vision = false
h.equal(
  h.slash.image.enabled({ adapter = chat.adapter }),
  false,
  'image completion disabled without vision'
)
h.equal(
  require('lpke.plugins.ai.helpers.slash_image').enabled(chat),
  false,
  'dispatcher rejects nonvision adapter'
)
vim.fn.delete(root, 'rf')
h.done('image completion/dispatch/attachment')
