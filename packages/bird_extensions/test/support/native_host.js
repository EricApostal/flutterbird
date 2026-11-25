#!/usr/bin/env node
// A native messaging host for tests: it answers each message with what it was
// started with and what it was sent, and does what a message with "cmd" says.
const os = require('os');
const little = os.endianness() === 'LE';

function send(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  const header = Buffer.alloc(4);
  if (little) header.writeUInt32LE(body.length, 0);
  else header.writeUInt32BE(body.length, 0);
  process.stdout.write(Buffer.concat([header, body]));
}

let pending = Buffer.alloc(0);
process.stdin.on('data', (chunk) => {
  pending = Buffer.concat([pending, chunk]);
  while (pending.length >= 4) {
    const length = little ? pending.readUInt32LE(0) : pending.readUInt32BE(0);
    if (pending.length < 4 + length) return;
    const message = JSON.parse(pending.subarray(4, 4 + length).toString('utf8'));
    pending = pending.subarray(4 + length);

    if (message && message.cmd === 'exit') process.exit(0);
    else send({ echo: message, args: process.argv.slice(2) });
  }
});
process.stdin.on('end', () => process.exit(0));
