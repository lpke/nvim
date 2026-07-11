local h = require('lpke.snippets.ls_helpers')

return {
  h.s(
    {
      trig = 'type',
      name = 'JSDoc type cast',
    },
    h.fmt('/** @type {<>} */ (<>)', {
      h.i(1, 'Type'),
      h.d(2, h.sel_dedent),
    }),
    { condition = h.has_visual_selection }
  ),
}
