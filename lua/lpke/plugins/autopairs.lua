local function config()
  -- add autoclose functionality when selecting cmp items
  local cmp_autopairs = require('nvim-autopairs.completion.cmp')
  local cmp = require('cmp')
  cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())

  require('nvim-autopairs').setup({
    disable_filetype = { 'TelescopePrompt', 'spectre_panel' },
    disable_in_macro = true,
    disable_in_visualblock = true,
    disable_in_replace_mode = true,
    ignored_next_char = [=[[%w%%%'%[%"%.%`%$]]=],
    enable_moveright = true,
    enable_afterquote = true, -- add bracket pairs after quote
    enable_check_bracket_line = true, -- check bracket in same line
    enable_bracket_in_quote = false,
    enable_abbr = false, -- trigger abbreviation
    break_undo = true, -- switch for basic rule break undo sequence
    check_ts = false, -- check treesitter (options example below)
    -- ts_config = {
    --   lua = { 'string' }, -- it will not add a pair on that treesitter node
    --   javascript = { 'template_string' },
    --   java = false, -- don't check treesitter on java
    -- },
    map_cr = true, -- map the <CR> key
    map_bs = true, -- map the <BS> key
    map_c_h = true, -- Map the <C-h> key to delete a pair
    map_c_w = false, -- map <c-w> to delete a pair if possible
  })
end

return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  dependencies = { 'hrsh7th/nvim-cmp' },
  config = config,
}
