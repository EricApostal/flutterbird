// A stand-in for one extension world in a web content process. It runs the
// shim exactly as the engine does and speaks JSON lines over stdio:
//
//   in:  {"cmd":"init","init":"<json text>","shim":"<js>"}
//        {"cmd":"deliver","payload":"<string for the receiver>"}
//        {"cmd":"run","id":1,"code":"<js to evaluate, awaiting a promise>"}
//   out: {"ready":true} {"send":"<string>"} {"phase":"document_end"}
//        {"ran":1,"value":...} {"ran":1,"error":"..."}
'use strict';

const readline = require('node:readline');
const vm = require('node:vm');

let context = null;
let receiver = null;

const out = (message) => process.stdout.write(JSON.stringify(message) + '\n');

const rl = readline.createInterface({ input: process.stdin });

rl.on('line', async (line) => {
  const message = JSON.parse(line);

  if (message.cmd === 'init') {
    context = vm.createContext({
      __bird_send: (text) => out({ send: text }),
      __bird_set_receiver: (fn) => {
        receiver = fn;
      },
      __bird_phase: (name) => out({ phase: name }),
      ...(message.page ? { location: { protocol: 'moz-extension:' } } : {}),
      document: {
        readyState: 'loading',
        documentElement: {},
        addEventListener() {},
        adoptedStyleSheets: [],
      },
      setTimeout,
      console: { error: (...args) => out({ log: args.map(String).join(' ') }) },
    });
    // The same two steps the engine takes.
    vm.runInContext('globalThis.__bird_init = ' + message.init + ';', context);
    vm.runInContext(message.shim, context);
    out({ ready: true });
  } else if (message.cmd === 'deliver') {
    receiver(message.payload);
  } else if (message.cmd === 'run') {
    try {
      const value = await vm.runInContext(message.code, context);
      out({ ran: message.id, value: value === undefined ? null : JSON.parse(JSON.stringify(value)) });
    } catch (error) {
      out({ ran: message.id, error: String((error && error.message) || error) });
    }
  }
});

rl.on('close', () => process.exit(0));
