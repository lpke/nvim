local function config()
  local spider = require('spider')
  local helpers = require('lpke.core.helpers')

  helpers.keymap_set_multi({
    { 'noxC', '<Right>', [[lua require('spider').motion('w')]] },
    { 'noxC', '<Left>', [[lua require('spider').motion('b')]] },
  })

  -- options
  spider.setup({
    skipInsignificantPunctuation = true,
  })
end

return {
  'chrisgrieser/nvim-spider',
  commit = '6da0307421bc4be6fe02815faabde51007c4ea1a',
  config = config,
}
