local function config()
  local keymaps = {
    -- subword (camelCase, snake_case, kebab-case)
    {'oxC', 'i<leader>w', [[lua require('various-textobjs').subword('inner')]]},
    {'oxC', 'a<leader>w', [[lua require('various-textobjs').subword('outer')]]},
    -- entire buffer
    {'oxC', 'gG', [[lua require('various-textobjs').entireBuffer()]]},
    -- indentation
    {'oxC', 'ii', [[lua require('various-textobjs').indentation('inner', 'inner')]]},
    {'oxC', 'ai', [[lua require('various-textobjs').indentation('outer', 'inner')]]},
    {'oxC', 'aI', [[lua require('various-textobjs').indentation('outer', 'outer')]]},
    {'oxC', 'iI', [[lua require('various-textobjs').restOfIndentation()]]},
  }
  require('lpke.core.helpers').keymap_set_multi(keymaps)

  -- options
  require('various-textobjs').setup({
    -- lines to seek forwards for "small" textobjs (mostly characterwise textobjs)
    -- set to 0 to only look in the current line
    lookForwardSmall = 5,

    -- lines to seek forwards for "big" textobjs (mostly linewise textobjs)
    lookForwardBig = 15,

    useDefaultKeymaps = false,
    disabledKeymaps = {},
  })
end

return {
  'chrisgrieser/nvim-various-textobjs',
  config = config,
}
