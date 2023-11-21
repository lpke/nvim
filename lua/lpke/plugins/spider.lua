local function config()
  require('lpke.core.helpers').keymap_set_multi({
    { 'noxC', '<Right>', [[lua require('spider').motion('w')]] },
    { 'noxC', '<Left>', [[lua require('spider').motion('b')]] },
  })

  -- options
  require('spider').setup({
    skipInsignificantPunctuation = true,
  })
end

return {
  'chrisgrieser/nvim-spider',
  config = config,
}
