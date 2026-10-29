-- Real disposable processes; no authenticated agent or existing user process.
-- run-nvim --headless -u NONE -i NONE -l tests/codecompanion_processes.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, name in ipairs({ 'codecompanion.nvim', 'plenary.nvim' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
local native_disconnect = require('codecompanion.acp').disconnect
local uv = vim.uv
local module = 'lpke.plugins.ai.helpers.acp_process'
local original_kill, original_scandir, original_defer =
  uv.kill, uv.fs_scandir, vim.defer_fn
local original_fs_open = uv.fs_open
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. '/bin', 'p')
local checks, scans = 0, 0
local known, handles, signals, native_signals, forbidden = {}, {}, {}, {}, {}
local log, pids = fixture .. '/signals', fixture .. '/pids'
local node_script = fixture
  .. '/node_modules/@agentclientprotocol/codex-acp/dist/index.js'
local original_child_env = vim.env.LPKE_ACP_PROCESS_CHILD
vim.env.LPKE_ACP_PROCESS_CHILD = fixture .. '/bin/codex-acp-leaf'
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function equal(actual, expected, message)
  check(
    vim.deep_equal(actual, expected),
    message
      .. '\n'
      .. vim.inspect(actual)
      .. '\nexpected '
      .. vim.inspect(expected)
  )
end
local function birth(pid, native)
  local fs_open = native and original_fs_open or uv.fs_open
  local fd = fs_open('/proc/' .. pid .. '/stat', 'r', 438)
  if not fd then
    return
  end
  local text = uv.fs_read(fd, 65536, 0)
  uv.fs_close(fd)
  local rest = text and text:match('^%d+ %b() (.*)$')
  local fields = vim.split(rest or '', '%s+', { trimempty = true })
  return fields[20], fields[1]
end
local function alive(pid)
  local start, state = birth(pid)
  return start and state ~= 'Z' and known[pid] == start
end
local function wait_for(predicate, message)
  check(vim.wait(3000, predicate, 5), message)
end
local function flush(ms)
  vim.wait(ms or 25, function()
    return false
  end, 5)
end
local function records()
  local result = {}
  if vim.fn.filereadable(pids) == 0 then
    return result
  end
  for _, line in ipairs(vim.fn.readfile(pids)) do
    local role, pid, parent = line:match('^(.-)\t(%d+)\t(%d+)$')
    if pid then
      pid, parent = tonumber(pid), tonumber(parent)
      known[pid] = known[pid] or birth(pid)
      result[#result + 1] = { role = role, pid = pid, parent = parent }
    end
  end
  return result
end
local function child_of(parent)
  for _, record in ipairs(records()) do
    if record.parent == parent then
      return record.pid
    end
  end
end
local function spawn(name, role, behavior, next_name, after_name, extra)
  local executable = name == 'real-node' and vim.fn.exepath('node')
    or fixture .. '/bin/' .. name
  if name == 'node' or name == 'systemd' then
    executable = fixture .. '/' .. name
  end
  local args = {
    log,
    pids,
    role,
    behavior or 'ignore',
    next_name or '-',
    after_name or '-',
    extra or '-',
    name == 'systemd' and '--user' or '-',
  }
  if name == 'real-node' then
    args = { node_script, log, pids, next_name or '-' }
  end
  local handle, pid
  handle, pid = uv.spawn(executable, {
    args = args,
    cwd = fixture,
    stdio = { nil, nil, nil },
  }, function()
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)
  assert(handle, 'fixture spawn: ' .. tostring(pid))
  handles[#handles + 1] = handle
  known[pid] = assert(birth(pid), 'fixture process identity')
  return pid
end
local function upvalue(fn, name)
  for index = 1, 100 do
    local key, value = debug.getupvalue(fn, index)
    if not key then
      break
    end
    if key == name then
      return value
    end
  end
  error('Missing private test boundary: ' .. name)
end
local function fresh()
  package.loaded[module] = nil
  local process = require(module)
  local Connection = {
    start_agent_process = function()
      return true
    end,
    disconnect = native_disconnect,
  }
  process.patch(Connection)
  local patched = Connection.disconnect
  process.patch(Connection)
  equal(Connection.disconnect, patched, 'process patch is idempotent')
  return process,
    function(pid)
      local conn = { _state = {} }
      conn._state.handle = {
        pid = pid,
        kill = function(_, sig)
          conn.disconnects = (conn.disconnects or 0) + 1
          local number = sig == 'sigterm' and 15 or sig
          if not known[pid] or known[pid] ~= birth(pid, true) then
            forbidden[#forbidden + 1] = { pid, number, 'native' }
            error('Native disconnect targeted an unowned/reused fixture PID')
          end
          native_signals[#native_signals + 1] = { pid = pid, sig = number }
          return original_kill(pid, number)
        end,
      }
      return setmetatable(conn, { __index = Connection })
    end
end
local function signal_count(pid, sig)
  local count = 0
  for _, source in ipairs({ signals, native_signals }) do
    for _, event in ipairs(source) do
      if event.pid == pid and event.sig == sig then
        count = count + 1
      end
    end
  end
  return count
end

local function run()
  check(
    debug
      .getinfo(native_disconnect, 'S').source
      :find('/codecompanion/acp/init.lua', 1, true),
    'native disconnect comes from the pinned ACP source'
  )
  local executable = fixture .. '/bin/codex-acp-root'
  local compile = vim
    .system({
      'cc',
      '-std=c11',
      '-D_POSIX_C_SOURCE=200809L',
      '-Wall',
      '-Wextra',
      '-O0',
      'tests/helpers/acp_process_fixture.c',
      '-o',
      executable,
    }, { text = true })
    :wait()
  check(
    compile.code == 0,
    'compile disposable process fixture: ' .. (compile.stderr or '')
  )
  for _, target in ipairs({
    fixture .. '/bin/codex-acp-leaf',
    fixture .. '/bin/acp-fixture-helper',
    fixture .. '/bin/acp-unrelated',
    fixture .. '/node',
    fixture .. '/systemd',
  }) do
    assert(uv.fs_copyfile(executable, target))
  end
  vim.fn.mkdir(vim.fs.dirname(node_script), 'p')
  assert(uv.fs_copyfile('tests/helpers/acp_process_fixture.js', node_script))
  uv.fs_scandir = function(path, ...)
    if path == '/proc' then
      scans = scans + 1
    end
    return original_scandir(path, ...)
  end
  uv.kill = function(pid, sig)
    if not known[pid] or known[pid] ~= birth(pid) then
      forbidden[#forbidden + 1] = { pid, sig }
      error('Cleanup attempted to signal an unowned/reused fixture PID')
    end
    signals[#signals + 1] = { pid = pid, sig = sig }
    return original_kill(pid, sig)
  end

  local root = spawn(
    'codex-acp-root',
    'tree',
    'ignore',
    fixture .. '/bin/acp-fixture-helper',
    '-'
  )
  local second = spawn('codex-acp-root', 'second')
  local unrelated = spawn('codex-acp-root', 'unrelated')
  wait_for(function()
    return child_of(root) and child_of(child_of(root))
  end, 'real child and grandchild start')
  local helper, leaf = child_of(root), child_of(child_of(root))
  local process, connection = fresh()
  local first_conn, second_conn = connection(root), connection(second)
  equal(process.pid(first_conn), root, 'native connection PID shape')
  equal(process.pid({ _state = {} }), nil, 'missing handle has no PID')
  local initial = scans
  first_conn:start_agent_process()
  process.observe(first_conn)
  second_conn:start_agent_process()
  flush()
  equal(scans - initial, 1, 'same-loop observations share one proc snapshot')
  local tracked = upvalue(process.stop_tracked, 'tracked')
  check(
    tracked[root] and tracked[root].children[leaf],
    'ACP descendant found through non-ACP intermediate'
  )
  check(not tracked[root].children[helper], 'non-ACP helper is not signalled')
  check(
    not tracked[root].children[unrelated],
    'unrelated ACP peer is not adopted'
  )
  equal(
    tracked[root].root.fd_targets,
    {},
    'shared dev/null descriptors establish no ownership'
  )
  flush(1100)
  equal(
    scans - initial,
    3,
    '250ms and 1000ms observation batches each share one snapshot'
  )
  local idle_scans = scans
  flush(300)
  equal(
    scans,
    idle_scans,
    'observation discovery stops after its finite window'
  )

  local escalations = {}
  vim.defer_fn = function(callback, ms)
    if ms == 300 then
      escalations[#escalations + 1] = callback
      return
    end
    return original_defer(callback, ms)
  end
  local before = scans
  process.stop_tracked(second)
  equal(scans - before, 1, 'stop sweep takes one snapshot')
  check(alive(second), 'keep PID survives tracked-stop sweep')
  equal(signal_count(second, 15), 0, 'keep PID receives no TERM')
  first_conn:disconnect()
  first_conn:disconnect()
  second_conn:disconnect()
  equal(
    #escalations,
    2,
    'duplicate disconnect schedules no duplicate escalation'
  )
  equal(
    signal_count(root, 15),
    1,
    'owned root receives one TERM across custom and native paths'
  )
  equal(
    first_conn.disconnects,
    nil,
    'owned root cleanup skips redundant native TERM'
  )
  equal(
    second_conn.disconnects,
    nil,
    'second owned root cleanup skips redundant native TERM'
  )
  equal(signal_count(leaf, 15), 1, 'owned descendant receives one TERM')
  equal(signal_count(second, 15), 1, 'second owned root receives one TERM')
  wait_for(function()
    if vim.fn.filereadable(log) == 0 then
      return false
    end
    return #vim.fn.readfile(log) >= 3
  end, 'real processes receive TERM before escalation')
  check(
    alive(root) and alive(leaf),
    'TERM-resistant fixture remains before grace expires'
  )
  flush(310)
  before = scans
  for _, callback in ipairs(escalations) do
    callback()
  end
  flush()
  equal(scans - before, 1, 'one queued escalation batch uses one proc snapshot')
  wait_for(function()
    return not alive(root) and not alive(leaf) and not alive(second)
  end, 'owned process trees terminate after KILL')
  equal(signal_count(root, 9), 1, 'owned root receives one KILL')
  equal(signal_count(leaf, 9), 1, 'owned descendant receives one KILL')
  check(
    alive(unrelated) and alive(helper),
    'unrelated peer and non-ACP helper survive'
  )
  equal(
    signal_count(unrelated, 15) + signal_count(unrelated, 9),
    0,
    'unrelated PID is never signalled'
  )
  vim.defer_fn = original_defer

  local node_root =
    spawn('real-node', 'node-root', 'ignore', fixture .. '/bin/codex-acp-leaf')
  wait_for(function()
    return child_of(node_root)
  end, 'real Node package launcher starts native child')
  local node_leaf = child_of(node_root)
  process, connection = fresh()
  local node_conn = connection(node_root)
  process.observe(node_conn)
  flush()
  tracked = upvalue(process.stop_tracked, 'tracked')
  check(
    tracked[node_root].root and tracked[node_root].root.codex,
    'actual Node package index script is recognized'
  )
  check(
    not tracked[node_root].root.native,
    'Node package launcher is not a native orphan candidate'
  )
  check(
    tracked[node_root].children[node_leaf] ~= nil,
    'Node launcher owns its native ACP child'
  )
  node_conn:disconnect()
  wait_for(function()
    return not alive(node_root) and not alive(node_leaf)
  end, 'real Node launcher and native child terminate')

  -- A different recorded birth time models PID reuse without waiting for the
  -- kernel to recycle a PID or ever targeting an existing user process.
  local stale = spawn('codex-acp-root', 'stale')
  process, connection = fresh()
  local stale_conn = connection(stale)
  process.observe(stale_conn)
  flush()
  tracked = upvalue(process.stop_tracked, 'tracked')
  local births = upvalue(process.observe, 'births')
  births[stale_conn].start_time = 'different-process-birth'
  tracked[stale].root.start_time = 'different-process-birth'
  if tracked[stale].owner_start_time then
    tracked[stale].owner_start_time = 'different-process-birth'
  end
  process.observe(stale_conn)
  flush()
  process.stop_tracked()
  flush(400)
  equal(
    signal_count(stale, 15) + signal_count(stale, 9),
    0,
    're-observation cannot adopt a reused root PID'
  )
  check(alive(stale), 'PID identity mismatch preserves the live replacement')
  local pruned_scans = scans
  process.observe(stale_conn)
  flush(700)
  equal(
    scans,
    pruned_scans,
    'invalid connection stays inactive through delayed observe after prune'
  )
  check(
    tracked[stale] == nil,
    'delayed observation cannot recreate pruned replacement record'
  )
  stale_conn:disconnect()
  flush(350)
  equal(
    signal_count(stale, 15) + signal_count(stale, 9),
    0,
    'disconnect after pruning cannot reclaim a reused PID'
  )
  check(alive(stale), 'stale connection teardown preserves replacement process')
  equal(
    stale_conn.disconnects,
    nil,
    'invalid birth skips native disconnect that could kill replacement'
  )

  local guarded_root = spawn(
    'codex-acp-root',
    'guarded-root',
    'ignore',
    fixture .. '/bin/codex-acp-leaf'
  )
  wait_for(function()
    return child_of(guarded_root)
  end, 'descendant identity fixture starts')
  local guarded_leaf = child_of(guarded_root)
  process, connection = fresh()
  local guarded_conn = connection(guarded_root)
  process.observe(guarded_conn)
  flush()
  tracked = upvalue(process.stop_tracked, 'tracked')
  tracked[guarded_root].children[guarded_leaf].start_time =
    'different-child-birth'
  process.observe(guarded_conn)
  flush()
  equal(
    tracked[guarded_root].children[guarded_leaf].start_time,
    'different-child-birth',
    're-observation retains recorded descendant identity'
  )
  guarded_conn:disconnect()
  wait_for(function()
    return not alive(guarded_root)
  end, 'matching owner still terminates')
  equal(
    signal_count(guarded_leaf, 15) + signal_count(guarded_leaf, 9),
    0,
    'reused descendant PID is never signalled'
  )
  check(
    alive(guarded_leaf),
    'descendant identity mismatch preserves live replacement'
  )
  -- End this fixture before the separate systemd orphan policy is tested.
  original_kill(guarded_leaf, 9)
  wait_for(function()
    return not alive(guarded_leaf)
  end, 'guarded replacement fixture exits during teardown')

  -- These parents are disposable binaries named systemd --user, not the real
  -- user manager. Native orphan candidates must match both cwd and ancestry.
  local parent = spawn(
    'systemd',
    'manager',
    'ignore',
    executable,
    fixture .. '/bin/codex-acp-leaf'
  )
  local node_parent = spawn(
    'systemd',
    'node-manager',
    'ignore',
    vim.fn.exepath('node'),
    '-',
    node_script
  )
  local filename_parent = spawn(
    'systemd',
    'filename-manager',
    'ignore',
    fixture .. '/bin/acp-unrelated',
    '-',
    executable
  )
  wait_for(function()
    return child_of(parent)
      and child_of(child_of(parent))
      and child_of(node_parent)
      and child_of(filename_parent)
  end, 'orphan-classification fixture starts')
  local orphan, orphan_leaf = child_of(parent), child_of(child_of(parent))
  local node, filename = child_of(node_parent), child_of(filename_parent)
  process = fresh()
  before = scans
  equal(
    process.cleanup_orphans(fixture .. '/wrong-cwd'),
    0,
    'orphan sweep requires exact cwd'
  )
  equal(scans - before, 1, 'empty orphan sweep takes one snapshot')
  before = scans
  equal(
    process.cleanup_orphans(fixture),
    1,
    'native orphan found while Node and unrelated argv filenames are excluded'
  )
  equal(scans - before, 1, 'orphan sweep shares one snapshot')
  wait_for(function()
    return not alive(orphan) and not alive(orphan_leaf)
  end, 'owned native orphan and its ACP descendant terminate')
  check(
    alive(parent) and alive(node_parent) and alive(node),
    'manager fixtures and Node launcher survive orphan cleanup'
  )
  check(
    alive(filename_parent) and alive(filename),
    'an argv filename does not classify unrelated executable as ACP'
  )
  equal(
    signal_count(orphan_leaf, 15),
    1,
    'orphan descendant receives TERM once'
  )
  check(alive(unrelated), 'unrelated ACP peer still survives orphan cleanup')

  local plain = spawn('acp-unrelated', 'native-fallback')
  process, connection = fresh()
  local plain_conn = connection(plain)
  process.observe(plain_conn)
  flush()
  local native_before = #native_signals
  local custom_before = #signals
  plain_conn:disconnect()
  plain_conn:disconnect()
  equal(
    #native_signals - native_before,
    1,
    'unrecognized process uses native fallback once'
  )
  equal(
    #signals,
    custom_before,
    'unrecognized process receives no custom signals'
  )
  equal(
    signal_count(plain, 15),
    1,
    'unrecognized process receives one total TERM'
  )
  equal(plain_conn.disconnects, 1, 'native fallback is idempotent')
  flush(350)

  local queued = spawn('codex-acp-root', 'queued-finish')
  process, connection = fresh()
  before = scans
  local queued_conn = connection(queued)
  process.observe(queued_conn)
  process.finish()
  equal(
    scans - before,
    1,
    'finish consumes queued observations in one final snapshot'
  )
  wait_for(function()
    return not alive(queued)
  end, 'finish terminates newly queued owned process')
  before = scans
  flush(1100)
  equal(
    scans,
    before,
    'finish suppresses all queued and delayed observation work'
  )

  -- Missing /proc is the relevant non-Linux boundary. No OS-specific process
  -- inspection or signal should occur when the proc snapshot is unavailable.
  process, connection = fresh()
  local scan, fs_open = uv.fs_scandir, uv.fs_open
  uv.fs_open = function(path, ...)
    if path:match('^/proc/') then
      return nil, 'ENOENT'
    end
    return fs_open(path, ...)
  end
  uv.fs_scandir = function(path, ...)
    if path == '/proc' then
      return nil, 'ENOENT'
    end
    return scan(path, ...)
  end
  local old_signal_count = #signals
  local missing_proc_conn = connection(unrelated)
  process.observe(missing_proc_conn)
  flush()
  equal(
    process.stop_tracked(),
    0,
    'no proc filesystem means no tracked process'
  )
  equal(
    process.cleanup_orphans(fixture),
    0,
    'orphan cleanup safely skips missing proc filesystem'
  )
  native_before = #native_signals
  missing_proc_conn:disconnect()
  missing_proc_conn:disconnect()
  equal(
    #native_signals - native_before,
    1,
    'missing proc native fallback sends TERM once across repeated disconnects'
  )
  equal(
    missing_proc_conn.disconnects,
    1,
    'missing proc filesystem keeps native disconnect available'
  )
  process.finish()
  flush()
  equal(
    #signals,
    old_signal_count,
    'missing proc filesystem never signals a PID'
  )
  uv.fs_scandir = scan
  process, connection = fresh()
  local unreadable_conn = connection(unrelated)
  process.observe(unreadable_conn)
  flush()
  native_before = #native_signals
  unreadable_conn:disconnect()
  unreadable_conn:disconnect()
  equal(
    #native_signals - native_before,
    1,
    'unreadable identity native fallback sends TERM once'
  )
  equal(
    unreadable_conn.disconnects,
    1,
    'unreadable process identity keeps native disconnect available'
  )
  process.finish()
  flush()
  equal(
    #signals,
    old_signal_count,
    'unreadable process identity never sends custom signals'
  )
  uv.fs_open = fs_open
  equal(forbidden, {}, 'no signal targeted an unknown or reused PID')
end

local ok, err = xpcall(run, debug.traceback)
vim.env.LPKE_ACP_PROCESS_CHILD = original_child_env
uv.kill, uv.fs_scandir, uv.fs_open, vim.defer_fn =
  original_kill, original_scandir, original_fs_open, original_defer
for _ = 1, 3 do
  records()
  for pid, start in pairs(known) do
    if birth(pid) == start then
      pcall(original_kill, pid, 9)
    end
  end
  flush(20)
end
for _, handle in ipairs(handles) do
  if not handle:is_closing() then
    handle:close()
  end
end
vim.fn.delete(fixture, 'rf')
if not ok then
  error(err)
end
local survivors = {}
for pid in pairs(known) do
  if alive(pid) then
    survivors[#survivors + 1] = pid
  end
end
equal(survivors, {}, 'fixture teardown leaves no live child process')
print(('PASS %d process ownership checks'):format(checks))
vim.cmd('qa!')
