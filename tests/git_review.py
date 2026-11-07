"""Run: python3 tests/git_review.py. Every case creates and removes real repos."""
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

from helpers.git_review import Repo, b64, fixture_environment, probe


class GitReview(unittest.TestCase):
    def test_fixture_writes_ignore_foreign_git_environment(self):
        import os
        from unittest.mock import patch
        sentinel = Repo(self.root / 'sentinel')
        sentinel.write('untouched', 'sentinel\n')
        sentinel.commit()
        before = sentinel.snapshot()
        with patch.dict(os.environ, GIT_DIR=str(sentinel.path / '.git'), GIT_WORK_TREE=str(sentinel.path),
                        GIT_INDEX_FILE=str(sentinel.path / '.git/index'), GIT_CONFIG_COUNT='1',
                        GIT_CONFIG_KEY_0='user.name', GIT_CONFIG_VALUE_0='Rogue fixture'):
            intended = Repo(self.root / 'isolated intended')
            intended.write('actual', 'new fixture\n')
            intended.commit()
        self.assertEqual(sentinel.snapshot(), before)
        self.assertEqual(Path(intended.git('rev-parse', '--show-toplevel')).resolve(), intended.path)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nvim-review-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = Repo(self.root / "repo '雪' [x] ")
        self.repo.write('file.txt', 'base\n')
        self.base = self.repo.commit('Root')

    def expect(self, spec, contents, **kwargs):
        return dict(repo_b64=spec['repo_b64'], title=spec.get('title'),
                    contents=contents, **kwargs)

    def run_views(self, specs, expected, **kwargs):
        repos = [self.repo, *getattr(self, 'other_repos', [])]
        before = [repo.snapshot() for repo in repos]
        probe(self.root, specs, expected, **kwargs)
        self.assertEqual(before, [repo.snapshot() for repo in repos], 'review changed repository')

    def test_real_cli_mixed_plan(self):
        import base64
        import json
        import socket
        repo = self.repo
        repo.write('file.txt', 'saved tracked\n')
        repo.write('saved-new', 'saved untracked\n')
        repo.git('stash', 'push', '-qu')
        oid = repo.git('rev-parse', 'refs/stash')
        repo.write('file.txt', 'live index\n')
        repo.git('add', '.')
        repo.write('file.txt', 'live worktree\n')
        repo.write('live-new', 'live untracked\n')
        plan = {'version': 1, 'hosts': {socket.gethostname(): {
            'repo': str(repo.path), 'views': [
                {'kind': 'history', 'title': 'Root commit', 'revisions': [self.base + '^!']},
                {'kind': 'staged', 'title': 'Index', 'paths': ['file.txt']},
                {'kind': 'unstaged', 'title': 'Worktree', 'paths': ['file.txt']},
                {'kind': 'untracked', 'title': 'New file', 'paths': ['live-new']},
                {'kind': 'diff', 'title': 'Explicit diff', 'revisions': [self.base + '^!']},
                {'kind': 'stash', 'title': 'Saved stash', 'oid': oid},
            ],
        }}}
        token = base64.urlsafe_b64encode(json.dumps(plan).encode()).decode().rstrip('=')
        specs = [repo.spec('history', 'Root commit'), repo.spec('diff', 'Index'),
                 repo.spec('diff', 'Worktree'), repo.spec('diff', 'New file'),
                 repo.spec('diff', 'Explicit diff'), repo.spec('stash', 'Saved stash')]
        self.run_views(specs, [
            self.expect(specs[0], {'file.txt': {'a': [''], 'b': ['base']}}, commits=[self.base]),
            self.expect(specs[1], {'working:file.txt': {'a': ['base'], 'b': ['live index']}}),
            self.expect(specs[2], {'working:file.txt': {'a': ['live index'], 'b': ['live worktree']}}),
            self.expect(specs[3], {'working:live-new': {'a': [''], 'b': ['live untracked']}}),
            self.expect(specs[4], {'working:file.txt': {'a': [''], 'b': ['base']}}),
            self.expect(specs[5], {
                'working:file.txt': {'a': ['base'], 'b': ['saved tracked']},
                'working:saved-new': {'a': [''], 'b': ['saved untracked']},
            }, readonly=True),
        ], gview_args=['--plan', token])

    def test_inactive_tab_refresh_cannot_cancel_pending_active_refresh(self):
        repo = self.repo
        repo.write('file.txt', 'staged\n')
        repo.git('add', '.')
        repo.write('file.txt', 'unstaged\n')
        specs = [repo.spec('diff', 'Index', state='staged'),
                 repo.spec('diff', 'Worktree', state='unstaged')]
        self.run_views(specs, [
            self.expect(specs[0], {'working:file.txt': {'a': ['base'], 'b': ['staged']}}),
            self.expect(specs[1], {'working:file.txt': {'a': ['staged'], 'b': ['unstaged']}}),
        ], extra='''
local views = require('diffview.lib').views
vim.api.nvim_set_current_tabpage(views[1].tabpage)
vim.wait(250, function() return false end, 10)
local finished, cancelled = false, false
views[1]:update_files()
views[1]:update_files(function(err) assert(not err, vim.inspect(err)); finished = true end)
views[2]:update_files(function(err) cancelled = err ~= nil end)
assert(vim.wait(2000, function() return finished end, 10), 'hidden tab cancelled the active refresh')
assert(cancelled, 'hidden update should report cancellation')
''')

    def test_unborn_repository_states_via_payload_and_real_cli(self):
        import base64
        import json
        import socket
        repo = Repo(self.root / 'unborn')
        self.other_repos = [repo]
        repo.write('both', 'index contents\n')
        repo.git('add', '.')
        repo.write('both', 'worktree contents\n')
        repo.write('new', 'untracked contents\n')
        specs = [repo.spec('diff', 'Unborn index', state='staged', paths_b64=[b64('both')]),
                 repo.spec('diff', 'Unborn worktree', state='unstaged', paths_b64=[b64('both')]),
                 repo.spec('diff', 'Unborn new', state='untracked', paths_b64=[b64('new')])]
        expected = [self.expect(specs[0], {'working:both': {'a': [''], 'b': ['index contents']}}),
                    self.expect(specs[1], {'working:both': {'a': ['index contents'], 'b': ['worktree contents']}}),
                    self.expect(specs[2], {'working:new': {'a': [''], 'b': ['untracked contents']}})]
        self.run_views(specs, expected)
        views = [dict(kind=spec['state'], title=spec['title'], paths=['new' if spec['state'] == 'untracked' else 'both'])
                 for spec in specs]
        plan = {'version': 1, 'hosts': {socket.gethostname(): {'repo': str(repo.path), 'views': views}}}
        token = base64.urlsafe_b64encode(json.dumps(plan).encode()).decode().rstrip('=')
        self.run_views(specs, expected, gview_args=['--plan', token])

    def test_mixed_repositories_titles_and_legacy(self):
        repo = self.repo
        repo.write('file.txt', 'index\n')
        repo.git('add', '.')
        repo.write('file.txt', 'worktree\n')
        name = 'new\n[ab]*? | let g:injected=1.txt'
        repo.write(name, 'untracked\n')
        other = Repo(self.root / 'second\nrepo | tabonly')
        self.other_repos = [other]
        other.write('other', 'another root\n')
        oid = other.commit()
        saved = Repo(self.root / 'stash repo')
        self.other_repos.append(saved)
        saved.write('saved', 'saved base\n')
        saved.commit()
        saved.write('saved', 'saved index\n')
        saved.git('add', '.')
        saved.write('saved', 'saved work\n')
        saved.write('new', 'saved untracked\n')
        saved.git('stash', 'push', '-qu')
        stash = saved.git('rev-parse', 'refs/stash')
        title = '%{execute("let g:injected=1")} | tabonly\n雪'
        specs = [other.spec('history', title, args=['--range=' + oid + '^!']),
                 repo.spec('diff', 'Index', state='staged'),
                 repo.spec('diff', 'Worktree', state='unstaged'),
                 repo.spec('diff', 'New files', state='untracked', paths_b64=[b64(name)]),
                 other.spec('diff', args=[oid + '^!']),
                 saved.spec('stash', 'Saved stash', stash_oid=stash)]
        expected = [self.expect(specs[0], {'other': {'a': [''], 'b': ['another root']}}, commits=[oid]),
                    self.expect(specs[1], {'working:file.txt': {'a': ['base'], 'b': ['index']}}),
                    self.expect(specs[2], {'working:file.txt': {'a': ['index'], 'b': ['worktree']}}),
                    self.expect(specs[3], {'working:' + name: {'a': [''], 'b': ['untracked']}}),
                    self.expect(specs[4], {'working:other': {'a': [''], 'b': ['another root']}}),
                    self.expect(specs[5], {
                        'working:saved': {'a': ['saved base'], 'b': ['saved work']},
                        'working:new': {'a': [''], 'b': ['saved untracked']},
                        'staged:saved': {'a': ['saved base'], 'b': ['saved index']},
                    }, readonly=True)]
        self.run_views(specs, expected, extra="""
local titles = {}
for _, tab in ipairs(vim.api.nvim_list_tabpages()) do titles[tab] = vim.t[tab].lpke_review_title end
vim.api.nvim_eval_statusline(Lpke_tabline(), {use_tabline=true})
assert(vim.g.injected == nil)
vim.cmd('tabnew')
assert(vim.t.lpke_review_title == nil, 'ordinary tab inherited a review title')
for tab, title in pairs(titles) do assert(vim.t[tab].lpke_review_title == title) end
vim.cmd('tabclose')
""", quit_key=True)

    def test_disjoint_root_and_merge_history(self):
        repo = self.repo
        repo.write('skip', 'unrelated\n')
        repo.commit('Interleaved')
        repo.write('chosen\n[ab]*? |file', 'chosen\n')
        chosen = repo.commit('Chosen')
        repo.git('checkout', '-qb', 'side')
        repo.write('side', 'side\n')
        repo.commit('Side')
        repo.git('checkout', '-q', 'main')
        repo.write('main', 'main\n')
        repo.commit('Main')
        repo.git('merge', '-qm', 'Merge', '--no-ff', 'side')
        merge = repo.git('rev-parse', 'HEAD')
        specs = [repo.spec('history', title, args=['--range=' + oid + '^!', '--diff-merges=first-parent'])
                 for title, oid in [('Root', self.base), ('Chosen', chosen), ('Merge', merge)]]
        self.run_views(specs, [
            self.expect(specs[0], {'file.txt': {'a': [''], 'b': ['base']}}, commits=[self.base]),
            self.expect(specs[1], {'chosen\n[ab]*? |file': {'a': [''], 'b': ['chosen']}}, commits=[chosen]),
            self.expect(specs[2], {'side': {'a': [''], 'b': ['side']}}, commits=[merge]),
        ])

    def test_legacy_history_follows_literal_renames_without_losing_earlier_contents(self):
        repo = self.repo
        old = 'old\t[ab]*? |name.txt'
        middle = 'middle\n[ab]*? |name.txt'
        new = 'new\t[ab]*? |name.txt'
        repo.write(old, 'original saved contents\n')
        original = repo.commit('Original file')
        repo.git('mv', '--', old, middle)
        repo.write('unrelated', 'exclude this file\n')
        first = repo.commit('First rename and unrelated work')
        repo.git('mv', '--', middle, new)
        repo.write('unrelated', 'exclude changed contents\n')
        second = repo.commit('Second rename')
        spec = repo.spec('history', 'History')
        self.run_views([spec], [self.expect(spec, {
            old: {'a': [''], 'b': ['original saved contents']},
            middle: {'a': ['original saved contents'], 'b': ['original saved contents'], 'oldpath': old},
            new: {'a': ['original saved contents'], 'b': ['original saved contents'], 'oldpath': middle},
        }, commits=[original, first, second])], gview_args=[str(repo.path), 'history', '--', new])

    def make_stash(self):
        repo = self.repo
        repo.write('deleted', 'delete me\n')
        repo.write('old', 'rename me\n')
        repo.commit('Stash base')
        repo.git('mv', 'old', 'new [x]')
        repo.git('rm', '-q', 'deleted')
        repo.write('file.txt', 'saved staged\n')
        repo.write('added', 'added\n')
        repo.git('add', '.')
        repo.write('file.txt', 'saved worktree\n')
        repo.write('untracked\n|file', 'saved untracked\n')
        repo.write('binary', b'\x00\x01binary\xff')
        (repo.path / 'link').symlink_to('file.txt')
        repo.git('stash', 'push', '-qu', '-m', 'Saved fixture')
        return repo.git('rev-parse', 'refs/stash')

    def stash_expected(self, spec):
        return self.expect(spec, {
            'working:file.txt': {'a': ['base'], 'b': ['saved worktree']},
            'working:added': {'a': [''], 'b': ['added']},
            'working:deleted': {'a': ['delete me'], 'b': ['']},
            'working:new [x]': {'a': ['rename me'], 'b': ['rename me'], 'oldpath': 'old'},
            'working:untracked\n|file': {'a': [''], 'b': ['saved untracked']},
            'working:binary': {'a': [''], 'b': [''], 'binary': True},
            'working:link': {'a': [''], 'b': ['file.txt']},
            'staged:file.txt': {'a': ['base'], 'b': ['saved staged']},
            'staged:added': {'a': [''], 'b': ['added']},
            'staged:deleted': {'a': ['delete me'], 'b': ['']},
            'staged:new [x]': {'a': ['rename me'], 'b': ['rename me'], 'oldpath': 'old'},
        }, readonly=True)

    def test_stash_immutable_after_apply_pop_conflict_and_drop(self):
        oid = self.make_stash()
        spec = self.repo.spec('stash', 'Saved stash', stash_oid=oid)
        def review():
            self.run_views([spec], [self.stash_expected(spec)], extra='''
local view = require('diffview.lib').views[1]
require('diffview.actions').stage_all()
require('diffview.actions').unstage_all()
view.panel:focus()
for _, key in ipairs({'s','S','U','X','I','cc'}) do
  vim.fn.maparg(key, 'n', false, true).callback()
end
''')
        review()
        self.repo.git('stash', 'apply', '--index')
        review()
        self.repo.git('reset', '--hard', 'HEAD')
        self.repo.git('clean', '-fd')
        self.repo.git('stash', 'pop', '--index')
        self.assertEqual(self.repo.git('stash', 'list'), '')
        review()
        self.repo.git('reset', '--hard', 'HEAD')
        self.repo.git('clean', '-fd')
        self.repo.write('file.txt', 'conflicting current\n')
        self.repo.commit('Conflicting commit')
        self.repo.git('stash', 'apply', oid, check=False)
        self.assertIn('UU', self.repo.git('status', '--porcelain'))
        review()

    def test_stash_missing_or_non_stash_is_rejected(self):
        # The startup helper throws a clear error, exercised in a real process
        # without asking the normal probe to wait for a view that must not open.
        from helpers.git_review import CONFIG
        import subprocess
        removed = self.make_stash()
        self.repo.git('stash', 'drop', '-q')
        self.repo.git('reflog', 'expire', '--expire=now', '--all')
        self.repo.git('gc', '--prune=now')
        before = self.repo.snapshot()
        script = self.root / 'reject.lua'
        script.write_text('''
vim.opt.rtp:prepend(vim.env.REVIEW_CONFIG)
vim.opt.rtp:prepend(vim.fn.expand('~/.local/share/nvim/lazy/diffview.nvim'))
require('diffview').setup({})
local stash = require('lpke.plugins.git.helpers.stash_view')
local raw = 'raw' .. string.char(255, 9, 10) .. '[ab]*? |name'
local paths = require('lpke.plugins.git.helpers.state_view').literal_paths({paths_b64={vim.base64.encode(raw)}})
assert(paths[1] == ':(top,literal)' .. raw, 'raw-byte transport changed')
for _, test in ipairs({{string.rep('0',40), 'unavailable'}, {vim.env.REVIEW_BASE, 'not a stash'}, {vim.env.REVIEW_MISSING, 'unavailable'}}) do
  local ok, err = pcall(stash.open, {repo_b64=vim.base64.encode(vim.env.REVIEW_REPO), stash_oid=test[1]})
  assert(not ok and tostring(err):find(test[2],1,true), tostring(err))
end
print('REJECTION_PASS')
vim.cmd('qa!')
''')
        import os
        result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-n', '-l', str(script)],
                                env=dict(fixture_environment(), REVIEW_CONFIG=str(CONFIG), REVIEW_BASE=self.base,
                                         REVIEW_REPO=str(self.repo.path), REVIEW_MISSING=removed,
                                         XDG_STATE_HOME=str(self.root / 'state'),
                                         XDG_CACHE_HOME=str(self.root / 'cache')), capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('REJECTION_PASS', result.stderr + result.stdout)
        self.assertEqual(before, self.repo.snapshot())

    def test_literal_explicit_diff_paths_and_conflicts(self):
        repo = self.repo
        name = 'literal[ab]*?\t\n|file'
        repo.write(name, 'literal base\n')
        repo.write('literala-match-file', 'excluded\n')
        base = repo.commit()
        repo.write(name, 'literal saved\n')
        repo.write('literala-match-file', 'excluded changed\n')
        tip = repo.commit()
        diff = repo.spec('diff', 'Literal diff', args=[base + '..' + tip], paths_b64=[b64(name)])
        repo.git('checkout', '-qb', 'side')
        repo.write('file.txt', 'theirs\n')
        repo.commit()
        repo.git('checkout', '-q', 'main')
        repo.write('file.txt', 'ours\n')
        repo.commit()
        repo.git('merge', 'side', check=False)
        history = repo.spec('history', 'Filtered history', args=['--range=' + tip + '^!'], paths_b64=[b64(name)])
        conflict = repo.spec('diff', 'Conflict', state='conflicted', paths_b64=[b64('file.txt')])
        self.run_views([diff, history, conflict], [
            self.expect(diff, {'working:' + name: {'a': ['literal base'], 'b': ['literal saved']}}),
            self.expect(history, {name: {'a': ['literal base'], 'b': ['literal saved']}}, commits=[tip]),
            self.expect(conflict, {'conflicting:file.txt': {
                'a': ['ours'], 'b': (repo.path / 'file.txt').read_text().splitlines(),
                'c': ['theirs'], 'd': ['base'],
            }}),
        ])
        history['title'] = 'History'
        self.run_views([history], [self.expect(history, {
            name: {'a': ['literal base'], 'b': ['literal saved']},
        }, commits=[tip])], gview_args=[str(repo.path), 'history', tip + '^!', '--', name])

    def test_raw_byte_root_and_untracked_names(self):
        import os
        import errno
        try:
            self.repo.path = self.repo.path.rename(self.root / os.fsdecode(b'repo-\xff '))
        except OSError as error:
            if error.errno in (errno.EILSEQ, errno.EINVAL):
                self.skipTest('filesystem rejects physical non-UTF8 paths: ' + str(error))
            raise
        name = os.fsdecode(b'new-\xff\t\n|file')
        self.repo.write(name, 'raw byte contents\n')
        spec = self.repo.spec('diff', 'Raw byte file', state='untracked', paths_b64=[b64(name)])
        self.run_views([spec], [self.expect(spec, {'working:' + name: {'a': [''], 'b': ['raw byte contents']}})])

    def test_stash_without_untracked_survives_explicit_drop(self):
        repo = self.repo
        repo.write('file.txt', 'first saved\n')
        repo.git('stash', 'push', '-q')
        oid = repo.git('rev-parse', 'refs/stash')
        repo.write('file.txt', 'second saved\n')
        repo.git('stash', 'push', '-q')
        repo.git('stash', 'drop', '-q', 'stash@{1}')
        self.assertNotEqual(repo.git('rev-parse', 'refs/stash'), oid)
        spec = repo.spec('stash', 'Dropped stash', stash_oid=oid)
        self.run_views([spec], [self.expect(spec, {
            'working:file.txt': {'a': ['base'], 'b': ['first saved']},
        }, readonly=True)])

    def test_stash_submodule_uses_saved_patch(self):
        repo = self.repo
        source = Repo(self.root / 'module source')
        source.write('module.txt', 'module base\n')
        source.commit()
        repo.git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', str(source.path), 'module')
        repo.commit('Add submodule')
        module = repo.path / 'module'
        import subprocess
        (module / 'module.txt').write_text('module saved\n')
        subprocess.run(['git', '-C', str(module), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                        '-c', 'core.hooksPath=/dev/null', 'commit', '-qam', 'Saved module'], check=True, env=fixture_environment())
        repo.git('add', 'module')
        patch = repo.git('diff', '--cached', '--submodule=diff', '--no-ext-diff', '--no-color',
                         '--ignore-submodules=none', '--', 'module').splitlines()
        repo.write('file.txt', 'saved with module\n')
        repo.git('stash', 'push', '-q')
        oid = repo.git('rev-parse', 'refs/stash')
        spec = repo.spec('stash', 'Saved module', stash_oid=oid)
        self.run_views([spec], [self.expect(spec, {
            'working:file.txt': {'a': ['base'], 'b': ['saved with module']},
            'working:module': {'a': [''], 'b': patch},
            'staged:module': {'a': [''], 'b': patch},
        }, readonly=True)])


if __name__ == '__main__':
    unittest.main()
