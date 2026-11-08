"""Run: python3 tests/git_review.py. Every case creates and removes real repos."""
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

from helpers.git_review import CONFIG, Harness, Repo, b64, fixture_environment, probe


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
        try:
            return probe(self.root, specs, expected, **kwargs)
        finally:
            self.assertEqual(before, [repo.snapshot() for repo in repos], 'review changed repository')

    def test_range_preserves_every_version_and_rejects_ambiguous_oracles(self):
        repo = self.repo
        versions = []
        previous = 'base'
        for number in range(1, 4):
            current = 'saved version ' + str(number)
            repo.write('file.txt', current + '\n')
            oid = repo.commit('Successive edit ' + str(number))
            versions.insert(0, dict(commit=oid, path='file.txt', a=[previous], b=[current]))
            previous = current
        spec = repo.spec('history', 'Three versions % literal',
                         args=['--range=' + self.base + '..' + versions[0]['commit']])
        want = self.expect(spec, {}, commits=[v['commit'] for v in versions], versions=versions)
        self.run_views([spec], [want])
        # Prove the oracle checks an earlier commit rather than only the tip.
        from copy import deepcopy
        wrong = deepcopy(want)
        wrong['versions'][-1]['b'] = ['wrong earlier version']
        with self.assertRaisesRegex(AssertionError, 'wrong b'):
            self.run_views([spec], [wrong])
        wrong = deepcopy(want)
        wrong['versions'].reverse()
        with self.assertRaisesRegex(AssertionError, 'wrong history sequence'):
            self.run_views([spec], [wrong])
        with self.assertRaisesRegex(AssertionError, 'ambiguous history path'):
            self.run_views([spec], [self.expect(spec, {
                'file.txt': dict(a=['saved version 2'], b=['saved version 3'])
            }, commits=[v['commit'] for v in versions])])

    def test_hostile_environment_and_concurrent_boots_leave_sources_untouched(self):
        import os
        import shutil
        from concurrent.futures import ThreadPoolExecutor
        from unittest.mock import patch
        from helpers import git_review as helper
        hostile = self.root / 'foreign-user'
        hostile.mkdir()
        source = self.root / 'source-copy'
        shutil.copytree(CONFIG, source, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        # A broad production Lazy import would run this destructive startup hook.
        (source / 'lua/lpke/plugins/hostile_probe.lua').write_text(
            "return {'hostile/plugin', lazy=false, init=function() error('UNRELATED STARTUP') end}\n")
        for relative in ('data/nvim/mason/registries/github/mason-org/mason-registry/registry.json',
                         'data/nvim/harpoon/marks', 'data/nvim/sessions/sentinel',
                         'state/nvim/shada/main.shada', 'cache/nvim/sentinel',
                         'config/foreign/init.lua', 'config/nvim-local/init.lua'):
            target = hostile / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('hostile sentinel: invalid registry and startup contents\n')
        trap = hostile / 'bin'
        trap.mkdir()
        for name in ('curl', 'wget', 'ssh', 'xclip', 'xsel', 'wl-copy', 'wl-paste', 'pbcopy', 'pbpaste'):
            path = trap / name
            path.write_text('#!/bin/sh\nprintf touched >> ' + str(hostile / 'external-activity') + '\nexit 91\n')
            path.chmod(0o755)
        def snapshot(path):
            return {str(p.relative_to(path)): (p.stat().st_mode, p.stat().st_mtime_ns, p.read_bytes())
                    for p in path.rglob('*') if p.is_file()}
        plugin_copy = hostile / 'installed-plugins'
        for name in helper.PLUGINS:
            shutil.copytree(helper.plugin_source() / name, plugin_copy / name,
                            ignore=shutil.ignore_patterns('.git', '__pycache__'), symlinks=False)
        before = snapshot(hostile), snapshot(source)
        script = self.root / 'isolation.lua'
        script.write_text("""
vim.fn.setreg('+', {'private plus'})
vim.fn.setreg('*', {'private star'})
assert(vim.fn.getreg('+') == 'private plus\\n')
assert(vim.fn.getreg('*') == 'private star\\n')
assert(vim.g.loaded_python3_provider == 0 and vim.g.loaded_node_provider == 0)
for _, kind in ipairs({'data', 'cache', 'state', 'config'}) do
  vim.fn.writefile({'private write'}, vim.fn.stdpath(kind) .. '/harness-sentinel')
end
Lpke_review_harness_check()
print('ISOLATION_PASS')
vim.cmd('qa!')
""")
        env = dict(os.environ, HOME=str(hostile), NVIM_APPNAME='foreign',
                   VIMINIT='lua error("FOREIGN VIMINIT")', SSH_CONNECTION='hostile ssh session',
                   DISPLAY=':hostile', WAYLAND_DISPLAY='hostile-wayland',
                   LPKE_NVIM_DIFFVIEW_VIEWS='invalid inherited plan',
                   LPKE_NVIM_NO_SESSION='0', XDG_DATA_HOME=str(hostile / 'data'),
                   XDG_CONFIG_HOME=str(hostile / 'config'), XDG_CACHE_HOME=str(hostile / 'cache'),
                   XDG_STATE_HOME=str(hostile / 'state'),
                   PATH=str(trap) + os.pathsep + os.environ['PATH'])
        def boot(number):
            with Harness(self.root / ('boot-' + str(number)), script, env=env) as harness:
                private = harness.root
                result = harness.run(marker='ISOLATION_PASS')
                self.assertTrue((harness.config / 'harness-sentinel').is_file())
                self.assertFalse((private / 'data/nvim/mason').exists())
                self.assertFalse((private / 'data/nvim/harpoon').exists())
            self.assertFalse(private.exists(), 'private boot was not cleaned')
            return result
        with patch.object(helper, 'CONFIG', source), patch.dict(os.environ,
                GIT_REVIEW_NVIM_PLUGINS=str(plugin_copy)):
            with ThreadPoolExecutor(max_workers=3) as workers:
                list(workers.map(boot, range(3)))
        self.assertEqual(before, (snapshot(hostile), snapshot(source)))

    def test_forbidden_activity_fails_even_when_caught_and_cleans_up(self):
        actions = {
            'process': "vim.system({'curl', 'https://example.invalid'})",
            'git config mutation': "vim.system({'git', 'config', 'user.name', 'rogue'})",
            'git network': "vim.system({'git', 'fetch', 'https://example.invalid'})",
            'libuv network': "vim.uv.new_tcp()",
            'Mason refresh': "require('mason-registry').refresh()",
            'Harpoon startup': "require('harpoon')",
        }
        for label, action in actions.items():
            with self.subTest(label=label):
                script = self.root / 'forbidden.lua'
                script.write_text("pcall(function() " + action + " end)\n"
                                  "local ok, err = pcall(Lpke_review_harness_check)\n"
                                  "assert(not ok, 'guard did not record forbidden activity')\n"
                                  "io.stderr:write(tostring(err))\nvim.cmd('cquit 1')\n")
                with self.assertRaisesRegex(AssertionError, 'process curl|git command fetch|git command config|network new_tcp|unrelated module'):
                    with Harness(self.root, script) as harness:
                        private = harness.root
                        harness.run()
                self.assertFalse(private.exists())

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

    def test_empty_review_panes_keep_the_title_without_inventing_a_file(self):
        spec = self.repo.spec('diff', 'Clean review', state='unstaged')
        self.run_views([spec], [self.expect(spec, {})], extra=r'''
local view = require('diffview.lib').views[1]
for _, win in ipairs(view.cur_layout.windows) do
  vim.api.nvim_set_current_win(win.id)
  assert(require('lpke.plugins.git.helpers.review_labels').current() == 'Clean review')
end
''')

    def test_diff_labels_follow_shared_buffers_and_disambiguate_filenames(self):
        repo = self.repo
        for folder in ('left', 'right'):
            repo.write(folder + '/same.txt', 'base\n')
        repo.commit()
        repo.write('file.txt', 'index\n')
        repo.git('add', '--', 'file.txt')
        repo.write('file.txt', 'worktree\n')
        for folder in ('left', 'right'):
            repo.write(folder + '/same.txt', folder + '\n')
        name = 'literal%{execute("let g:injected=1")}\n雪.txt'
        repo.write(name, 'literal\n')
        title = '%{execute("let g:injected=1")}\nTitle'
        specs = [repo.spec('diff', 'Index', state='staged', paths=['file.txt']),
                 repo.spec('diff', 'Worktree', state='unstaged', paths=['file.txt']),
                 repo.spec('diff', 'Another review', state='unstaged', paths=['file.txt']),
                 repo.spec('diff', 'Duplicate names', state='unstaged', paths=['left/same.txt', 'right/same.txt']),
                 repo.spec('diff', title, state='untracked', paths_b64=[b64(name)])]
        expected = [self.expect(specs[0], {'working:file.txt': dict(a=['base'], b=['index'], labels={
                        'a': 'BEFORE: file.txt | Index', 'b': 'AFTER: file.txt | Index'})}),
                    self.expect(specs[1], {'working:file.txt': dict(a=['index'], b=['worktree'], labels={
                        'a': 'BEFORE: file.txt | Worktree', 'b': 'AFTER: file.txt | Worktree'})}),
                    self.expect(specs[2], {'working:file.txt': dict(a=['index'], b=['worktree'], labels={
                        'a': 'BEFORE: file.txt | Another review', 'b': 'AFTER: file.txt | Another review'})}),
                    self.expect(specs[3], {'working:' + folder + '/same.txt': dict(a=['base'], b=[folder], labels={
                        'a': 'BEFORE: ' + folder + '/same.txt | Duplicate names',
                        'b': 'AFTER: ' + folder + '/same.txt | Duplicate names'}) for folder in ('left', 'right')}),
                    self.expect(specs[4], {'working:' + name: dict(a=[''], b=['literal'], labels={
                        'a': 'BEFORE: ' + name + ' | ' + title, 'b': 'AFTER: ' + name + ' | ' + title})})]
        self.run_views(specs, expected, extra=r'''
local views = require('diffview.lib').views
assert(views[1].cur_layout.b.file.bufnr == views[2].cur_layout.a.file.bufnr, 'index not actually shared')
local live = views[2].cur_layout.b.file.bufnr
assert(live == views[3].cur_layout.b.file.bufnr, 'worktree not actually shared')
local labels = require('lpke.plugins.git.helpers.review_labels')
local filename = dofile(vim.fn.stdpath('config') .. '/tests/helpers/git_review_statusline.lua')
for _, view in ipairs(views) do
  vim.api.nvim_set_current_tabpage(view.tabpage)
  for _, win in ipairs(view.cur_layout.windows) do
    vim.api.nvim_set_current_win(win.id)
    local label = assert(labels.current())
    local visible = label:gsub('[%z\1-\31\127]', function(c) return string.format('\\x%02x', c:byte()) end)
    assert(vim.api.nvim_eval_statusline(filename('native filename'), {maxwidth=10000}).str == visible)
    Lpke_format_bufname = false
    assert(filename('native filename') == 'native filename')
    Lpke_format_bufname = true
  end
end
local native = vim.api.nvim_buf_get_name(live)
assert(native == views[2].adapter.ctx.toplevel .. '/file.txt', 'live save target changed')
vim.cmd('tabnew')
vim.api.nvim_win_set_buf(0, live)
assert(labels.current() == nil, 'review label leaked into ordinary file window')
assert(filename('native filename') == 'native filename')
vim.cmd('tabclose')
vim.api.nvim_set_current_tabpage(views[2].tabpage)
local win = views[2].cur_layout.b.id
vim.api.nvim_set_current_win(win)
vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(false, true))
assert(labels.current() == nil, 'review label remained after opening another buffer')
vim.api.nvim_win_set_buf(win, live)
assert(labels.current() == 'AFTER: file.txt | Worktree')
assert(vim.g.injected == nil)
''')

    def test_renamed_file_diff_labels_use_the_correct_side_filename(self):
        self.repo.git('mv', '--', 'file.txt', 'renamed.txt')
        spec = self.repo.spec('diff', 'Rename', state='staged')
        self.run_views([spec], [self.expect(spec, {'working:renamed.txt': dict(
            a=['base'], b=['base'], oldpath='file.txt', labels={
                'a': 'BEFORE: file.txt | Rename', 'b': 'AFTER: renamed.txt | Rename'})})])

    def test_diff_label_filename_ambiguity_refreshes_with_the_real_file_list(self):
        repo = self.repo
        repo.write('left/same.txt', 'left\n')
        repo.write('right/same.txt', 'right\n')
        before = repo.snapshot()
        after_files = dict(before[0])
        after_files.pop('right/same.txt')
        after_files.pop('left/same.txt')
        spec = repo.spec('diff', 'Refresh', state='untracked')
        expected = self.expect(spec, {'working:' + folder + '/same.txt': dict(a=[''], b=[folder])
                                      for folder in ('left', 'right')})
        probe(self.root, [spec], [expected], extra=r'''
local view = require('diffview.lib').views[1]
local labels = require('lpke.plugins.git.helpers.review_labels')
local target
for _, entry in view.files:iter() do if entry.path == 'left/same.txt' then target = entry end end
local opened = false
view:set_file(assert(target)):finally(function() opened = true end)
assert(vim.wait(15000, function() return opened end, 20))
vim.api.nvim_set_current_win(view.cur_layout.a.id)
assert(labels.current() == 'BEFORE: left/same.txt | Refresh')
local root = view.adapter.ctx.toplevel
assert(vim.fn.delete(root .. '/right/same.txt') == 0)
vim.fn.writefile({'other'}, root .. '/other.txt')
local updated = false
view:update_files(function(err) assert(not err, vim.inspect(err)); updated = true end)
assert(vim.wait(15000, function() return updated end, 20), 'refresh did not complete')
assert(view.files:len() == 2, 'refresh must retain the same file count')
assert(view.cur_entry == target, 'refresh should retain the selected entry')
vim.api.nvim_set_current_win(view.cur_layout.a.id)
assert(labels.current() == 'BEFORE: same.txt | Refresh', 'cached ambiguity survived refresh')
assert(vim.fn.delete(root .. '/left/same.txt') == 0)
assert(vim.fn.delete(root .. '/other.txt') == 0)
updated = false
view:update_files(function(err) assert(not err, vim.inspect(err)); updated = true end)
assert(vim.wait(15000, function() return updated end, 20))
assert(view.files:len() == 0 and view.nulled, 'review did not become empty')
for _, win in ipairs(view.cur_layout.windows) do
  vim.api.nvim_set_current_win(win.id)
  assert(labels.current() == 'Refresh', 'empty review retained the previous filename')
end
''')
        actual = repo.snapshot()
        self.assertEqual(actual[0], after_files, 'refresh changed other repository files/index')
        self.assertEqual(actual[2:], before[2:], 'refresh changed refs or stash state')
        self.assertEqual(repo.git('ls-files', '--others', '--exclude-standard'), '')

    def test_review_buffer_titles_are_unique_and_render_literally(self):
        self.repo.write('file.txt', 'worktree\n')
        title = '%{execute("let g:injected=1")} | tabonly\n雪 / ../../scheme://evil'
        specs = [self.repo.spec('history', '1 new commit', args=['--range=' + self.base + '^!']),
                 self.repo.spec('history', '1 new commit', args=['--range=' + self.base + '^!']),
                 self.repo.spec('diff', title, state='unstaged'),
                 self.repo.spec('diff', state='unstaged')]
        expected = [self.expect(spec, {'file.txt': {'a': [''], 'b': ['base']}}, commits=[self.base])
                    for spec in specs[:2]]
        expected += [self.expect(spec, {'working:file.txt': {'a': ['base'], 'b': ['worktree']}})
                     for spec in specs[2:]]
        self.run_views(specs, expected, extra=r'''
local lib = require('diffview.lib')
local first, second = lib.views[1].panel, lib.views[2].panel
assert(first.bufid ~= second.bufid)
assert(vim.api.nvim_buf_get_name(first.bufid) ~= vim.api.nvim_buf_get_name(second.bufid))
assert(vim.api.nvim_buf_is_valid(first.bufid) and vim.api.nvim_buf_is_valid(second.bufid))
local filename = {fmt = dofile(vim.fn.stdpath('config') .. '/tests/helpers/git_review_statusline.lua')}
for index, view in ipairs(lib.views) do
  vim.api.nvim_set_current_tabpage(view.tabpage)
  vim.api.nvim_set_current_win(view.panel.winid)
  local label = filename.fmt('raw buffer')
  if index < 4 then
    local expected = vim.b.lpke_review_title:gsub('[%z\1-\31\127]', function(c)
      return string.format('\\x%02x', c:byte())
    end)
    assert(vim.api.nvim_eval_statusline(label, {}).str == expected, 'wrong visible buffer title')
    Lpke_format_bufname = false
    assert(filename.fmt('raw buffer') == 'raw buffer', 'raw-name toggle changed')
    Lpke_format_bufname = true
  else
    assert(vim.b.lpke_review_title == nil, 'legacy review inherited a buffer title')
    assert(label == 'Diffview Files (:DiffviewOpen)', 'legacy statusline changed')
  end
end
assert(vim.g.injected == nil, 'buffer title executed statusline syntax')
''')

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

    def test_single_file_history_ignores_unavailable_excluded_changes_and_follows_renames(self):
        self.other_repos = []
        for renamed in (False, True):
            repo = Repo(self.root / ('renamed' if renamed else 'modified'))
            self.other_repos.append(repo)
            old, new = 'selected\t*?[x]', 'renamed\nselected*'
            original = ['selected base'] * 20
            repo.write(old, '\n'.join(original) + '\n')
            repo.write('excluded', 'excluded before\n')
            base = repo.commit()
            if renamed:
                repo.git('mv', '--', old, new)
            else:
                new = old
            updated = original + ['selected edit']
            repo.write(new, '\n'.join(updated) + '\n')
            repo.write('excluded', 'excluded missing contents\n')
            tip = repo.commit()
            oid = repo.git('rev-parse', tip + ':excluded')
            blob = repo.path / '.git/objects' / oid[:2] / oid[2:]
            saved = blob.read_bytes()
            blob.unlink()
            try:
                self.assertIn('1\t0\t', repo.git('diff', '--numstat', base, tip, '--', old, new))
                spec = repo.spec('history', 'History')
                content = dict(a=original, b=updated)
                if renamed:
                    content['oldpath'] = old
                self.run_views([spec], [self.expect(spec, {new: content}, commits=[tip])],
                               gview_args=[str(repo.path), 'history', tip + '^!', '--', new])
            finally:
                blob.write_bytes(saved)
            if renamed:
                repo.write(old, 'separate reused filename\n')
                latest = updated + ['later selected edit']
                repo.write(new, '\n'.join(latest) + '\n')
                tip = repo.commit('Reuse old filename separately')
                oid = repo.git('rev-parse', tip + ':' + old)
                blob = repo.path / '.git/objects' / oid[:2] / oid[2:]
                saved = blob.read_bytes()
                blob.unlink()
                try:
                    self.run_views([spec], [self.expect(spec, {new: dict(a=updated, b=latest)}, commits=[tip])],
                                   gview_args=[str(repo.path), 'history', tip + '^!', '--', new])
                finally:
                    blob.write_bytes(saved)

    def test_single_file_merge_uses_its_first_parent_comparison(self):
        repo = self.repo
        repo.write('other', 'base other\n')
        repo.commit()
        repo.git('checkout', '-qb', 'side')
        repo.write('file.txt', 'side\n')
        repo.commit()
        repo.git('checkout', '-q', 'main')
        repo.write('other', 'main\n')
        first_parent = repo.commit()
        repo.git('merge', '--no-ff', '-qm', 'merge', 'side')
        merge = repo.git('rev-parse', 'HEAD')
        self.assertEqual(repo.git('diff', '--numstat', first_parent, merge, '--', 'file.txt'), '1\t1\tfile.txt')
        self.assertIn(merge, repo.git('log', '--format=%H', '--follow', '--diff-merges=first-parent', merge + '^!', '--', 'file.txt'))
        spec = repo.spec('history', 'History')
        self.run_views([spec], [self.expect(spec, {'file.txt': dict(a=['base'], b=['side'])}, commits=[merge])],
                       gview_args=[str(repo.path), 'history', merge + '^!', '--', 'file.txt'])

    def test_explicit_ranges_include_all_257_commits_through_legacy_and_plan_routes(self):
        import base64
        import json
        import socket
        repo = self.repo
        repo.write('file.txt', 'v0\n')
        base = repo.commit()
        ids, versions = [], []
        for index in range(1, 258):
            repo.write('file.txt', f'v{index}\n')
            oid = repo.commit(f'Change {index}')
            ids.append(oid)
            version = dict(commit=oid, path='file.txt')
            if index in (1, 257):
                version.update(a=[f'v{index - 1}'], b=[f'v{index}'])
            versions.insert(0, version)
        revision = base + '..' + ids[-1]
        self.assertEqual(repo.git('rev-list', revision).splitlines(), list(reversed(ids)))
        spec = repo.spec('history', 'History')
        expected = self.expect(spec, {}, commits=ids, versions=versions)
        self.run_views([spec], [expected], gview_args=[str(repo.path), 'history', revision])
        self.run_views([spec], [expected], gview_args=[str(repo.path), 'history', revision, '--', 'file.txt'])
        plan = {'version': 1, 'hosts': {socket.gethostname(): {'repo': str(repo.path),
                'views': [dict(kind='history', title='History', revisions=[revision])]}}}
        token = base64.urlsafe_b64encode(json.dumps(plan).encode()).decode().rstrip('=')
        self.run_views([spec], [expected], gview_args=['--plan', token])

    def test_history_drains_metadata_after_the_git_process_exits(self):
        import os
        import shutil
        from unittest.mock import patch
        if not hasattr(os, 'fork'):
            self.skipTest('delayed pipe EOF fixture requires POSIX fork')
        binary = self.root / 'delayed-git-bin'
        binary.mkdir()
        actual_git = shutil.which('git')
        marker = self.root / 'metadata-flushed'
        wrapper = binary / 'git'
        wrapper.write_text('#!' + sys.executable + '\n' + '''import os,subprocess,sys,time
real = ''' + repr(actual_git) + '''
args = sys.argv[1:]
if 'log' in args and any('%x00' in arg for arg in args):
    data = subprocess.check_output([real, *args])
    if os.fork():
        os._exit(0)
    time.sleep(0.05)
    os.write(1, data)
    open(''' + repr(str(marker)) + ''', 'w').write('flushed')
    os._exit(0)
os.execv(real, [real, *args])
''')
        wrapper.chmod(0o755)
        spec = self.repo.spec('history', 'History')
        with patch.dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH']):
            self.run_views([spec], [self.expect(spec, {'file.txt': dict(a=[''], b=['base'])}, commits=[self.base])],
                           gview_args=[str(self.repo.path), 'history', self.base + '^!'])
        self.assertTrue(marker.exists(), 'fixture did not delay Git output until after process exit')

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
        removed = self.make_stash()
        self.repo.git('stash', 'drop', '-q')
        self.repo.git('reflog', 'expire', '--expire=now', '--all')
        self.repo.git('gc', '--prune=now')
        before = self.repo.snapshot()
        script = self.root / 'reject.lua'
        script.write_text('''
local stash = require('lpke.plugins.git.helpers.stash_view')
local raw = 'raw' .. string.char(255, 9, 10) .. '[ab]*? |name'
local paths = require('lpke.plugins.git.helpers.state_view').literal_paths({paths_b64={vim.base64.encode(raw)}})
assert(paths[1] == ':(top,literal)' .. raw, 'raw-byte transport changed')
for _, test in ipairs({{string.rep('0',40), 'unavailable'}, {vim.env.REVIEW_BASE, 'not a stash'}, {vim.env.REVIEW_MISSING, 'unavailable'}}) do
  local ok, err = pcall(stash.open, {repo_b64=vim.base64.encode(vim.env.REVIEW_REPO), stash_oid=test[1]})
  assert(not ok and tostring(err):find(test[2],1,true), tostring(err))
end
Lpke_review_harness_check()
print('REJECTION_PASS')
vim.cmd('qa!')
''')
        with Harness(self.root, script) as harness:
            harness.run(extra_env=dict(REVIEW_BASE=self.base, REVIEW_REPO=str(self.repo.path),
                                       REVIEW_MISSING=removed), marker='REJECTION_PASS')
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

    def test_general_diff_retains_conflicts_with_ordinary_and_literal_paths(self):
        repo = self.repo
        name = 'conflict*?[x]\n.txt'
        repo.write(name, 'base conflict\n')
        repo.write('ordinary', 'base ordinary\n')
        repo.commit()
        repo.git('checkout', '-qb', 'other')
        repo.write(name, 'theirs\n')
        repo.commit()
        repo.git('checkout', '-q', 'main')
        repo.write(name, 'ours\n')
        repo.commit()
        repo.git('merge', 'other', check=False)
        repo.write('ordinary', 'ordinary edit\n')
        self.assertIn('UU ', repo.git('status', '--porcelain'))
        conflict = {'a': ['ours'], 'b': (repo.path / name).read_text().splitlines(),
                    'c': ['theirs'], 'd': ['base conflict']}
        ordinary = {'a': ['base ordinary'], 'b': ['ordinary edit']}
        general = repo.spec('diff', 'Diff')
        self.run_views([general], [self.expect(general, {
            'conflicting:' + name: conflict, 'working:ordinary': ordinary,
        })], extra="assert(require('diffview.lib').views[1].files:len() == 2)",
            gview_args=[str(repo.path), 'diff'])
        filtered = repo.spec('diff', 'Diff', paths_b64=[b64(name)])
        self.run_views([filtered], [self.expect(filtered, {'conflicting:' + name: conflict})],
                       gview_args=[str(repo.path), 'diff', '--', name])
        unstaged = repo.spec('diff', 'Unstaged', state='unstaged', paths_b64=[b64(name), b64('ordinary')])
        self.run_views([unstaged], [self.expect(unstaged, {'working:ordinary': ordinary})])

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
