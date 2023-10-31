local function config()
  require('Comment').setup({
    padding = true, -- add a space b/w comment and the line
    sticky = true, -- whether the cursor should stay at its position
    ignore = nil, -- lines to be ignored while (un)comment

    -- keymaps
    toggler = {
      line = 'gcc', -- line-comment toggle keymap
      block = 'gbb', -- block-comment toggle keymap
    },

    opleader = {
      line = 'gc', -- line-comment keymap
      block = 'gb', -- block-comment keymap
    },

    extra = {
      above = 'gcO', -- add comment on the line above
      below = 'gco', -- add comment on the line below
      eol = 'gcA', -- add comment at the end of line
    },

    mappings = {
      basic = true, -- toggler, opleader
      extra = true, -- extra
    },

    -- function to call before (un)comment
    pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),

    -- function to call after (un)comment
    post_hook = nil,
  })
end

return {
  'numToStr/Comment.nvim',
  lazy = false,
  config = config,
}
