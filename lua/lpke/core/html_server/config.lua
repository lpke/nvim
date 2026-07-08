local M = {}

M.registry_dir = vim.fn.stdpath('state') .. '/lpke/html_server'
M.registry_path = M.registry_dir .. '/html_servers.json'

M.heartbeat_interval_ms = 60000
M.lease_ms = 5 * 60 * 1000
M.active_heartbeat_window_ms = 70000
M.browser_keepalive_ms = 60000
M.reload_debounce_ms = 80
M.startup_scan_delay_ms = 500
M.startup_timeout_ms = 5000
M.http_timeout_ms = 2000

return M
