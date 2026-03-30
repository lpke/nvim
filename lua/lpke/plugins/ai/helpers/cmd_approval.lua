-- Determines whether a run_command tool invocation needs user approval.
-- Returns true to require approval, false to auto-approve.

-- Unsafe patterns: always require approval.
-- Destructive, privilege-escalating, or system-altering commands.
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
  -- redirection can overwrite files (but not 2>&1 stderr redirect)
  '[^2&]>', -- output redirection
}

-- Safe patterns: auto-approve without prompting.
-- Read-only, informational, or low-risk commands.
-- These are matched against the START of each sub-command.
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
  '^sort',
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
  -- delete empty directories only (safe cleanup)
  '^find .* %-type d %-empty %-delete',
}

--- Split a command string on shell operators (&&, ||, ;, |)
--- and return a list of trimmed sub-commands.
---@param cmd string
---@return string[]
local function split_subcommands(cmd)
  -- Split on &&, ||, ;, and | (but not ||)
  -- We handle || before | to avoid partial matches.
  local parts = {}
  -- Use a pattern that splits on the operators, preserving order.
  -- Replace operators with a sentinel, then split.
  local sentinel = '\0'
  local s = cmd
  -- Order matters: || before |, && before &
  s = s:gsub('||', sentinel)
  s = s:gsub('&&', sentinel)
  s = s:gsub(';', sentinel)
  s = s:gsub('|', sentinel)
  for part in s:gmatch('[^' .. sentinel .. ']+') do
    local trimmed = part:match('^%s*(.-)%s*$')
    if trimmed and #trimmed > 0 then
      table.insert(parts, trimmed)
    end
  end
  return parts
end

--- Strip a leading `cd <dir> &&`-style prefix from a sub-command
--- if it's changing to the current working directory.
--- Returns the command with leading whitespace trimmed.
---@param subcmd string
---@return string cleaned sub-command
---@return boolean true if a cd-to-cwd was stripped
local function strip_cd_to_cwd(subcmd)
  -- Match `cd <path>` where <path> can be quoted or unquoted
  local cd_path = subcmd:match('^cd%s+["\']?([^"\';|&]+)["\']?%s*$')
  if not cd_path then
    return subcmd, false
  end

  cd_path = cd_path:match('^%s*(.-)%s*$') -- trim

  -- Allow cd to CWD, home dir, or common project-relative paths
  local cwd = vim.fn.getcwd()
  -- Normalise: remove trailing slash for comparison
  local norm = function(p)
    return (p:gsub('/+$', ''))
  end

  if norm(cd_path) == norm(cwd) then
    return '', true
  end

  -- Also allow relative paths like "." or paths under cwd
  if cd_path == '.' or cd_path == './' then
    return '', true
  end

  -- Allow subdirectories of cwd
  if cd_path:sub(1, 1) ~= '/' then
    -- relative path — it's under cwd, allow it
    return '', true
  end

  -- Allow paths that are under cwd
  if norm(cd_path):sub(1, #norm(cwd) + 1) == norm(cwd) .. '/' then
    return '', true
  end

  return subcmd, false
end

--- Check if a sub-command matches any pattern in a list.
---@param subcmd string
---@param patterns string[]
---@return boolean
local function matches_any(subcmd, patterns)
  for _, pattern in ipairs(patterns) do
    if subcmd:match(pattern) then
      return true
    end
  end
  return false
end

return function(tool, tools)
  -- Only auto-approve commands when YOLO mode is enabled.
  -- Without YOLO mode, every command requires approval.
  local approvals = require('codecompanion.interactions.chat.tools.approvals')
  if not approvals:is_approved(tools.bufnr) then
    return true
  end

  local cmd = tool.args and tool.args.cmd or ''

  -- Reject empty commands
  if cmd:match('^%s*$') then
    return true
  end

  -- Split on shell operators and check EVERY sub-command.
  local subcommands = split_subcommands(cmd)

  -- If splitting produced nothing, require approval.
  if #subcommands == 0 then
    return true
  end

  for _, subcmd in ipairs(subcommands) do
    -- First: check unsafe patterns against every sub-command.
    -- Unsafe patterns are checked anywhere in the sub-command string.
    if matches_any(subcmd, unsafe_patterns) then
      return true -- require approval
    end
  end

  -- Now check that every (non-cd) sub-command is explicitly safe.
  for _, subcmd in ipairs(subcommands) do
    -- Strip cd-to-cwd; if the entire sub-command is just a cd to cwd,
    -- it's safe on its own.
    local cleaned, was_cd = strip_cd_to_cwd(subcmd)
    if was_cd and #cleaned == 0 then
      -- Pure cd to cwd — safe, continue to next sub-command
      goto continue
    end

    -- If not a bare cd-to-cwd, the command must match a safe pattern
    if not matches_any(cleaned, safe_patterns) then
      return true -- not explicitly safe, require approval
    end

    ::continue::
  end

  return false -- all sub-commands are safe, auto-approve
end
