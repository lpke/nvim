local helpers = require('lpke.core.helpers')
local merge_tables = helpers.merge_tables

-- shared emmet options for multiple filetypes
local emmet_opts_global = {
  ['bem.enabled'] = false,
  ['output.selfClosingStyle'] = 'xhtml',
  ['output.attributeQuotes'] = 'double',
}

local emmet_opts_jsx = {
  ['jsx.enabled'] = true,
  ['markup.attributes'] = {
    ['class'] = 'className',
    ['for'] = 'htmlFor',
  },
}

return {
  on_init = function(_client, _result)
    -- when server first initiated
  end,
  on_attach = function(_client, _bufnr)
    -- for every buffer attach
  end,
  filetypes = {
    'html',
    'htmx',
    'pug',
    'jsx',
    'javascriptreact',
    'tsx',
    'typescriptreact',
    'vue',
    'svelte',
    'css',
    'sass',
    'scss',
    'less',
    'eruby',
  },
  init_options = {
    html = {
      options = emmet_opts_global,
    },
    pug = {
      options = emmet_opts_global,
    },
    xml = {
      options = emmet_opts_global,
    },
    xsl = {
      options = emmet_opts_global,
    },
    js = {
      options = merge_tables(emmet_opts_global, emmet_opts_jsx),
    },
    jsx = {
      options = merge_tables(emmet_opts_global, emmet_opts_jsx),
    },
    svelte = {
      options = emmet_opts_global,
    },
    vue = {
      options = emmet_opts_global,
    },
    slim = {
      options = emmet_opts_global,
    },
    haml = {
      options = emmet_opts_global,
    },
  },
}
