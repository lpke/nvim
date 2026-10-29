local M = {}

-- Only these pinned modules need the legacy validation shape translated.
-- Digests make an upstream change a visible review requirement, not a silent
-- source rewrite. Remove entries as their upstream implementations modernize.
local modules = {
  {
    'lualine.utils.fn_store',
    'lualine.nvim/lua/lualine/utils/fn_store.lua',
    '095f031643c667f6c3bce8c79cdeaeb0da51bbdfd3a64a612edff5d0e3433920',
    2,
  },
  {
    'plenary.async.control',
    'plenary.nvim/lua/plenary/async/control.lua',
    '9c1fdcd3bd6582196ad0006beefddb331c07dcbcc9c6dff309bd85386a59c1f1',
    1,
  },
  {
    'plenary.async_lib.util',
    'plenary.nvim/lua/plenary/async_lib/util.lua',
    '1a6d35236b42c8f417594d047662650840d8c9c5acf3b8bc9d0340cd0f873a9d',
    1,
  },
  {
    'plenary.benchmark',
    'plenary.nvim/lua/plenary/benchmark/init.lua',
    '4106f5ca233be69b74ba2f38f1f4a03df5c5363c4d706249cfeca4fb922cbaff',
    1,
  },
  {
    'diffview.ui.panel',
    'diffview.nvim/lua/diffview/ui/panel.lua',
    '536a2f1a42cfc8fe19f2749793a08b7a59570b5eff14889c5383770dff593fad',
    3,
  },
  {
    'diffview.vcs.adapters.git',
    'diffview.nvim/lua/diffview/vcs/adapters/git/init.lua',
    '5d77fd042d1af44ee97570032fb4823a00809cc60d7e2e1a68a32b88ad20d26c',
    1,
  },
  {
    'dressing.input',
    'dressing.nvim/lua/dressing/input.lua',
    '4fd27fb8f8525eabe1c64a646b0bad286b8c8b1150c1430bff4147e012c3f244',
    1,
  },
  {
    'dressing.select',
    'dressing.nvim/lua/dressing/select/init.lua',
    'ba290dc8d6f7130437224daeda94836efd8bf93328441b832c5d03c7b0f70b87',
    1,
  },
  {
    'cmp_buffer.source',
    'cmp-buffer/lua/cmp_buffer/source.lua',
    'b9dfb3b082ba70e5cb589b1b6ceeca8d59df1cfe0132cd08f246350302499ff4',
    1,
  },
  {
    'cmp_luasnip',
    'cmp_luasnip/lua/cmp_luasnip/init.lua',
    '6a26c8ac3b402480e1ca117f7fa4bc1445f534d7af9ba0dd45e9bb38deaaa536',
    1,
  },
}

function M.setup()
  local patch = require('lpke.core.helpers.plugin')
  local root = vim.fn.stdpath('data') .. '/lazy/'
  for _, module in ipairs(modules) do
    patch.patch_validation(module[1], root .. module[2], module[3], module[4])
  end

  local function replace(source, before, after)
    local first, last = assert(source:find(before, 1, true))
    assert(not source:find(before, last + 1, true), 'Plugin patch is ambiguous')
    return source:sub(1, first - 1) .. after .. source:sub(last + 1)
  end

  patch.patch_module(
    'nvim-treesitter-textobjects.shared',
    root
      .. 'nvim-treesitter-textobjects/lua/nvim-treesitter-textobjects/shared.lua',
    'a2d5587e0050d39fd0ededed6c5988ed4ab670e34512dc2a9ca6ab77b16fbfb5',
    function(source)
      source = replace(
        source,
        'nodes[1]:range(true)',
        'unpack(ts.get_range(nodes[1], bufnr, metadata[id]))'
      )
      return replace(
        source,
        'nodes[#nodes]:range(true)',
        'unpack(ts.get_range(nodes[#nodes], bufnr, metadata[id]))'
      )
    end
  )

  patch.patch_module(
    'telescope.previewers.buffer_previewer',
    root .. 'telescope.nvim/lua/telescope/previewers/buffer_previewer.lua',
    '66eb9b8be3df0277883cb3d7cdd9e664bfe068c694ca06ea3ee31a2851253119',
    function(source)
      source = replace(
        source,
        '{ i - 1, dstart }, { #line }',
        '{ i - 1, dstart }, { i - 1, #line }'
      )
      -- Upstream ad7d958: after toggling the preview, the outer window ID is
      -- stale. Only the five option setters need the current preview ID.
      local patched, count =
        source:gsub('vim%.wo%[preview_window_id%]', 'vim.wo[preview_winid]')
      assert(count == 5, 'Telescope preview option sites changed')
      return patched
    end
  )

  patch.patch_module(
    'dressing.select.builtin',
    root .. 'dressing.nvim/lua/dressing/select/builtin.lua',
    'c25a4d935c2d90c3502e34fa9bb2555bad2846a69026478ca4dd8155a72b11c9',
    function(source)
      source = replace(
        source,
        'vim.api.nvim_buf_add_highlight(bufnr, ns, "DressingSelectIdx", lnum, 0, end_col)',
        'vim.hl.range(bufnr, ns, "DressingSelectIdx", { lnum, 0 }, { lnum, end_col })'
      )
      return replace(source, 'buffer = bufnr', 'buf = bufnr')
    end
  )
end

return M
