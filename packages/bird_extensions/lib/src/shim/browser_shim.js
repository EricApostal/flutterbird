// The `browser` and `chrome` objects of an extension context.
//
// This runs inside the context the engine makes for an extension (an isolated
// world for content scripts, or the document itself for an extension's own
// pages), after the engine has defined three functions on the global and the
// browser has defined `__bird_init`:
//
//   __bird_send(string)          send a string to the browser
//   __bird_set_receiver(fn)      register fn(string) for strings from the browser
//   __bird_phase(name)           ask the engine to run the content scripts due
//   __bird_eval(code)            run code as a script and return its value
//                                at "document_end" or "document_idle"
//
// Everything else an extension can do is built from those. A call becomes
//
//   {"id": 7, "ns": "storage", "method": "get", "args": [...]}
//
// and its answer arrives as {"reply": 7, "result": ...} or
// {"reply": 7, "error": {"message": "..."}}. The browser starts events with
// {"event": "runtime.onMessage", "args": [...], "token": 3}; an event with a
// token wants an answer, which is sent as the internal call bird.respond.
(function () {
  'use strict';

  var init = globalThis.__bird_init || {};
  var sendNative = globalThis.__bird_send;
  var setReceiver = globalThis.__bird_set_receiver;
  var requestPhase = globalThis.__bird_phase;
  // Runs code the way a content script runs, which a page's CSP does not limit.
  var runCode = globalThis.__bird_eval;

  // The extension's own scripts share this realm, so keep the natives out of
  // their reach: they are the browser's, not part of any extension API.
  try {
    delete globalThis.__bird_init;
    delete globalThis.__bird_send;
    delete globalThis.__bird_set_receiver;
    delete globalThis.__bird_phase;
    delete globalThis.__bird_eval;
  } catch (e) {
    // A global that cannot be deleted is harmless; the copies above are used.
  }

  var isExtensionPage = false;
  try {
    isExtensionPage = String(globalThis.location && globalThis.location.protocol) === 'moz-extension:';
  } catch (e) {
    isExtensionPage = false;
  }

  // ---------------------------------------------------------------- calls

  var nextCallId = 1;
  var pending = new Map();

  function makeError(description) {
    var error = new Error(
      description && description.message ? String(description.message) : 'Unknown error');
    if (description && description.name) error.name = String(description.name);
    return error;
  }

  // Calls an API implemented by the browser and returns a promise for its
  // result.
  function call(ns, method, args) {
    return new Promise(function (resolve, reject) {
      var id = nextCallId++;
      pending.set(id, { resolve: resolve, reject: reject });
      try {
        sendNative(JSON.stringify({ id: id, ns: ns, method: method, args: args }));
      } catch (error) {
        pending.delete(id);
        reject(error);
      }
    });
  }

  // A call whose answer nobody needs.
  function tell(ns, method, args) {
    call(ns, method, args).catch(function () {});
  }

  // ---------------------------------------------------------------- events

  var events = Object.create(null);

  // `tracked` events tell the browser when the first listener arrives and the
  // last one leaves, so it only does work for events somebody wants.
  function createEvent(name, tracked) {
    var listeners = [];
    // What followed each listener in addListener, such as a webRequest filter.
    var extras = [];
    var event = {
      addListener: function (listener) {
        if (typeof listener !== 'function' || listeners.indexOf(listener) >= 0) return;
        var extra = Array.prototype.slice.call(arguments, 1);
        listeners.push(listener);
        extras.push(extra);
        if (tracked) tell('events', 'addListener', [name, extra]);
      },
      removeListener: function (listener) {
        var index = listeners.indexOf(listener);
        if (index < 0) return;
        listeners.splice(index, 1);
        var extra = extras.splice(index, 1)[0];
        if (tracked) tell('events', 'removeListener', [name, extra]);
      },
      hasListener: function (listener) {
        return listeners.indexOf(listener) >= 0;
      },
      hasListeners: function () {
        return listeners.length > 0;
      },
    };
    Object.defineProperty(event, '_listeners', { value: listeners, enumerable: false });
    Object.defineProperty(event, '_extras', { value: extras, enumerable: false });
    if (name) events[name] = event;
    return event;
  }

  // Lets the browser's log say what went wrong in an extension's own code.
  function logToBrowser(kind, text) {
    tell('bird', 'log', [kind, String(text).slice(0, 800)]);
  }

  if (typeof globalThis.addEventListener === 'function') {
    globalThis.addEventListener('error', function (event) {
      var file = String(event.filename || '');
      // In an extension's own page every error is the extension's.
      if (!isExtensionPage && file.indexOf('moz-extension://') !== 0) return;
      logToBrowser('error', event.message + ' at ' + file + ':' + event.lineno + ':' + event.colno);
    });
    globalThis.addEventListener('unhandledrejection', function (event) {
      var reason = event.reason;
      var stack = reason && reason.stack ? String(reason.stack) : '';
      var text = stack || String(reason && reason.message ? reason.name + ': ' + reason.message : reason);
      // A page's own rejections are its business; whatever has no stack to tell is still reported.
      if (!isExtensionPage && stack && stack.indexOf('moz-extension://') < 0) return;
      logToBrowser('unhandled rejection', text);
    });
  }

  ['error', 'warn'].forEach(function (level) {
    var original = globalThis.console && globalThis.console[level];
    if (typeof original !== 'function') return;
    globalThis.console[level] = function () {
      try {
        logToBrowser('console.' + level, Array.prototype.map.call(arguments, function (value) {
          return value && value.stack ? value.stack : String(value);
        }).join(' '));
      } catch (ignored) {
        // Logging must never get in the way of the extension.
      }
      return original.apply(this, arguments);
    };
  });

  function reportListenerError(error) {
    try {
      console.error(error);
    } catch (ignored) {
      // There is nowhere left to report to.
    }
  }

  function describeError(error) {
    return { message: error && error.message ? String(error.message) : String(error) };
  }

  // Whether `url` is covered by a match pattern such as "*://*.example.com/*".
  function urlMatchesPattern(pattern, url) {
    if (typeof pattern !== 'string' || typeof url !== 'string') return false;
    var target = /^([a-z][a-z0-9+.-]*):\/\/([^\/?#]*)([^#]*)/i.exec(url);
    if (!target) return false;
    var scheme = target[1].toLowerCase();
    var host = target[2].replace(/^[^@]*@/, '').replace(/:\d+$/, '').toLowerCase();
    var path = target[3] || '/';
    if (path.charAt(0) !== '/') path = '/' + path;

    if (pattern === '<all_urls>') {
      return ['http', 'https', 'ws', 'wss', 'ftp', 'ftps', 'file', 'data'].indexOf(scheme) >= 0;
    }
    var parts = /^(\*|[a-z][a-z0-9+.-]*):\/\/([^\/]*)(\/.*)$/i.exec(pattern);
    if (!parts) return false;

    var wantedScheme = parts[1].toLowerCase();
    if (wantedScheme === '*') {
      if (['http', 'https', 'ws', 'wss'].indexOf(scheme) < 0) return false;
    } else if (wantedScheme !== scheme) {
      return false;
    }

    var wantedHost = parts[2].toLowerCase();
    if (wantedHost !== '*') {
      if (wantedHost.indexOf('*.') === 0) {
        var base = wantedHost.slice(2);
        if (host !== base && host.slice(-(base.length + 1)) !== '.' + base) return false;
      } else if (wantedHost !== host) {
        return false;
      }
    }

    var glob = parts[3].replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
    return new RegExp('^' + glob + '$').test(path);
  }

  // Whether a listener asked to be told about `args`. Only webRequest has
  // filters that are applied here: the browser cannot know which of a
  // context's listeners a filter belonged to.
  function listenerAccepts(name, extra, args, answered) {
    if (name.indexOf('webRequest.') !== 0) return true;
    var filter = extra && extra[0];
    var details = args && args[0];
    if (filter && typeof filter === 'object' && details) {
      if (Array.isArray(filter.urls) && !filter.urls.some(function (pattern) {
        return urlMatchesPattern(pattern, details.url);
      })) return false;
      if (Array.isArray(filter.types) && filter.types.indexOf(details.type) < 0) return false;
      if (typeof filter.tabId === 'number' && filter.tabId !== details.tabId) return false;
    }
    // Only a listener that asked to block may change what the request does.
    if (answered && !(extra && Array.isArray(extra[1]) && extra[1].indexOf('blocking') >= 0)) {
      return false;
    }
    return true;
  }

  function acceptingListeners(event, name, args, answered) {
    var chosen = [];
    event._listeners.forEach(function (listener, index) {
      if (listenerAccepts(name, event._extras[index], args, answered)) chosen.push(listener);
    });
    return chosen;
  }

  function dispatchPlainEvent(message) {
    var event = events[message.event];
    if (!event) return;
    acceptingListeners(event, message.event, message.args || [], false).forEach(function (listener) {
      try {
        listener.apply(undefined, message.args || []);
      } catch (error) {
        reportListenerError(error);
      }
    });
  }

  // An event with a token wants an answer, exactly once, when a listener has
  // given one or when it is clear that none will. `withSendResponse` is for
  // runtime.onMessage, whose listeners may also answer through a callback.
  function dispatchAnswered(message, withSendResponse) {
    var args = message.args || [];
    var token = message.token;
    var event = events[message.event];
    var listeners = event ? acceptingListeners(event, message.event, args, true) : [];

    var settled = false;
    var waiting = 0;
    var handled = false;

    function answer(body) {
      if (settled) return;
      settled = true;
      tell('bird', 'respond', [token, body]);
    }

    function finishIfIdle() {
      if (!settled && waiting === 0) answer({ handled: handled });
    }

    function respondWith(value) {
      handled = true;
      answer({ handled: true, value: value });
    }

    listeners.forEach(function (listener) {
      var result;
      try {
        result = withSendResponse ?
          listener(args[0], args[1], function (value) { respondWith(value); }) :
          listener.apply(undefined, args);
      } catch (error) {
        reportListenerError(error);
        return;
      }

      if (withSendResponse && result === true) {
        // Chrome: "I will call sendResponse later."
        waiting++;
        handled = true;
      } else if (result && typeof result.then === 'function') {
        waiting++;
        handled = true;
        result.then(
          function (value) {
            waiting--;
            respondWith(value);
          },
          function (error) {
            waiting--;
            answer({ handled: true, error: describeError(error) });
          });
      } else if (!withSendResponse && result !== undefined) {
        // A blocking webRequest listener answers by returning.
        respondWith(result);
      }
    });

    finishIfIdle();
  }

  // ---------------------------------------------------------------- ports

  var ports = new Map();
  var nextPortNumber = 1;

  function makePort(portId, name, sender) {
    var disconnected = false;
    var port = {
      name: name || '',
      sender: sender,
      error: null,
      onMessage: createEvent(null, false),
      onDisconnect: createEvent(null, false),
      postMessage: function (message) {
        if (disconnected) throw new Error('Attempt to postMessage on disconnected port');
        tell('bird', 'portPost', [portId, message]);
      },
      disconnect: function () {
        if (disconnected) return;
        disconnected = true;
        ports.delete(portId);
        tell('bird', 'portDisconnect', [portId]);
      },
    };
    Object.defineProperty(port, '_close', {
      enumerable: false,
      value: function (error) {
        if (disconnected) return;
        disconnected = true;
        ports.delete(portId);
        if (error) port.error = { message: String(error) };
        port.onDisconnect._listeners.slice().forEach(function (listener) {
          try {
            listener(port);
          } catch (e) {
            reportListenerError(e);
          }
        });
      },
    });
    ports.set(portId, port);
    return port;
  }

  function newPortId() {
    return String(init.uuid || 'x') + ':' + Math.random().toString(36).slice(2) + ':' + (nextPortNumber++);
  }

  function dispatchPortEvent(message) {
    var args = message.args || [];
    var port = ports.get(args[0]);
    if (message.event === 'bird.portMessage') {
      if (!port) return;
      port.onMessage._listeners.slice().forEach(function (listener) {
        try {
          listener(args[1], port);
        } catch (error) {
          reportListenerError(error);
        }
      });
    } else if (message.event === 'bird.portDisconnect') {
      if (port) port._close(args[1]);
    }
  }

  // ---------------------------------------------------------------- scripts run on the browser's behalf

  function dispatchBirdEvent(message) {
    var args = message.args || [];

    if (message.event === 'bird.eval') {
      // tabs.executeScript: evaluate the code here and answer with its result.
      var token = message.token;
      var finish = function (body) {
        tell('bird', 'respond', [token, body]);
      };
      try {
        var result = typeof runCode === 'function' ? runCode(String(args[0])) : (0, eval)(String(args[0]));
        if (result && typeof result.then === 'function') {
          result.then(function (value) {
            finish({ handled: true, value: value === undefined ? null : value });
          }, function (error) {
            finish({ handled: true, error: describeError(error) });
          });
        } else {
          finish({ handled: true, value: result === undefined ? null : result });
        }
      } catch (error) {
        finish({ handled: true, error: describeError(error) });
      }
    } else if (message.event === 'bird.insertCss') {
      globalThis.__bird_insert_css(String(args[0]));
      if (message.token !== undefined) tell('bird', 'respond', [message.token, { handled: true, value: null }]);
    }
  }

  // ---------------------------------------------------------------- native messaging

  var nativePorts = new Map();
  var nextNativePort = 1;

  function finishNativePort(portId, errorMessage) {
    var entry = nativePorts.get(portId);
    if (!entry || entry.closed) return;
    entry.closed = true;
    nativePorts.delete(portId);
    if (errorMessage) entry.port.error = { message: String(errorMessage) };
    entry.port.onDisconnect._listeners.slice().forEach(function (listener) {
      try {
        listener(entry.port);
      } catch (error) {
        reportListenerError(error);
      }
    });
  }

  function dispatchNativeEvent(message) {
    var args = message.args || [];
    var entry = nativePorts.get(args[0]);
    if (!entry) return;

    if (message.event === 'bird.nativeDisconnect') {
      finishNativePort(args[0], args[1]);
      return;
    }
    entry.port.onMessage._listeners.slice().forEach(function (listener) {
      try {
        listener(args[1], entry.port);
      } catch (error) {
        reportListenerError(error);
      }
    });
  }

  // runtime.connectNative: a port to a program installed on the computer.
  function connectNative(application) {
    var portId = 'native:' + nextNativePort++;
    var entry = { closed: false, port: null };
    var port = {
      name: String(application),
      error: null,
      onMessage: createEvent(null, false),
      onDisconnect: createEvent(null, false),
      postMessage: function (message) {
        if (entry.closed) throw new Error('Attempt to postMessage on disconnected port');
        tell('native', 'post', [portId, message]);
      },
      disconnect: function () {
        if (entry.closed) return;
        entry.closed = true;
        nativePorts.delete(portId);
        tell('native', 'close', [portId]);
      },
    };
    entry.port = port;
    nativePorts.set(portId, entry);

    call('native', 'connect', [String(application), portId]).catch(function (error) {
      finishNativePort(portId, error && error.message);
    });
    return port;
  }

  function sendNativeMessage(application, message) {
    return call('native', 'send', [String(application), message]);
  }

  // ---------------------------------------------------------------- receiving

  setReceiver(function (text) {
    var message;
    try {
      message = JSON.parse(text);
    } catch (error) {
      return;
    }

    if (message.reply !== undefined) {
      var entry = pending.get(message.reply);
      if (!entry) return;
      pending.delete(message.reply);
      if (message.error) entry.reject(makeError(message.error));
      else entry.resolve(message.result);
      return;
    }

    var name = message.event;
    if (!name) return;

    if (name === 'bird.portMessage' || name === 'bird.portDisconnect') dispatchPortEvent(message);
    else if (name === 'bird.eval' || name === 'bird.insertCss') dispatchBirdEvent(message);
    else if (name === 'bird.nativeMessage' || name === 'bird.nativeDisconnect') dispatchNativeEvent(message);
    else if (name === 'runtime.onConnect') dispatchConnect(message);
    else if (message.token !== undefined) dispatchAnswered(message, name === 'runtime.onMessage');
    else dispatchPlainEvent(message);
  });

  function dispatchConnect(message) {
    var info = (message.args || [])[0] || {};
    var event = events['runtime.onConnect'];
    if (!event || event._listeners.length === 0) {
      tell('bird', 'portDisconnect', [info.portId]);
      return;
    }
    var port = makePort(info.portId, info.name, info.sender);
    event._listeners.slice().forEach(function (listener) {
      try {
        listener(port);
      } catch (error) {
        reportListenerError(error);
      }
    });
  }

  // ---------------------------------------------------------------- helpers for defining APIs

  // Defines each of `names` on `target` as a call to the browser.
  function defineCalls(target, ns, names) {
    names.forEach(function (name) {
      target[name] = function () {
        return call(ns, name, Array.prototype.slice.call(arguments));
      };
    });
    return target;
  }

  function defineEvents(target, prefix, names) {
    names.forEach(function (name) {
      target[name] = createEvent(prefix + '.' + name, true);
    });
    return target;
  }

  function looksLikeExtensionId(text) {
    return typeof text === 'string' &&
      (/^[^\s@]+@[^\s@]+$/.test(text) || /^\{[0-9a-fA-F-]+\}$/.test(text));
  }

  // sendMessage([extensionId], message, [options]) has no marker for which
  // argument is which, so go by how many there are and what the first looks like.
  function normalizeSendMessage(args) {
    if (args.length >= 3) return { target: args[0], message: args[1], options: args[2] };
    if (args.length === 2) {
      if (looksLikeExtensionId(args[0])) return { target: args[0], message: args[1] };
      return { message: args[0], options: args[1] };
    }
    return { message: args[0] };
  }

  // ---------------------------------------------------------------- runtime

  var runtime = {
    id: init.id,
    getURL: function (path) {
      return String(init.baseUrl || '') + String(path).replace(/^\/+/, '');
    },
    getManifest: function () {
      return JSON.parse(JSON.stringify(init.manifest || {}));
    },
    getPlatformInfo: function () {
      return Promise.resolve({ os: init.platform || 'mac', arch: 'arm64' });
    },
    // Extensions sniff this to decide what the browser supports, and what they
    // can use is what Firefox has, so this answers as Firefox does.
    getBrowserInfo: function () {
      return Promise.resolve({
        name: 'Firefox', vendor: 'Mozilla', version: init.browserVersion || '128.0', buildID: '20240101000000',
      });
    },
    sendMessage: function () {
      var request = normalizeSendMessage(Array.prototype.slice.call(arguments));
      if (request.target !== undefined && request.target !== init.id) {
        return Promise.reject(new Error('Messaging other extensions is not supported'));
      }
      return call('runtime', 'sendMessage', [request.message, request.options || null]);
    },
    connect: function () {
      var args = Array.prototype.slice.call(arguments);
      var info = typeof args[args.length - 1] === 'object' && args[args.length - 1] !== null ?
        args[args.length - 1] : {};
      var portId = newPortId();
      var port = makePort(portId, info.name, undefined);
      call('runtime', 'connect', [portId, info.name || '']).catch(function (error) {
        port._close(error && error.message);
      });
      return port;
    },
    openOptionsPage: function () {
      return call('runtime', 'openOptionsPage', []);
    },
    reload: function () {
      return call('runtime', 'reload', []);
    },
    setUninstallURL: function () {
      return Promise.resolve();
    },
    requestUpdateCheck: function () {
      return Promise.resolve(['no_update', {}]);
    },
    getBackgroundPage: function () {
      return Promise.resolve(null);
    },
    onMessage: createEvent('runtime.onMessage', true),
    onConnect: createEvent('runtime.onConnect', true),
    onInstalled: createEvent('runtime.onInstalled', true),
    onStartup: createEvent('runtime.onStartup', true),
    onUpdateAvailable: createEvent('runtime.onUpdateAvailable', true),
    // Messages from other extensions and web pages are not supported, so these never fire.
    onMessageExternal: createEvent(null, false),
    // The background page is never suspended, so these never fire either.
    onSuspend: createEvent(null, false),
    onSuspendCanceled: createEvent(null, false),
    onConnectExternal: createEvent(null, false),
    lastError: undefined,
  };

  // ---------------------------------------------------------------- storage

  var storageChanged = createEvent('storage.onChanged', true);

  // `storage.local.onChanged` and the like: the same changes, for one area.
  function areaChangedEvent(area) {
    var event = createEvent(null, false);
    var add = event.addListener;
    var remove = event.removeListener;
    function forward(changes, areaName) {
      if (areaName !== area) return;
      event._listeners.slice().forEach(function (listener) {
        try {
          listener(changes);
        } catch (error) {
          reportListenerError(error);
        }
      });
    }
    event.addListener = function () {
      var before = event._listeners.length;
      add.apply(event, arguments);
      if (before === 0 && event._listeners.length === 1) storageChanged.addListener(forward);
    };
    event.removeListener = function () {
      var before = event._listeners.length;
      remove.apply(event, arguments);
      if (before === 1 && event._listeners.length === 0) storageChanged.removeListener(forward);
    };
    return event;
  }

  function storageArea(area) {
    return {
      onChanged: areaChangedEvent(area),
      get: function (keys) {
        return call('storage', 'get', [area, keys === undefined ? null : keys]);
      },
      set: function (items) {
        return call('storage', 'set', [area, items]);
      },
      remove: function (keys) {
        return call('storage', 'remove', [area, keys]);
      },
      clear: function () {
        return call('storage', 'clear', [area]);
      },
      getBytesInUse: function (keys) {
        return call('storage', 'getBytesInUse', [area, keys === undefined ? null : keys]);
      },
    };
  }

  var storage = {
    local: storageArea('local'),
    sync: storageArea('sync'),
    session: storageArea('session'),
    managed: storageArea('managed'),
    onChanged: storageChanged,
  };

  // ---------------------------------------------------------------- i18n

  var catalog = init.messages || {};

  function getMessage(name, substitutions) {
    var entry = catalog[String(name).toLowerCase()];
    if (!entry) return '';
    var values = substitutions === undefined ? [] :
      Array.isArray(substitutions) ? substitutions : [substitutions];
    // "$$" is a literal dollar sign and "$1".."$9" are the substitutions.
    return String(entry.message).replace(/\$(\$|[1-9])/g, function (match, token) {
      if (token === '$') return '$';
      var value = values[Number(token) - 1];
      return value === undefined ? '' : String(value);
    });
  }

  var i18n = {
    getMessage: getMessage,
    getUILanguage: function () {
      return init.uiLanguage || 'en-US';
    },
    getAcceptLanguages: function () {
      return Promise.resolve([init.uiLanguage || 'en-US']);
    },
    detectLanguage: function () {
      return Promise.reject(new Error('detectLanguage is not supported'));
    },
  };

  // ---------------------------------------------------------------- the rest of the API

  var tabs = defineCalls({
    TAB_ID_NONE: -1,
    connect: function (tabId, info) {
      info = info || {};
      var portId = newPortId();
      var port = makePort(portId, info.name, undefined);
      call('tabs', 'connect', [portId, tabId, info.name || '', info.frameId === undefined ? null : info.frameId])
        .catch(function (error) {
          port._close(error && error.message);
        });
      return port;
    },
  }, 'tabs', [
    'get', 'getCurrent', 'query', 'create', 'update', 'remove', 'reload', 'move', 'duplicate',
    'executeScript', 'insertCSS', 'removeCSS', 'sendMessage', 'getZoom', 'setZoom', 'goBack',
    'goForward', 'discard', 'captureTab', 'captureVisibleTab', 'detectLanguage', 'warmup',
  ]);
  defineEvents(tabs, 'tabs', [
    'onCreated', 'onUpdated', 'onRemoved', 'onActivated', 'onMoved', 'onAttached', 'onDetached',
    'onReplaced', 'onHighlighted', 'onZoomChange',
  ]);

  var windows = defineCalls({ WINDOW_ID_NONE: -1, WINDOW_ID_CURRENT: -2 }, 'windows', [
    'get', 'getCurrent', 'getLastFocused', 'getAll', 'create', 'update', 'remove',
  ]);
  defineEvents(windows, 'windows', ['onCreated', 'onRemoved', 'onFocusChanged']);

  var webNavigation = defineCalls({}, 'webNavigation', ['getFrame', 'getAllFrames']);
  defineEvents(webNavigation, 'webNavigation', [
    'onBeforeNavigate', 'onCommitted', 'onDOMContentLoaded', 'onCompleted', 'onErrorOccurred',
    'onCreatedNavigationTarget', 'onReferenceFragmentUpdated', 'onHistoryStateUpdated',
    'onTabReplaced',
  ]);

  var webRequest = defineCalls({
    MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES: 20,
    ResourceType: {
      MAIN_FRAME: 'main_frame', SUB_FRAME: 'sub_frame', STYLESHEET: 'stylesheet', SCRIPT: 'script',
      IMAGE: 'image', FONT: 'font', OBJECT: 'object', XMLHTTPREQUEST: 'xmlhttprequest',
      PING: 'ping', CSP_REPORT: 'csp_report', MEDIA: 'media', WEBSOCKET: 'websocket',
      WEBBUNDLE: 'webbundle', OTHER: 'other',
    },
    // Firefox lets an extension read and rewrite a response as it arrives.
    filterResponseData: function (requestId) {
      return call('webRequest', 'filterResponseData', [requestId]);
    },
  }, 'webRequest', ['handlerBehaviorChanged', 'getSecurityInfo']);
  defineEvents(webRequest, 'webRequest', [
    'onBeforeRequest', 'onBeforeSendHeaders', 'onSendHeaders', 'onHeadersReceived',
    'onAuthRequired', 'onBeforeRedirect', 'onResponseStarted', 'onCompleted', 'onErrorOccurred',
  ]);

  function actionApi(ns) {
    var api = defineCalls({}, ns, [
      'setTitle', 'getTitle', 'setIcon', 'setPopup', 'getPopup', 'setBadgeText', 'getBadgeText',
      'setBadgeBackgroundColor', 'getBadgeBackgroundColor', 'setBadgeTextColor',
      'getBadgeTextColor', 'enable', 'disable', 'isEnabled', 'openPopup', 'getUserSettings',
    ]);
    return defineEvents(api, ns, ['onClicked']);
  }
  var browserAction = actionApi('browserAction');
  var action = actionApi('action');

  // Menu items are made without waiting: create() returns the id at once.
  var nextMenuId = 1;
  function menusApi(ns) {
    var api = defineCalls({}, ns, ['update', 'remove', 'removeAll']);
    api.create = function (properties, callback) {
      properties = properties || {};
      var id = properties.id !== undefined ? properties.id : 'menu-' + (nextMenuId++);
      call(ns, 'create', [Object.assign({}, properties, { id: id })]).then(function () {
        if (typeof callback === 'function') callback();
      }, function () {
        if (typeof callback === 'function') callback();
      });
      return id;
    };
    return defineEvents(api, ns, ['onClicked', 'onShown', 'onHidden']);
  }
  var menus = menusApi('menus');
  var contextMenus = menusApi('menus');

  var alarms = defineCalls({}, 'alarms', ['get', 'getAll', 'clear', 'clearAll']);
  alarms.create = function () {
    var args = Array.prototype.slice.call(arguments);
    tell('alarms', 'create', args);
  };
  defineEvents(alarms, 'alarms', ['onAlarm']);

  var commands = defineCalls({}, 'commands', ['getAll', 'reset', 'update']);
  defineEvents(commands, 'commands', ['onCommand']);

  var permissions = defineCalls({}, 'permissions', ['contains', 'getAll', 'request', 'remove']);
  // Asking for access to one host from the toolbar is not offered.
  permissions.addHostAccessRequest = function () {
    return Promise.resolve();
  };
  permissions.removeHostAccessRequest = function () {
    return Promise.resolve();
  };
  defineEvents(permissions, 'permissions', ['onAdded', 'onRemoved']);

  var idle = defineCalls({}, 'idle', ['queryState']);
  idle.setDetectionInterval = function (seconds) {
    tell('idle', 'setDetectionInterval', [seconds]);
  };
  defineEvents(idle, 'idle', ['onStateChanged']);

  var notifications = defineCalls({}, 'notifications', ['update', 'clear', 'getAll']);
  // create([id], options)
  notifications.create = function (first, second) {
    var named = typeof first === 'string';
    return call('notifications', 'create', [named ? first : '', named ? second : first]);
  };
  defineEvents(notifications, 'notifications', ['onClicked', 'onButtonClicked', 'onClosed', 'onShown']);

  var management = defineCalls({}, 'management', ['getSelf', 'getAll', 'setEnabled']);
  defineEvents(management, 'management', ['onInstalled', 'onUninstalled', 'onEnabled', 'onDisabled']);

  var downloads = defineCalls({}, 'downloads', ['download', 'search', 'cancel', 'erase', 'open', 'show']);
  defineEvents(downloads, 'downloads', ['onCreated', 'onChanged', 'onErased']);

  var scripting = {
    executeScript: function (injection) {
      var request = Object.assign({}, injection);
      // A function is sent as code that calls it with its arguments.
      var func = request.func || request.function;
      if (typeof func === 'function') {
        request.code = '(' + func.toString() + ').apply(null, ' + JSON.stringify(request.args || []) + ')';
        delete request.func;
        delete request.function;
        delete request.args;
      }
      return call('scripting', 'executeScript', [request]);
    },
    insertCSS: function (injection) {
      return call('scripting', 'insertCSS', [injection]);
    },
    removeCSS: function () {
      return Promise.resolve();
    },
  };

  // The browser has none of these to change, so each remembers what was asked
  // of it for as long as the page lasts and changes nothing.
  function setting(initial) {
    var value = initial;
    var controlled = false;
    return {
      get: function () {
        return Promise.resolve({
          value: value,
          levelOfControl: controlled ? 'controlled_by_this_extension' : 'controllable_by_this_extension',
        });
      },
      set: function (details) {
        if (details && 'value' in details) {
          value = details.value;
          controlled = true;
        }
        return Promise.resolve(true);
      },
      clear: function () {
        value = initial;
        controlled = false;
        return Promise.resolve(true);
      },
      onChange: createEvent(null, false),
    };
  }
  var privacy = {
    network: {
      networkPredictionEnabled: setting(true),
      webRTCIPHandlingPolicy: setting('default'),
      peerConnectionEnabled: setting(true),
      httpsOnlyMode: setting('never'),
    },
    // The browser saves no passwords and fills nothing in, which is what a
    // password manager asks before it offers to take over.
    services: {
      passwordSavingEnabled: setting(false),
      autofillAddressEnabled: setting(false),
      autofillCreditCardEnabled: setting(false),
      autofillEnabled: setting(false),
    },
    websites: {
      hyperlinkAuditingEnabled: setting(true),
      referrersEnabled: setting(true),
      resistFingerprinting: setting(false),
      trackingProtectionMode: setting('private_browsing'),
      firstPartyIsolate: setting(false),
    },
  };

  var dns = defineCalls({}, 'dns', ['resolve']);

  var contentScripts = {
    register: function (options) {
      return call('contentScripts', 'register', [options]).then(function (id) {
        return {
          unregister: function () {
            return call('contentScripts', 'unregister', [id]);
          },
        };
      });
    },
  };

  var extension = {
    getURL: runtime.getURL,
    inIncognitoContext: false,
    isAllowedIncognitoAccess: function () {
      return Promise.resolve(false);
    },
    isAllowedFileSchemeAccess: function () {
      return Promise.resolve(false);
    },
    getBackgroundPage: function () {
      return null;
    },
    getViews: function () {
      return [];
    },
  };

  // ---------------------------------------------------------------- assembly

  var browser = {
    runtime: runtime,
    storage: storage,
    i18n: i18n,
    extension: extension,
    // Firefox lets a content script see inside a shadow root the page closed.
    // Here only open ones are visible, which is all the page's own scripts see.
    dom: {
      openOrClosedShadowRoot: function (element) {
        return element && element.shadowRoot ? element.shadowRoot : null;
      },
    },
  };

  // The rest of the API is for the extension's own pages, as in Firefox: content
  // scripts get runtime, storage, i18n and extension, and little else.
  if (isExtensionPage) {
    runtime.connectNative = connectNative;
    runtime.sendNativeMessage = sendNativeMessage;
    browser.tabs = tabs;
    browser.windows = windows;
    browser.webNavigation = webNavigation;
    browser.webRequest = webRequest;
    browser.browserAction = browserAction;
    browser.action = action;
    browser.menus = menus;
    browser.contextMenus = contextMenus;
    browser.alarms = alarms;
    browser.commands = commands;
    browser.permissions = permissions;
    browser.privacy = privacy;
    browser.dns = dns;
    browser.idle = idle;
    browser.notifications = notifications;
    browser.management = management;
    browser.downloads = downloads;
    browser.scripting = scripting;
    browser.contentScripts = contentScripts;
  }

  // `chrome` is the callback flavour of the same API: pass a callback and the
  // call answers through it, with runtime.lastError set when it failed.
  function chromeFlavour(source) {
    var target = {};
    Object.keys(source).forEach(function (key) {
      var value = source[key];
      if (typeof value === 'function') {
        target[key] = function () {
          var args = Array.prototype.slice.call(arguments);
          var callback = typeof args[args.length - 1] === 'function' ? args.pop() : null;
          var result = value.apply(source, args);
          if (!callback || !result || typeof result.then !== 'function') return result;

          result.then(
            function (answer) {
              callback(answer);
            },
            function (error) {
              chromeRuntime.lastError = { message: error && error.message ? error.message : String(error) };
              try {
                callback();
              } finally {
                chromeRuntime.lastError = undefined;
              }
            });
          return undefined;
        };
      } else if (value && typeof value === 'object' && typeof value.addListener !== 'function') {
        target[key] = chromeFlavour(value);
      } else {
        // Events and plain values are shared with the promise flavour.
        target[key] = value;
      }
    });
    return target;
  }

  var chromeRuntime;
  var chromeApi = chromeFlavour(browser);
  chromeRuntime = chromeApi.runtime;

  globalThis.browser = browser;
  globalThis.chrome = chromeApi;

  // ---------------------------------------------------------------- hooks the engine calls

  // A stylesheet from a content script's "css" list.
  globalThis.__bird_insert_css = function (css) {
    try {
      var sheet = new CSSStyleSheet();
      sheet.replaceSync(css);
      document.adoptedStyleSheets = document.adoptedStyleSheets.concat([sheet]);
      return;
    } catch (ignored) {
      // Fall back to a <style> element.
    }

    function add() {
      var style = document.createElement('style');
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    }
    if (document.documentElement) add();
    else document.addEventListener('DOMContentLoaded', add, { once: true });
  };

  // document_end and document_idle scripts run once the document has parsed.
  function documentReady() {
    requestPhase('document_end');
    setTimeout(function () {
      requestPhase('document_idle');
    }, 0);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', documentReady, { once: true });
  } else {
    documentReady();
  }

  // A popup is as big as its content, so an extension's own top-level page says
  // how much room its content takes. The extent is that of what is in the body,
  // because the body itself is as wide as the view.
  if (isExtensionPage && globalThis.window === globalThis.top) {
    var lastWidth = 0;
    var lastHeight = 0;
    var measureTimer = null;

    var measure = function () {
      measureTimer = null;
      var body = document.body;
      var root = document.documentElement;
      if (!body || !root || !root.style) return;

      // A block fills the view, so its box says nothing about how much room its
      // content wants. The root is laid out as big as its content for the
      // moment it takes to read it, and put back before anything paints.
      var sides = [root.style, body.style];
      var saved = sides.map(function (style) {
        return ['width', 'height', 'min-height'].map(function (name) {
          return [style.getPropertyValue(name), style.getPropertyPriority(name)];
        });
      });
      var width = 0;
      var height = 0;
      try {
        root.style.setProperty('width', 'max-content', 'important');
        root.style.setProperty('height', 'max-content', 'important');
        root.style.setProperty('min-height', '0', 'important');
        body.style.setProperty('height', 'auto', 'important');
        body.style.setProperty('min-height', '0', 'important');
        var box = root.getBoundingClientRect();
        width = box.width;
        height = box.height;
      } finally {
        sides.forEach(function (style, index) {
          ['width', 'height', 'min-height'].forEach(function (name, position) {
            var was = saved[index][position];
            if (was[0]) style.setProperty(name, was[0], was[1]);
            else style.removeProperty(name);
          });
        });
      }

      width = Math.ceil(width);
      height = Math.ceil(height);
      if (width === 0 || height === 0) return;
      if (width === lastWidth && height === lastHeight) return;
      lastWidth = width;
      lastHeight = height;
      tell('bird', 'contentSize', [width, height]);
    };

    var scheduleMeasure = function () {
      if (measureTimer === null) measureTimer = setTimeout(measure, 50);
    };

    var watchSize = function () {
      scheduleMeasure();
      if (typeof ResizeObserver === 'function') {
        var observer = new ResizeObserver(scheduleMeasure);
        observer.observe(document.documentElement);
        observer.observe(document.body);
      }
      if (typeof MutationObserver === 'function') {
        new MutationObserver(scheduleMeasure).observe(document.body, {
          attributes: true,
          childList: true,
          subtree: true,
        });
      }
    };

    var startWatching = function () {
      if (document.body) watchSize();
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', startWatching, { once: true });
    } else {
      startWatching();
    }
  }

  // Tell the browser how far the document has got, so that webNavigation can
  // report it. Only a content script's document is a page navigation.
  if (!isExtensionPage) {
    var announce = function (name) {
      tell('bird', 'documentEvent', [name]);
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        announce('DOMContentLoaded');
      }, { once: true });
    } else {
      announce('DOMContentLoaded');
    }
    if (document.readyState !== 'complete' && typeof addEventListener === 'function') {
      addEventListener('load', function () {
        announce('load');
      }, { once: true });
    } else if (document.readyState === 'complete') {
      announce('load');
    }
  }
})();
