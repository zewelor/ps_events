const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function submission(responses) {
  const posted = [];
  const context = vm.createContext({
    window: {}, FormData,
    document: {getElementById: () => null},
    fetch: async (_url, {body}) => {
      posted.push(Object.fromEntries(body));
      const {code, body: response} = responses.shift();
      return {ok: code === 200, status: code, json: async () => response};
    }
  });
  vm.runInContext(fs.readFileSync('events_listing/assets/js/upload_form.js', 'utf8'), context);
  const data = new FormData();
  data.set('event_text', 'Original source context');
  return {
    posted,
    submit: (onConflict) => context.window.PXOForms.submitUploadForm({
      form: {action: '/add_event'}, data, onConflict,
      submitBtn: {classList: {add() {}, remove() {}}}
    })
  };
}

test('successive reviews retain all explicit acknowledgements', async () => {
  const review = {status: 'needs_review', results: [{status: 'conflict'}]};
  const retries = [];
  const flow = submission([
    {code: 409, body: review},
    {code: 409, body: review},
    {code: 200, body: {status: 'ok', outcome: 'added'}}
  ]);

  await flow.submit((_result, retry) => retries.push(retry));
  await retries[0](['candidate-A']);
  await retries[1](['candidate-B']);

  assert.deepEqual(JSON.parse(flow.posted[2].distinct_from), ['candidate-A', 'candidate-B']);
  assert.equal(flow.posted[2].event_text, 'Original source context');
});

test('partial ingestion failure preserves review results without replaying the batch', async () => {
  const body = {
    status: 'error', error_code: 'ingestion_failed',
    counts: {added: 1, skipped: 0, conflicted: 1},
    results: [{status: 'conflict'}, {status: 'added'}, {status: 'failed'}, {status: 'not_attempted'}]
  };
  let received;
  const flow = submission([{code: 503, body}]);

  await flow.submit((result, _retry, source) => { received = {result, source}; });

  assert.ok(received, 'Structured partial results must reach the review UI');
  assert.equal(received.result, body);
  assert.equal(received.source.get('event_text'), 'Original source context');
  assert.equal(flow.posted.length, 1, 'Failed/unknown writes must not be automatically repeated');
});
