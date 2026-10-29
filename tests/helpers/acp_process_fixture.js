const fs = require('node:fs');
const { spawn } = require('node:child_process');
const [log, pids, child] = process.argv.slice(2);

process.on('SIGTERM', () => {
  fs.appendFileSync(log, `${process.pid} TERM\n`);
});
fs.appendFileSync(pids, `node\t${process.pid}\t${process.ppid}\n`);
if (child && child !== '-') {
  spawn(child, [log, pids, 'child', 'ignore', '-', '-'], {
    stdio: 'ignore',
  });
}
setInterval(() => {}, 1000);
