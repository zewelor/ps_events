const {test, expect} = require('@playwright/test');

test('a reviewed event needs a valid form, sign-in and explicit consent', async ({page, context, baseURL}) => {
  const credential = 'test.' + Buffer.from('{"email":"submitter@example.test"}').toString('base64') + '.signature';
  await context.route('**/*', route => new URL(route.request().url()).origin === baseURL
    ? route.continue() : route.abort());
  await context.route('https://accounts.google.com/gsi/client', route => route.fulfill({
    contentType: 'application/javascript',
    body: `
      window.google = {accounts: {id: {
        initialize({callback}) { this.signIn = () => callback({credential: ${JSON.stringify(credential)}}); },
        renderButton(container) {
          const button = document.createElement('button');
          button.textContent = 'Sign in for test';
          button.onclick = this.signIn;
          container.append(button);
        }
      }}};
    `
  }));

  const submissions = [];
  await context.route(baseURL + '/add_event', async route => {
    submissions.push(route.request());
    await route.fulfill({json: {status: 'ok', message: 'Evento adicionado no teste'}});
  });
  const event = {
    name: 'São João & amigos',
    description: 'Música ao vivo e atividades para toda a família. '.repeat(12).trim(),
    start_date: '5/6/2026',
    end_date: '6/6/2026',
    end_time: '24:00',
    category: 'Música',
    contact_email: 'evento@example.test',
    event_image: 'untrusted.webp',
    google_token: 'untrusted',
    responsibility_agreement: 'on'
  };
  const ready = {name: 'Concerto no auditório', location: 'Auditório'};
  await context.route(baseURL + '/health', route => route.fulfill({status: 200}));
  await context.route(baseURL + '/events_ocr', route => route.fulfill({
    status: 422,
    json: {
      status: 'error',
      error_code: 'ocr_review_required',
      message: 'Nenhum evento foi submetido.',
      events: [ready],
      review_items: [
        {candidate: {...event, location: null}, reason: 'missing_start_date'},
        {candidate: null, message: 'Consulte o cartaz para confirmar os dados.'}
      ]
    }
  }));
  const ocr = page;
  await ocr.goto('/event_ocr/');
  await ocr.getByRole('button', {name: 'Sign in for test'}).click();
  await ocr.locator('#event_image').setInputFiles(require.resolve('../test/fixtures/ocr/images/pijama_2026_facebook_poster.jpg'));
  await ocr.locator('#submit-btn').click();
  const review = ocr.locator('#duplicate-review');
  await expect(review).toContainText('Nenhum evento foi submetido.');
  await expect(review).toContainText('Indique a data de início do evento.');
  const readyCard = review.locator('article').filter({hasText: ready.name});
  await expect(readyCard.getByRole('link')).toHaveAttribute('href', /\/add_event\/#prefill=/);
  await expect(review.getByRole('link', {name: 'Preencher formulário'})).toHaveAttribute('href', '/add_event/');
  const popup = ocr.waitForEvent('popup');
  await review.locator('article').filter({hasText: event.name}).getByRole('link').click();
  const correction = await popup;
  await expect(review).toBeVisible();
  expect(submissions).toHaveLength(0);

  const form = correction.locator('#add-event form');
  const location = form.locator('#location');
  const description = form.getByLabel('Descrição');
  const startDate = form.getByLabel('Data de início');
  const consent = form.getByRole('checkbox');
  const submit = form.getByRole('button', {name: /Adicionar evento/});
  await expect(form.getByLabel('Nome')).toHaveValue(event.name);
  await expect(startDate).toHaveValue('');
  await expect(startDate).toBeFocused();
  await expect(correction.getByRole('status').filter({hasText: 'Sugestão do OCR'})).toContainText('5/6/2026');
  await expect(form.getByLabel('Data de fim')).toHaveValue('2026-06-06');
  await expect(form.getByLabel('Hora de fim')).toHaveValue('24:00');
  await expect(location).toHaveValue('');
  expect(await location.evaluate(field => field.validity.valueMissing)).toBe(false);
  await expect(description).toHaveValue(event.description);
  await expect(description).toHaveAttribute('maxlength', '2000');
  await expect(consent).not.toBeChecked();
  await expect(form.locator('[name="google_token"]')).toHaveValue('');

  await form.getByLabel('Hora de fim').fill('24:01');
  expect(await form.getByLabel('Hora de fim').evaluate(field => field.validity.patternMismatch)).toBe(true);
  await form.getByLabel('Hora de fim').fill('24:00');
  await consent.check();
  await submit.click();
  await expect(startDate).toBeFocused();
  expect(await startDate.evaluate(field => field.validity.valueMissing)).toBe(true);
  expect(submissions).toHaveLength(0);

  await startDate.fill('2026-06-05');
  await submit.click();
  await expect(correction.getByRole('alert')).toContainText(/iniciar sessão com o Google/);
  expect(submissions).toHaveLength(0);

  await consent.uncheck();
  await correction.getByRole('button', {name: 'Sign in for test'}).click();
  await expect(form.locator('#contact_email')).toHaveValue(event.contact_email);
  await submit.click();
  await expect(consent).toBeFocused();
  expect(submissions).toHaveLength(0);

  await consent.check();
  await submit.click();
  await expect(correction.getByText('Evento adicionado no teste')).toBeVisible();
  expect(submissions).toHaveLength(1);
  const request = submissions[0];
  expect(request.method()).toBe('POST');
  const body = await new Response(request.postDataBuffer(), {
    headers: {'content-type': request.headers()['content-type']}
  }).formData();
  expect(Object.fromEntries(body)).toMatchObject({
    name: event.name,
    description: event.description,
    start_date: '2026-06-05',
    end_date: '2026-06-06',
    end_time: '24:00',
    category: 'Música',
    location: '',
    contact_email: event.contact_email,
    google_token: credential,
    price_type: 'Desconhecido',
    responsibility_agreement: 'on'
  });
  expect(body.get('event_image').size).toBe(0);
  await expect(form.getByLabel('Hora de fim')).toHaveAttribute('type', 'time');
});
