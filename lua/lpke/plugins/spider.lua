local function config()
  local keymaps = {
    {'noxC', '<Right>', [[lua require('spider').motion('w')]]},
    {'noxC', '<Left>', [[lua require('spider').motion('b')]]},
  }
  require('lpke.core.helpers').keymap_set_multi(keymaps)

  -- options
  require('spider').setup({
    skipInsignificantPunctuation = true,
  })
end

return {
  'chrisgrieser/nvim-spider',
  config = config,
}
