const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {File} = require('node:buffer');

class Element {
  constructor(tag = 'div') {
    this.tag = tag;
    this.children = [];
    this.listeners = {};
    this.classList = {add() {}, remove() {}};
    this.value = '';
    this.text = '';
  }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; this.text = ''; }
  setAttribute() {}
  addEventListener(type, handler) { this.listeners[type] = handler; }
  get textContent() { return this.text + this.children.map(child => child.textContent).join(' '); }
  set textContent(value) { this.text = value; this.children = []; }
  all() { return [this, ...this.children.flatMap(child => child.all())]; }
}

const imageRef = 'a34a5a3a-2f56-4ef9-b57e-d170d3e40e0c';
const event = (name) => ({name, start_date: '21/11/2026', location: 'Centro Cultural', description: 'Evento com entrada gratuita.', category: 'Música', organizer: 'Associação Cultural'});
const conflict = (name, index) => ({status: 'conflict', index, event: event(name), candidates: [{event: event('Já registado'), differences: ['name'], fingerprint: 'a'.repeat(64)}]});
const failed = {status: 'failed', index: 2, event: event('Concerto com resultado incerto')};
const unattempted = {status: 'not_attempted', index: 3, event: event('Oficina ainda não tentada')};

function reviewFlow(responses, useImage = true) {
  const elements = new Map();
  const getElement = id => {
    if (id === 'toast-container') return null;
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  const form = new Element('form');
  form.action = 'https://fixture.invalid/events_ocr';
  form.entries = [
    ['google_token', 'fixture-token'], ['event_text', 'Contexto original'],
    ['event_image', new File(['image'], 'flyer.png', {type: 'image/png'})]
  ];
  if (useImage) form.entries.push(['use_event_image', 'on']);
  class Form extends FormData {
    constructor(source) { super(); source?.entries.forEach(([key, value]) => this.append(key, value)); }
  }
  const posted = [];
  const context = vm.createContext({
    window: {}, URL, File, FormData: Form,
    document: {querySelector: () => form, getElementById: getElement, createElement: tag => new Element(tag), addEventListener() {}},
    fetch: async (url, {body}) => {
      posted.push({url, data: Object.fromEntries(body)});
      const {code, body: response} = responses.shift();
      return {ok: code === 200, status: code, json: async () => response};
    }
  });
  vm.runInContext(fs.readFileSync('events_listing/assets/js/upload_form.js', 'utf8'), context);
  context.PXOForms = context.window.PXOForms;
  const submit = context.PXOForms.submitUploadForm;
  let submission;
  context.PXOForms.submitUploadForm = options => { submission = submit(options); return submission; };
  const html = fs.readFileSync('events_listing/event_ocr.html', 'utf8');
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/{% unless jekyll.environment == 'development' %}[\s\S]*?{% endunless %}/g, '');
  vm.runInContext(script, context);
  const review = getElement('duplicate-review');
  return {
    posted, review,
    submit() { form.listeners.submit({preventDefault() {}}); return submission; },
    click(label) {
      const button = review.all().find(node => node.tag === 'button' && node.textContent === label);
      assert.ok(button, `Missing action: ${label}`);
      return button.listeners.click();
    },
    buttons() { return review.all().filter(node => node.tag === 'button'); }
  };
}

test('resolving the last conflict preserves failed and unattempted event details', async () => {
  const flow = reviewFlow([{code: 503, body: {
    status: 'error', error_code: 'ingestion_failed', image_ref: imageRef,
    message: 'Não foi possível concluir a submissão.',
    counts: {added: 1, skipped: 0, conflicted: 1},
    results: [conflict('Concerto para rever', 0), {status: 'added'}, failed, unattempted]
  }}]);
  await flow.submit();
  assert.match(flow.review.textContent, /Concerto com resultado incerto/);
  assert.match(flow.review.textContent, /Oficina ainda não tentada/);
  await flow.click('Não guardar esta submissão');
  assert.match(flow.review.textContent, /Concerto com resultado incerto/);
  assert.match(flow.review.textContent, /Oficina ainda não tentada/);
  assert.doesNotMatch(flow.review.textContent, /A revisão terminou/);
  assert.equal(flow.buttons().length, 0);
  assert.equal(flow.posted.length, 1, 'Uncertain writes must not be retried automatically');
});

test('successive distinct occurrences reuse one processed image reference', async () => {
  const flow = reviewFlow([
    {code: 409, body: {status: 'needs_review', image_ref: imageRef, counts: {added: 0, skipped: 0, conflicted: 2}, results: [conflict('Primeiro concerto', 0), conflict('Segundo concerto', 1)]}},
    {code: 200, body: {status: 'ok', outcome: 'added', image_ref: imageRef}},
    {code: 200, body: {status: 'ok', outcome: 'added', image_ref: imageRef}}
  ]);
  await flow.submit();
  await flow.click('É outro evento');
  await flow.click('É outro evento');
  assert.equal(flow.posted.length, 3);
  for (const request of flow.posted.slice(1)) {
    assert.equal(request.url, 'https://fixture.invalid/add_event');
    assert.equal(request.data.image_ref, imageRef);
    assert.equal(request.data.event_image, undefined, 'The source image must not be processed again');
  }
  assert.deepEqual(flow.posted.slice(1).map(request => request.data.name), ['Primeiro concerto', 'Segundo concerto']);
});

test('a failed selected-occurrence write remains visible without offering an automatic retry', async () => {
  const flow = reviewFlow([
    {code: 409, body: {status: 'needs_review', counts: {added: 0, skipped: 0, conflicted: 1}, results: [conflict('Concerto para rever', 0)]}},
    {code: 503, body: {status: 'error', error_code: 'ingestion_failed', message: 'Verifique os eventos antes de tentar novamente.', results: [{...failed, event: event('Concerto para rever')}]}}
  ], false);
  await flow.submit();
  await flow.click('É outro evento');
  assert.match(flow.review.textContent, /Concerto para rever/);
  assert.match(flow.review.textContent, /Resultado do registo por confirmar/);
  assert.equal(flow.buttons().length, 0);
  assert.equal(flow.posted.length, 2);
  assert.equal(flow.posted[1].data.image_ref, undefined);
  assert.equal(flow.posted[1].data.event_image, undefined);
});

test('a partial failure with no conflicts still lists the unresolved events', async () => {
  const flow = reviewFlow([{code: 503, body: {status: 'error', error_code: 'ingestion_failed', results: [failed, unattempted]}}], false);
  await flow.submit();
  assert.match(flow.review.textContent, /Concerto com resultado incerto/);
  assert.match(flow.review.textContent, /Oficina ainda não tentada/);
  assert.equal(flow.posted.length, 1);
});
