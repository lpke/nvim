"""Exercise gview through real Git and the installed production Neovim config."""
import importlib.machinery
import importlib.util
import base64
import errno
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
from helpers.git_review import Harness, fixture_environment

GVIEW = Path(os.environ.get('GVIEW_SOURCE',
    str(Path.home() / '.local/share/chezmoi/dot_local/bin/executable_gview')))

PROBE = r'''
vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  local function fail(err)
    io.stderr:write(tostring(err) .. '\n')
    vim.cmd('cquit 1')
  end
  local expected = {}
  for path, contents in pairs(vim.json.decode(vim.env.LPKE_TEST_EXPECTED)) do
    expected[vim.base64.decode(path)] = contents
  end
  local attempts = 0
  local refreshed = false
  local function check()
    local ok, err = pcall(function()
      attempts = attempts + 1
      local view = require('diffview.lib').views[1]
      if not view or not view.ready or not view.initialized then
        assert(attempts < 200, 'state view never initialized')
        vim.defer_fn(check, 50)
        return
      end
      local actual = {}
      for _, entry in view.files:iter() do
        actual[entry.path] = entry
      end
      assert(vim.tbl_count(actual) == vim.tbl_count(expected),
        'wrong file list: ' .. vim.inspect(vim.tbl_keys(actual)))
      for path in pairs(expected) do
        assert(actual[path], 'missing exact path: ' .. path)
      end
      if vim.env.LPKE_TEST_MODE == 'conflicted' then
        assert(#view.files.working == 0 and #view.files.staged == 0)
        for _, entry in ipairs(view.files.conflicting) do
          assert(entry.revs.a.stage == 2 and entry.revs.c.stage == 3 and entry.revs.d.stage == 1)
        end
      end
      local paths = vim.tbl_keys(expected)
      table.sort(paths)
      local function content(index)
        local entry = actual[paths[index]]
        if not entry then
          if not refreshed then
            refreshed = true
            if vim.env.LPKE_TEST_RELINK then
              local path = view.adapter.ctx.toplevel .. '/untracked link'
              assert(vim.uv.fs_unlink(path))
              assert(vim.uv.fs_symlink(vim.env.LPKE_TEST_RELINK, path))
              expected['untracked link'][2] = { vim.env.LPKE_TEST_RELINK }
            end
            if vim.env.LPKE_TEST_REPLACE then
              local replacement = vim.json.decode(vim.env.LPKE_TEST_REPLACE)
              local path = view.adapter.ctx.toplevel .. '/' .. replacement.path
              assert(vim.uv.fs_unlink(path))
              if replacement.kind == 'link' then
                assert(vim.uv.fs_symlink(replacement.contents, path))
              else
                vim.fn.writefile({ replacement.contents }, path)
              end
              expected[replacement.path][2] = { replacement.contents }
            end
            view:update_files(function()
              vim.defer_fn(check, 100)
            end)
          else
            Lpke_review_harness_check()
            print('GVIEW_STATE_PASS')
            vim.cmd('qa!')
          end
          return
        end
        local opened = false
        view:set_file(entry):finally(function() opened = true end)
        local tries = 0
        local function loaded()
          local passed, reason = pcall(function()
            tries = tries + 1
            local a, b = entry.layout.a.file, entry.layout.b.file
            -- Diffview creates named buffers before its asynchronous git-show
            -- job fills them. A loaded buffer can still contain only ''.
            if not opened or not a.bufnr or not b.bufnr or not vim.api.nvim_buf_is_loaded(a.bufnr)
                or not vim.api.nvim_buf_is_loaded(b.bufnr) then
              assert(tries < 100, 'buffers never loaded for ' .. entry.path)
              vim.defer_fn(loaded, 50)
              return
            end
            local left = vim.api.nvim_buf_get_lines(a.bufnr, 0, -1, false)
            local right = vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false)
            local want = expected[entry.path]
            assert(vim.deep_equal(left, want[1]), 'wrong left contents for ' .. entry.path
              .. ': ' .. vim.inspect(left))
            assert(vim.deep_equal(right, want[2]), 'wrong right contents for ' .. entry.path
              .. ': ' .. vim.inspect(right))
            content(index + 1)
          end)
          if not passed then fail(reason) end
        end
        vim.defer_fn(loaded, 50)
      end
      content(1)
    end)
    if not ok then fail(err) end
  end
  vim.defer_fn(check, 100)
end })
'''


class GviewState(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gview-state-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo with 'quotes' "
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        for name in ('both.txt', 'staged.txt', 'unstaged.txt', 'deleted.txt', 'rename old.txt'):
            (self.repo / name).write_text('HEAD ' + name + '\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        for name in ('both.txt', 'staged.txt'):
            (self.repo / name).write_text('INDEX ' + name + '\n')
        self.git('add', '.')
        self.git('mv', 'rename old.txt', "renamed '雪'.txt")
        (self.repo / 'both.txt').write_text('WORK both.txt\n')
        (self.repo / 'unstaged.txt').write_text('WORK unstaged.txt\n')
        (self.repo / 'deleted.txt').unlink()
        self.untracked = ('literal[ab]*?.txt', 'literalaZZx.txt', 'tab\tname.txt',
                          'line\nname.txt', "new '雪'.txt")
        for name in self.untracked:
            (self.repo / name).write_text('NEW ' + name.replace('\n', ' ') + '\n')
        self.probe = self.root / 'probe.lua'
        self.probe.write_text(PROBE)
        self.env = fixture_environment()

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'core.hooksPath=/dev/null',
                                        '-c', 'commit.gpgsign=false', '-c', 'init.templateDir=',
                                        '-C', str(self.repo), *args], env=fixture_environment())

    def open(self, mode, expected, paths=(), host=None):
        command = [sys.executable, str(GVIEW)]
        if host:
            command += ['--host', host]
        command += [str(self.repo), mode]
        if paths:
            command += ['--', *paths]
        encoded = {base64.b64encode(os.fsencode(path)).decode('ascii'): value
                   for path, value in expected.items()}
        env = dict(self.env, LPKE_TEST_EXPECTED=json.dumps(encoded), LPKE_TEST_MODE=mode)
        with Harness(self.root, self.probe) as harness:
            harness.run(extra_env={key: value for key, value in env.items() if key.startswith('LPKE_TEST_')},
                        gview_args=command[2:], gview=GVIEW, marker='GVIEW_STATE_PASS', cwd='/')

    def test_staged_has_only_head_to_index(self):
        self.open('staged', {
            'both.txt': [['HEAD both.txt'], ['INDEX both.txt']],
            'staged.txt': [['HEAD staged.txt'], ['INDEX staged.txt']],
            "renamed '雪'.txt": [['HEAD rename old.txt'], ['HEAD rename old.txt']],
        }, host='another-host,' + socket.gethostname())

    def test_unstaged_has_only_index_to_worktree(self):
        self.open('unstaged', {
            'both.txt': [['INDEX both.txt'], ['WORK both.txt']],
            'unstaged.txt': [['HEAD unstaged.txt'], ['WORK unstaged.txt']],
            'deleted.txt': [['HEAD deleted.txt'], ['']],
        })

    def test_untracked_has_only_empty_to_exact_files(self):
        self.open('untracked', {name: [[''], ['NEW ' + name.replace('\n', ' ')]]
                                for name in self.untracked})

    def test_literal_glob_path_does_not_select_other_files(self):
        name = self.untracked[0]
        self.open('untracked', {name: [[''], ['NEW ' + name]]}, [name])

    def test_explicit_state_path_and_subdirectory(self):
        self.open('unstaged', {'both.txt': [['INDEX both.txt'], ['WORK both.txt']]}, ['both.txt'])
        self.repo = self.repo / 'subdir'
        self.repo.mkdir()
        name = 'nested[1].txt'
        (self.repo / name).write_text('nested\n')
        self.open('untracked', {'subdir/' + name: [[''], ['nested']]}, [name])

    def test_root_directory_filter(self):
        self.open('unstaged', {
            'both.txt': [['INDEX both.txt'], ['WORK both.txt']],
            'unstaged.txt': [['HEAD unstaged.txt'], ['WORK unstaged.txt']],
            'deleted.txt': [['HEAD deleted.txt'], ['']],
        }, ['.'])

    def test_invalid_utf8_filename(self):
        name = os.fsdecode(b'invalid-\xff.txt')
        try:
            (self.repo / name).write_text('invalid bytes filename\n')
        except OSError as error:
            if error.errno in (errno.EILSEQ, errno.EINVAL):
                self.skipTest('filesystem rejects invalid UTF-8 filenames: ' + str(error))
            raise
        self.open('untracked', {name: [[''], ['invalid bytes filename']]}, [name])

    def test_invalid_utf8_checkout_path(self):
        try:
            self.repo = self.repo.rename(self.root / os.fsdecode(b'repo-\xff '))
        except OSError as error:
            if error.errno in (errno.EILSEQ, errno.EINVAL):
                self.skipTest('filesystem rejects invalid UTF-8 directory names: ' + str(error))
            raise
        self.open('unstaged', {'both.txt': [['INDEX both.txt'], ['WORK both.txt']]}, ['both.txt'])

    def test_tracked_literal_tabs_and_newlines(self):
        names = ['tracked[ab]*?.txt', 'tracked\tname.txt', 'tracked\nname.txt']
        for name in names:
            (self.repo / name).write_text('base\n')
        self.git('add', '--', *names)
        self.git('commit', '-qm', 'Special tracked files', '--', *names)
        for name in names:
            (self.repo / name).write_text('index\n')
        self.git('add', '--', *names)
        for name in names:
            (self.repo / name).write_text('worktree\n')
        self.open('staged', {name: [['base'], ['index']] for name in names}, names)
        self.open('unstaged', {name: [['index'], ['worktree']] for name in names}, names)

    def test_conflict_has_only_merge_entries(self):
        self.git('reset', '--hard', 'HEAD')
        self.git('checkout', '-qb', 'side')
        (self.repo / 'both.txt').write_text('theirs\n')
        self.git('commit', '-qam', 'Theirs')
        self.git('checkout', '-qB', 'ours', 'HEAD^')
        (self.repo / 'both.txt').write_text('ours\n')
        self.git('commit', '-qam', 'Ours')
        with self.assertRaises(subprocess.CalledProcessError):
            self.git('merge', 'side')
        self.open('conflicted', {'both.txt': [
            ['ours'], (self.repo / 'both.txt').read_text().splitlines(),
        ]}, ['both.txt'])

    def test_symlink_shows_target_text(self):
        name = 'untracked link'
        (self.repo / name).symlink_to('both.txt')
        self.open('untracked', {name: [[''], ['both.txt']]}, [name])

    def test_symlink_refresh_shows_new_target(self):
        name = 'untracked link'
        (self.repo / name).symlink_to('both.txt')
        self.env['LPKE_TEST_RELINK'] = 'staged.txt'
        self.open('untracked', {name: [[''], ['both.txt']]}, [name])

    def test_refresh_recreates_local_buffer_for_both_file_type_transitions(self):
        for mode in ('untracked', 'unstaged'):
            for initial in ('link', 'file'):
                with self.subTest(mode=mode, initial=initial):
                    name = 'type transition ' + mode + initial
                    path = self.repo / name
                    if mode == 'unstaged':
                        path.write_text('committed contents\n')
                        self.git('add', '--', name)
                        self.git('commit', '-qm', 'Track transition fixture', '--', name)
                        path.unlink()
                    if initial == 'link':
                        path.symlink_to('both.txt')
                        before, after, kind = 'both.txt', 'regular contents', 'file'
                    else:
                        path.write_text('regular contents\n')
                        before, after, kind = 'regular contents', 'both.txt', 'link'
                    self.env['LPKE_TEST_REPLACE'] = json.dumps(
                        dict(path=name, kind=kind, contents=after))
                    left = [''] if mode == 'untracked' else ['committed contents']
                    target_before = (self.repo / 'both.txt').read_bytes()
                    self.open(mode, {name: [left, [before]]}, [name])
                    self.assertEqual((self.repo / 'both.txt').read_bytes(), target_before)

    def test_submodule_opens_patch(self):
        nested = self.root / 'nested'
        nested.mkdir()
        subprocess.run(['git', '-c', 'init.templateDir=', '-C', str(nested), 'init', '-q'], check=True, env=fixture_environment())
        (nested / 'file.txt').write_text('base\n')
        subprocess.run(['git', '-C', str(nested), 'add', '.'], check=True, env=fixture_environment())
        subprocess.run(['git', '-C', str(nested), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Base'], check=True, env=fixture_environment())
        self.git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(nested), 'nested repo')
        self.git('commit', '-qm', 'Add submodule')
        (self.repo / 'nested repo/file.txt').write_text('changed\n')
        patch_text = self.git('diff', '--submodule=diff', '--no-color', '--no-ext-diff',
                              '--ignore-submodules=none', '--', 'nested repo').decode().splitlines()
        self.open('unstaged', {'nested repo': [[''], patch_text]}, ['nested repo'])

    def test_wrong_host_precedes_filesystem_git_and_nvim(self):
        loader = importlib.machinery.SourceFileLoader('gview_test', str(GVIEW))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        argv = ['gview', '--host', 'definitely-wrong.invalid', '/missing/repo', 'unstaged']
        with patch.object(sys, 'argv', argv), patch.object(Path, 'expanduser', side_effect=AssertionError), \
                patch.object(subprocess, 'run', side_effect=AssertionError), \
                patch.object(module.os, 'execvpe', side_effect=AssertionError):
            with self.assertRaises(SystemExit) as caught:
                module.main()
            self.assertEqual(caught.exception.code, 1)


if __name__ == '__main__':
    unittest.main()
