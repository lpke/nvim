local manager = require('lpke.core.html_server.manager')

manager.setup()

return {
  attach_existing = manager.attach_existing,
  complete_stop = manager.complete_stop,
  disconnect_current_session = manager.disconnect_current_session,
  help = manager.help,
  list = manager.list,
  open_command = manager.open_command,
  start_path = manager.start_path,
  stop = manager.stop,
  stop_all = manager.stop_all,
  stop_command = manager.stop_command,
}
