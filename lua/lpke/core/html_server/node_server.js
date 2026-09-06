// Server source of truth lives in chezmoi and is shared with the terminal launcher.
const path = require('node:path');
const os = require('node:os');
const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local/share');
require(path.join(dataHome, 'html-server/server.cjs'));
