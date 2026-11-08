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
    local started = vim.uv.hrtime()
    local function before_deadline()
      -- Process startup is much slower on macOS. Bound elapsed time while still
      -- requiring the completed stream and exact full commit/file sequence.
      return (vim.uv.hrtime() - started) / 1e6 < 60000
    end
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
      if not startup_done or not view or not view.ready then
        assert(before_deadline(), 'view never ready ' .. index)
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
        local title = want.title:gsub('[%z\1-\31\127]', function(c)
          return string.format('\\x%02x', c:byte())
        end)
        if title ~= '' then
          assert(
            vim.b[view.panel.bufid].lpke_review_title == want.title,
            'wrong review buffer title'
          )
          local name = vim.api.nvim_buf_get_name(view.panel.bufid)
          assert(
            name:match('^diffview:///panels/%d+/'),
            'lost unique panel URI'
          )
          assert(
            name:find(
              'Review - '
                .. want.title:gsub('[%z\1-\31\127/\\%%]', function(c)
                  return string.format('%%%02X', c:byte())
                end),
              1,
              true
            ),
            'wrong panel buffer name: ' .. name
          )
        end
        title = title:gsub('%%', '%%%%')
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
        if view.panel.updating or #view.panel.entries < #want.commits then
          assert(before_deadline(), 'history never loaded')
          later(function()
            check_view(index)
          end)
          return
        end
        local commits = {}
        for _, entry in ipairs(view.panel.entries) do
          commits[#commits + 1] = entry.commit.hash
          for _, file in ipairs(entry.files) do
            sequence[#sequence + 1] =
              { commit = entry.commit.hash, path = file.path }
            if want.versions then
              actual[tostring(#sequence)] = file
            else
              assert(
                not actual[file.path],
                'ambiguous history path; use ordered versions keyed by commit and path: '
                  .. file.path
              )
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
          assert(
            before_deadline(),
            'diff never initialized '
              .. index
              .. ': initialized='
              .. tostring(view.initialized)
              .. ', files='
              .. view.files:len()
              .. ', current='
              .. tostring(view.cur_entry and view.cur_entry.path)
              .. ', opened='
              .. tostring(view.cur_entry and view.cur_entry.opened)
          )
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
        assert(
          vim.tbl_isempty(contents),
          'use versions or legacy contents, not both'
        )
        local wanted_sequence = {}
        for i, version in ipairs(want.versions) do
          local path = vim.base64.decode(version.path_b64)
          wanted_sequence[i] = { commit = version.commit, path = path }
          contents[tostring(i)] = version
        end
        assert(
          vim.deep_equal(sequence, wanted_sequence),
          'wrong history sequence: '
            .. vim.inspect(sequence)
            .. ' expected '
            .. vim.inspect(wanted_sequence)
        )
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
          started = vim.uv.hrtime()
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
        -- Ordered metadata still checks every version in large histories; only
        -- versions with content expectations need a buffer opened as well.
        if
          not want.readonly
          and not data.binary
          and not (data.a or data.b or data.c or data.d)
        then
          return check_file(file_index + 1)
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
          if type(want.title) == 'string' and want.title ~= '' then
            for _, side in ipairs({ 'a', 'b', 'c', 'd' }) do
              local win = view.cur_layout[side]
              if win and win.id and vim.api.nvim_win_is_valid(win.id) then
                local buf = vim.api.nvim_win_get_buf(win.id)
                local native_name = vim.api.nvim_buf_get_name(buf)
                local label = vim.api.nvim_win_call(win.id, function()
                  return require('lpke.plugins.git.helpers.review_labels').current()
                end)
                local role = side == 'a' and 'BEFORE' or 'AFTER'
                if entry.kind == 'conflicting' then
                  role = (
                    { a = 'OURS', b = 'RESULT', c = 'THEIRS', d = 'BASE' }
                  )[side]
                elseif
                  side == 'b' and view.adapter._lpke_readonly_label == 'Stash'
                then
                  role = entry.kind == 'staged' and 'AFTER (INDEX)'
                    or entry.status == '?' and 'AFTER (UNTRACKED)'
                    or 'AFTER (WORKTREE)'
                end
                assert(
                  type(label) == 'string',
                  'missing file-pane label: ' .. key .. ' ' .. side
                )
                assert(
                  label:sub(1, #role + 2) == role .. ': ',
                  'wrong side label: ' .. label
                )
                assert(
                  label:sub(-#want.title - 3) == ' | ' .. want.title,
                  'wrong review title: ' .. label
                )
                local path = side == 'a' and entry.oldpath or entry.path
                assert(
                  label:find(path:match('[^/]+$'), 1, true),
                  'wrong filename: ' .. label
                )
                if data.labels and data.labels[side] then
                  assert(
                    label == data.labels[side],
                    'wrong exact pane label: ' .. label
                  )
                end
                assert(
                  vim.api.nvim_buf_get_name(buf) == native_name,
                  'file buffer was renamed'
                )
                assert(
                  vim.b[buf].lpke_review_title == nil,
                  'review title leaked into shared file buffer'
                )
              end
            end
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
