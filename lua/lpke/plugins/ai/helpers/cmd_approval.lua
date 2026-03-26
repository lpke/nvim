-- Determines whether a run_command tool invocation needs user approval.
-- Returns true to require approval, false to auto-approve.
return function(tool, tools)
  -- Only auto-approve commands when YOLO mode is enabled.
  -- Without YOLO mode, every command requires approval.
  local approvals =
    require('codecompanion.interactions.chat.tools.approvals')
  if not approvals:is_approved(tools.bufnr) then
    return true
  end

  local cmd = tool.args and tool.args.cmd or ''

  -- Unsafe patterns: always require approval, checked first.
  -- These match destructive, privilege-escalating, or
  -- system-altering commands even when embedded in pipes
  -- or subshells.
  local unsafe_patterns = {
    -- file/directory destruction
    'rm ',
    'rm$',
    'rmdir ',
    'shred ',
    'unlink ',
    -- disk / filesystem
    'mkfs',
    'fdisk',
    'dd ',
    -- privilege escalation
    'sudo ',
    'su ',
    'doas ',
    'pkexec ',
    -- package management (installs, removes, upgrades)
    'apt ',
    'apt%-get ',
    'dpkg ',
    'pacman ',
    'yay ',
    'paru ',
    'dnf ',
    'yum ',
    'snap ',
    'flatpak ',
    'pip install',
    'pip uninstall',
    'pip3 install',
    'pip3 uninstall',
    'npm install %-g',
    'npm i %-g',
    'npm uninstall',
    'cargo install',
    -- system services / init
    'systemctl ',
    'service ',
    'reboot',
    'shutdown',
    'poweroff',
    'halt',
    'init ',
    -- networking / firewall
    'iptables ',
    'nft ',
    'ufw ',
    -- user / group management
    'useradd',
    'userdel',
    'usermod',
    'groupadd',
    'groupdel',
    'groupmod',
    'passwd',
    'chown ',
    'chmod ',
    -- writing to arbitrary files
    'tee ',
    'truncate ',
    -- container / vm with host access
    'docker run',
    'podman run',
    -- process manipulation
    'kill ',
    'killall ',
    'pkill ',
    -- shell eval / code execution from string
    'eval ',
    'bash %-c',
    'sh %-c',
    'zsh %-c',
    -- cURL/wget that could POST or overwrite files
    'curl %-X',
    'curl %-%-request',
    'curl %-d',
    'curl %-%-data',
    'curl .*|', -- piped curl output
    'wget %-O',
    'wget %-%-output',
    -- git destructive operations
    'git push %-%-force',
    'git push %-f ',
    'git reset %-%-hard',
    'git clean %-fd',
    'git clean %-f',
    'git checkout %-%-',
    -- misc dangerous
    'mv / ', -- moving root
    ':%!', -- vim external filter
    'xargs ',
  }
  for _, pattern in ipairs(unsafe_patterns) do
    if cmd:match(pattern) then
      return true -- require approval
    end
  end

  -- Safe patterns: auto-approve without prompting.
  -- Read-only, informational, or low-risk commands.
  local safe_patterns = {
    -- filesystem browsing
    '^ls',
    '^exa ',
    '^eza ',
    '^tree ',
    '^find ',
    '^fd ',
    '^stat ',
    '^file ',
    '^du ',
    '^df ',
    '^realpath ',
    '^readlink ',
    '^basename ',
    '^dirname ',
    -- reading files
    '^cat ',
    '^bat ',
    '^head ',
    '^tail ',
    '^less ',
    '^more ',
    '^wc ',
    '^md5sum ',
    '^sha256sum ',
    -- text search
    '^grep ',
    '^egrep ',
    '^fgrep ',
    '^rg ',
    '^ag ',
    '^awk ',
    '^sed %-n',
    -- output / formatting
    '^echo ',
    '^printf ',
    '^date',
    '^cal$',
    '^cal ',
    '^env$',
    '^env ',
    '^printenv',
    '^pwd$',
    '^whoami$',
    '^id$',
    '^id ',
    '^hostname',
    '^uname',
    -- git read-only
    '^git status',
    '^git diff',
    '^git log',
    '^git show',
    '^git branch',
    '^git remote %-v',
    '^git remote show',
    '^git tag',
    '^git stash list',
    '^git ls%-files',
    '^git ls%-tree',
    '^git rev%-parse',
    '^git describe',
    '^git blame',
    '^git shortlog',
    -- build / test / lint (common project commands)
    '^make ',
    '^make$',
    '^cargo test',
    '^cargo check',
    '^cargo clippy',
    '^cargo build',
    '^cargo fmt',
    '^go test',
    '^go vet',
    '^go build',
    '^go fmt',
    '^python[23]? %-m pytest',
    '^pytest',
    '^python[23]? %-m unittest',
    '^python[23]? %-c ',
    '^npm test',
    '^npm run ',
    '^npx ',
    '^yarn test',
    '^yarn run ',
    '^pnpm test',
    '^pnpm run ',
    '^bun test',
    '^bun run ',
    '^luacheck ',
    '^selene ',
    '^stylua %-%-check',
    '^eslint ',
    '^prettier %-%-check',
    '^rubocop ',
    '^rspec ',
    -- misc safe utilities
    '^which ',
    '^whereis ',
    '^type ',
    '^man ',
    '^help ',
    '^sort ',
    '^uniq ',
    '^cut ',
    '^tr ',
    '^diff ',
    '^comm ',
    '^cmp ',
    '^jq ',
    '^yq ',
    '^column ',
    '^paste ',
    '^seq ',
    '^yes ',
    '^true$',
    '^false$',
    '^nproc$',
    '^free ',
    '^uptime$',
    '^lscpu',
    '^lsblk',
    '^lspci',
    '^lsusb',
  }
  for _, pattern in ipairs(safe_patterns) do
    if cmd:match(pattern) then
      return false -- auto-approve
    end
  end

  return true -- require approval for anything else
end
