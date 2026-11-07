"""Verify wrap shortcuts in a real history view using the production config."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DiffviewWrap(unittest.TestCase):
    def test_history_and_diff_pane_scope(self):
        with tempfile.TemporaryDirectory(prefix='diffview-wrap-') as directory:
            root = Path(directory)
            def git(*args):
                subprocess.run(['git', '-C', directory, *args], check=True,
                               capture_output=True)
            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            git('config', 'commit.gpgsign', 'false')
            git('config', 'core.hooksPath', '/dev/null')
            for text in ('before\n', 'after\n'):
                (root / 'file.txt').write_text(text)
                git('add', '.')
                git('commit', '-qm', 'Fixture')
            probe = root / 'probe.lua'
            probe.write_text(r'''
vim.api.nvim_create_autocmd('VimEnter', {once=true, callback=function()
  local attempts=0
  local function check()
    local ok,err=pcall(function()
      attempts=attempts+1
      local view=require('diffview.lib').views[1]
      local diffs={}
      for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.wo[win].diff then diffs[#diffs+1]=win end
      end
      if not view or not view.ready or not view.panel:is_open() or #diffs~=2 then
        assert(attempts<200,'history layout never became ready')
        vim.defer_fn(check,50)
        return
      end
      local panel=view.panel.winid
      for _,win in ipairs({panel,diffs[1],diffs[2]}) do
        local ready=vim.api.nvim_win_call(win,function()
          return type(vim.fn.maparg('<A-w>','n',false,true).callback)=='function'
        end)
        if not ready then
          assert(attempts<200,'scoped wrap mapping never installed')
          vim.defer_fn(check,50)
          return
        end
      end
      local function toggle(win,key)
        vim.api.nvim_set_current_win(win)
        local mapping=vim.fn.maparg(key or '<A-w>','n',false,true)
        assert(type(mapping.callback)=='function','missing scoped wrap mapping: '..vim.inspect(mapping))
        mapping.callback()
        assert(vim.api.nvim_get_current_win()==win,'wrap changed focus')
      end
      local function expect(bottom,top)
        assert(vim.wo[panel].wrap==bottom,'wrong history pane wrap')
        for _,win in ipairs(diffs) do
          assert(vim.wo[win].wrap==top,'wrong diff pane wrap')
        end
      end
      vim.wo[panel].wrap=false
      for _,win in ipairs(diffs) do vim.wo[win].wrap=false end
      toggle(panel);expect(true,true)
      toggle(panel);expect(false,false)
      vim.wo[panel].wrap=true
      toggle(diffs[1]);expect(true,true)
      toggle(diffs[2]);expect(true,false)
      toggle(panel,'<F2>w');expect(false,false)
      toggle(panel,'<F2>w');expect(true,true)
      vim.wo[panel].wrap=false
      toggle(diffs[2]);expect(false,false)
      print('DIFFVIEW_WRAP_PASS')
      vim.cmd('qa!')
    end)
    if not ok then io.stderr:write(tostring(err)..'\n');vim.cmd('cquit 1') end
  end
  vim.defer_fn(check,100)
end})
''')
            env = dict(os.environ, LPKE_NVIM_NO_SESSION='1',
                       LPKE_NVIM_DIFFVIEW_GIT_UI='1',
                       LPKE_NVIM_DIFFVIEW_GIT_UI_MODE='history')
            env.pop('LPKE_NVIM_DIFFVIEW_VIEWS', None)
            result = subprocess.run(['nvim', '--headless', '-i', 'NONE', '-n', '.',
                                     '-c', 'lua dofile(' + repr(str(probe)) + ')'],
                                    cwd=root, env=env, capture_output=True,
                                    text=True, errors="replace", timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('DIFFVIEW_WRAP_PASS', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
