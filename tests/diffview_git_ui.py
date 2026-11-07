"""Run with python3 tests/diffview_git_ui.py using the installed Neovim config."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DiffviewGitUi(unittest.TestCase):
    def test_first_commit_shortcut_survives_startup_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()

            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            hashes = []
            for index in range(3):
                (root / 'file.txt').write_text(str(index) + '\n')
                git('add', '.')
                git('commit', '-qm', 'Commit ' + str(index))
                hashes.append(git('rev-parse', 'HEAD'))
            probe = root / 'probe.lua'
            probe.write_text('''
vim.api.nvim_create_autocmd('VimEnter', {once=true, callback=function()
  local function schedule(fn, delay)
    vim.defer_fn(function()
      local ok, err = pcall(fn)
      if not ok then
        io.stderr:write(tostring(err) .. '\\n')
        vim.cmd('cquit 1')
      end
    end, delay)
  end
  local attempts = 0
  local function check()
    attempts = attempts + 1
    local lib = require('diffview.lib')
    local history = lib.views[1]
    if not history or not history.ready or #history.panel.entries < 3 then
      assert(attempts < 100, 'history did not load')
      schedule(check, 50)
      return
    end
    history.panel:focus()
    local entry = history.panel.entries[2]
    for line = 1, vim.api.nvim_buf_line_count(history.panel.bufid) do
      vim.api.nvim_win_set_cursor(history.panel.winid, {line, 0})
      if history.panel:get_item_at_cursor() == entry then break end
    end
    -- History entries arrive before Diffview's throttled panel render. Only
    -- press the shortcut once the chosen commit has an actual cursor row.
    if history.panel:get_item_at_cursor() ~= entry then
      assert(attempts < 100, 'selected commit row did not render')
      schedule(check, 50)
      return
    end
    vim.fn.maparg('<leader>I', 'n', false, true).callback()
    schedule(function()
      assert(#lib.views == 2, 'first press must retain the new diff view')
      assert(#vim.api.nvim_list_tabpages() == 2, 'both Diffview tabs must survive cleanup')
      local view = lib.get_current_view()
      assert(view.right.commit == vim.env.LPKE_TEST_COMMIT, 'selected commit must stay focused')
      assert(view.left.commit == vim.env.LPKE_TEST_PARENT, 'diff must use selected commit parent')
      print('DIFFVIEW_PASS')
      vim.cmd('qa!')
    end, 500)
  end
  schedule(check, 100)
end})
''')
            env = dict(os.environ, LPKE_NVIM_NO_SESSION='1', LPKE_NVIM_DIFFVIEW_GIT_UI='1',
                       LPKE_NVIM_DIFFVIEW_GIT_UI_MODE='history', LPKE_TEST_COMMIT=hashes[1],
                       LPKE_TEST_PARENT=hashes[0])
            env.pop('LPKE_NVIM_DIFFVIEW_VIEWS', None)
            try:
                result = subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '.', '-c',
                                         'lua dofile(' + repr(str(probe)) + ')'], cwd=root, env=env,
                                        capture_output=True, text=True, timeout=15)
            except subprocess.TimeoutExpired as error:
                self.fail('Neovim timed out:\n' + (error.stderr or b'').decode(errors='replace'))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('DIFFVIEW_PASS', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
