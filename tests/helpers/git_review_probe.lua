-- Shared integration assertions: production config, actual plugin views/buffers.
local expected = vim.json.decode(vim.env.LPKE_REVIEW_EXPECTED)
local startup_done = false
local startup = require('lpke.plugins.git.helpers.review_views')
local open = startup.open
startup.open = function(...)
  local result = open(...)
  startup_done = true
  return result
end
local function later(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      io.stderr:write(tostring(err) .. '\n')
      vim.cmd('cquit 1')
    end
  end, 60)
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    local tries = 0
    local function check_view(index)
      local want = expected[index]
      local lib = require('diffview.lib')
      if not want then
        assert(#lib.views == #expected, 'unexpected review views')
        assert(
          #vim.api.nvim_list_tabpages() == #expected,
          'startup tabs survived'
        )
        if vim.env.LPKE_REVIEW_EXTRA and vim.env.LPKE_REVIEW_EXTRA ~= '' then
          assert(loadstring(vim.env.LPKE_REVIEW_EXTRA))()
        end
        assert(
          require('auto-session.config').auto_save == false,
          'review can save a session'
        )
        Lpke_review_harness_check()
        print('GIT_REVIEW_PASS')
        if vim.env.LPKE_REVIEW_QUIT == '1' then
          local mapping = vim.fn.maparg('Q', 'n', false, true)
          assert(type(mapping.callback) == 'function', 'missing Q')
          mapping.callback()
        else
          vim.cmd('qa!')
        end
        return
      end
      local view = lib.views[index]
      tries = tries + 1
      if not startup_done or not view or not view.ready then
        assert(tries < 300, 'view never ready ' .. index)
        later(function()
          check_view(index)
        end)
        return
      end
      vim.api.nvim_set_current_tabpage(view.tabpage)
      if want.title and want.title ~= vim.NIL then
        assert(
          vim.t[view.tabpage].lpke_review_title == want.title,
          'wrong tab title '
            .. index
            .. ': '
            .. vim.inspect(vim.t[view.tabpage].lpke_review_title)
            .. ' expected '
            .. vim.inspect(want.title)
        )
        local title = want.title
          :gsub('[%z\1-\31\127]', function(c)
            return string.format('\\x%02x', c:byte())
          end)
          :gsub('%%', '%%%%')
        assert(
          Lpke_tabline():find(title, 1, true),
          'title not rendered literally'
        )
      else
        assert(
          vim.t[view.tabpage].lpke_review_title == nil,
          'legacy title changed'
        )
      end
      local root = vim.base64.decode(want.repo_b64)
      assert(view.adapter.ctx.toplevel == root, 'wrong adapter repository')
      assert(vim.fn.getcwd(-1, vim.fn.tabpagenr()) == root, 'wrong tab cwd')
      local actual = {}
      local sequence = {}
      if want.commits then
        if #view.panel.entries < #want.commits then
          assert(tries < 300, 'history never loaded')
          later(function()
            check_view(index)
          end)
          return
        end
        local commits = {}
        for _, entry in ipairs(view.panel.entries) do
          commits[#commits + 1] = entry.commit.hash
          for _, file in ipairs(entry.files) do
            sequence[#sequence + 1] = { commit = entry.commit.hash, path = file.path }
            if want.versions then
              actual[tostring(#sequence)] = file
            else
              assert(not actual[file.path],
                'ambiguous history path; use ordered versions keyed by commit and path: ' .. file.path)
              actual[file.path] = file
            end
          end
        end
        table.sort(commits)
        table.sort(want.commits)
        assert(
          vim.deep_equal(commits, want.commits),
          'wrong commits ' .. vim.inspect(commits)
        )
      else
        if
          not view.initialized
          or (
            view.files:len() > 0
            and (not view.cur_entry or not view.cur_entry.opened)
          )
        then
          assert(tries < 300, 'diff never initialized '
            .. index .. ': initialized=' .. tostring(view.initialized)
            .. ', files=' .. view.files:len()
            .. ', current=' .. tostring(view.cur_entry and view.cur_entry.path)
            .. ', opened=' .. tostring(view.cur_entry and view.cur_entry.opened))
          later(function()
            check_view(index)
          end)
          return
        end
        for _, entry in view.files:iter() do
          actual[entry.kind .. ':' .. entry.path] = entry
        end
      end
      local contents = {}
      for key, value in pairs(want.contents_b64 or {}) do
        contents[vim.base64.decode(key)] = value
      end
      if want.versions then
        assert(want.commits, 'versions require explicit commit scope')
        assert(vim.tbl_isempty(contents), 'use versions or legacy contents, not both')
        local wanted_sequence = {}
        for i, version in ipairs(want.versions) do
          local path = vim.base64.decode(version.path_b64)
          wanted_sequence[i] = { commit = version.commit, path = path }
          contents[tostring(i)] = version
        end
        assert(vim.deep_equal(sequence, wanted_sequence),
          'wrong history sequence: ' .. vim.inspect(sequence)
            .. ' expected ' .. vim.inspect(wanted_sequence))
      end
      assert(
        vim.tbl_count(actual) == vim.tbl_count(contents),
        'wrong files ' .. index .. ': ' .. vim.inspect(vim.tbl_keys(actual))
      )
      local keys = vim.tbl_keys(contents)
      table.sort(keys)
      local function check_file(file_index)
        local key = keys[file_index]
        if not key then
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
            assert(
              vim.api.nvim_win_call(win, vim.fn.getcwd) == root,
              'wrong window cwd '
                .. index
                .. ': '
                .. vim.api.nvim_win_call(win, vim.fn.getcwd)
                .. ' expected '
                .. root
            )
          end
          tries = 0
          later(function()
            check_view(index + 1)
          end)
          return
        end
        local entry = assert(actual[key], 'missing ' .. key)
        local data = contents[key]
        if data.oldpath then
          assert(entry.oldpath == data.oldpath, 'wrong rename source')
        end
        local opened = false
        view:set_file(entry):finally(function()
          opened = true
        end)
        local attempts = 0
        local function loaded()
          attempts = attempts + 1
          if not opened then
            assert(attempts < 150, 'file did not load ' .. key)
            later(loaded)
            return
          end
          for _, side in ipairs({ 'a', 'b', 'c', 'd' }) do
            if data[side] then
              local file = entry.layout[side].file
              assert(
                file.bufnr and vim.api.nvim_buf_is_loaded(file.bufnr),
                'buffer missing'
              )
              local lines = vim.api.nvim_buf_get_lines(file.bufnr, 0, -1, false)
              assert(
                vim.deep_equal(lines, data[side]),
                'wrong ' .. side .. ' ' .. key .. ': ' .. vim.inspect(lines)
              )
              if want.readonly then
                assert(
                  not vim.bo[file.bufnr].modifiable,
                  'stash buffer is writable'
                )
                assert(
                  vim.bo[file.bufnr].readonly,
                  'stash buffer lacks readonly'
                )
              end
            end
          end
          if data.binary then
            assert(entry.layout.b.file.binary, 'binary shown as text')
          end
          check_file(file_index + 1)
        end
        later(loaded)
      end
      check_file(1)
    end
    later(function()
      check_view(1)
    end)
  end,
})
