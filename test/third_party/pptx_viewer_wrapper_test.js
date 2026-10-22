const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

test('waits for PPTX renderer completion rather than quiet DOM', async () => {
  const source = fs.readFileSync(
    path.resolve(
      __dirname,
      '../../third_party/offline_document_viewer/assets/viewers/pptx.js',
    ),
    'utf8',
  );
  const messages = [];
  const handlers = {};
  let rendererOptions;
  const slides = [];
  const stage = {
    querySelectorAll: () => slides,
    querySelector: () => null,
  };
  const input = {
    style: {},
    dispatchEvent: () => true,
  };
  const context = {
    document: {
      documentElement: { clientWidth: 100 },
      body: { appendChild: () => {} },
      createElement: () => input,
      getElementById: () => stage,
    },
    window: {
      jQuery: () => ({
        pptxToHtml: (options) => {
          rendererOptions = options;
        },
      }),
    },
    Bridge: {
      on: (type, handler) => {
        handlers[type] = handler;
      },
      send: (type, payload) => messages.push({ type, payload }),
      start: (render) => {
        context.render = render;
      },
    },
    File: class {},
    DataTransfer: class {
      items = { add: () => {} };
      files = [];
    },
    Event: class {},
    performance: { now: () => 1 },
  };
  vm.runInNewContext(source, context);
  context.render(new Uint8Array([1, 2, 3]));

  await new Promise((resolve) => setTimeout(resolve, 450));
  assert.deepEqual(messages, []);

  slides.push({
    offsetWidth: 80,
    offsetHeight: 40,
    style: {},
    textContent: 'First slide',
    setAttribute: () => {},
  });
  rendererOptions.onReady(1);

  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, 'rendered');
  assert.equal(messages[0].payload.units, 1);
});

test('reports renderer errors through the document bridge', () => {
  const source = fs.readFileSync(
    path.resolve(
      __dirname,
      '../../third_party/offline_document_viewer/assets/viewers/pptx.js',
    ),
    'utf8',
  );
  const messages = [];
  let rendererOptions;
  const input = {
    style: {},
    dispatchEvent: () => true,
  };
  const context = {
    document: {
      documentElement: { clientWidth: 100 },
      body: { appendChild: () => {} },
      createElement: () => input,
      getElementById: () => ({ querySelectorAll: () => [] }),
    },
    window: {
      jQuery: () => ({
        pptxToHtml: (options) => {
          rendererOptions = options;
        },
      }),
    },
    Bridge: {
      on: () => {},
      send: (type, payload) => messages.push({ type, payload }),
      start: (render) => {
        context.render = render;
      },
    },
    File: class {},
    DataTransfer: class {
      items = { add: () => {} };
      files = [];
    },
    Event: class {},
    performance: { now: () => 1 },
  };
  vm.runInNewContext(source, context);
  context.render(new Uint8Array([1]));
  rendererOptions.onError(new Error('Invalid presentation'));

  assert.equal(messages.length, 1);
  assert.equal(messages[0].type, 'error');
  assert.match(messages[0].payload.detail, /Invalid presentation/);
});
