(function() {
  const TOAST_DEFAULTS = {
    success: {
      bgClass: 'bg-green-600',
      duration: 4000,
      role: 'status',
      live: 'polite'
    },
    info: {
      bgClass: 'bg-slate-700',
      duration: 0,
      role: 'status',
      live: 'polite'
    },
    error: {
      bgClass: 'bg-red-600',
      duration: 0,
      role: 'alert',
      live: 'assertive'
    }
  };

  const EVENT_FIELD_LABELS = {
    name: 'Nome', start_date: 'Data de início', start_time: 'Hora de início',
    end_date: 'Data de fim', end_time: 'Hora de fim', location: 'Local',
    description: 'Descrição', category: 'Categoria', organizer: 'Organizador',
    contact_email: 'Email de contacto', contact_tel: 'Telefone de contacto',
    price_type: 'Preço', event_link1: 'Ligação 1', event_link2: 'Ligação 2',
    event_link3: 'Ligação 3', event_link4: 'Ligação 4'
  };

  const PREFILL_REVIEW_FIELDS = {
    conflicting_location_evidence: ['location', 'Confirme o local do evento.'],
    missing_start_date: ['start_date', 'Indique a data de início do evento.'],
    conflicting_inset: ['start_date', 'Confirme a data e a hora do evento antes de submeter.']
  };

  function validationFieldHints(fields, event) {
    return fields.map(field => {
      const value = event?.[field];
      const hint = `Verifique o campo «${EVENT_FIELD_LABELS[field]}».`;
      return typeof value === 'string' && value ? `${hint} Sugestão do OCR: ${value}.` : hint;
    });
  }

  function prefillEventForm(form, notice) {
    const prefix = '#prefill=';
    const hash = window.location.hash;
    if (!hash.startsWith(prefix)) return false;

    let payload;
    try {
      payload = JSON.parse(decodeURIComponent(hash.slice(prefix.length)));
    } catch (_) {}

    notice.classList.remove('hidden');
    const event = payload?.event;
    if (!event || typeof event !== 'object' || Array.isArray(event)) {
      notice.textContent = 'Não foi possível ler os dados do link de revisão. Pode preencher o formulário manualmente.';
      return false;
    }

    const reason = payload.reason;
    const [reviewKey, reviewMessage] = typeof reason === 'string' && Object.hasOwn(PREFILL_REVIEW_FIELDS, reason)
      ? PREFILL_REVIEW_FIELDS[reason]
      : [];
    const invalidFields = Array.isArray(payload.validation_fields)
      ? payload.validation_fields.filter(field => typeof field === 'string' && Object.hasOwn(EVENT_FIELD_LABELS, field))
      : [];
    notice.textContent = reviewMessage || 'Reveja os dados do evento e complete o que falta antes de submeter.';
    if (reason === 'missing_start_date' && typeof event.start_date === 'string' && event.start_date) {
      notice.textContent += ` Sugestão do OCR: ${event.start_date}.`;
    }
    if (invalidFields.length) notice.textContent += ` ${validationFieldHints(invalidFields, event).join(' ')}`;

    for (const key of Object.keys(EVENT_FIELD_LABELS)) {
      const field = form.elements.namedItem(key);
      if (!field) continue;
      let value = typeof event[key] === 'string' ? event[key] : '';
      if (key === 'start_date' && reason === 'missing_start_date') value = '';
      if (field.type === 'date') {
        value = value.replace(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/, (_match, day, month, year) =>
          `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`);
      }
      if (key === 'end_time' && value === '24:00') {
        field.type = 'text';
        field.pattern = '([01][0-9]|2[0-3]):[0-5][0-9]|24:00';
        form.addEventListener('reset', () => {
          field.type = 'time';
          field.removeAttribute('pattern');
        }, {once: true});
      }
      field.value = value;
      if (key === 'price_type' && !field.value) field.value = 'Desconhecido';
    }

    const focusField = reviewKey || invalidFields[0];
    const reviewField = focusField ? form.elements.namedItem(focusField) : form.querySelector(':invalid');
    reviewField?.focus();
    form.addEventListener('reset', () => notice.classList.add('hidden'), {once: true});
    return true;
  }

  function dismissToast(toast) {
    if (!toast || !toast.isConnected || toast.dataset.state === 'closing') return;

    toast.dataset.state = 'closing';
    toast.classList.remove('opacity-100', 'translate-y-0');
    toast.classList.add('opacity-0', 'translate-y-2');
    toast.addEventListener('transitionend', () => toast.remove(), {once: true});
  }

  function showToast(message, type = 'success', options = {}) {
    const container = document.getElementById('toast-container');
    if (!container) return null;

    const defaults = TOAST_DEFAULTS[type] || TOAST_DEFAULTS.success;
    const duration = options.duration ?? defaults.duration;
    const dismissible = options.dismissible ?? true;

    container.classList.add('pointer-events-none');

    const toast = document.createElement('div');
    toast.className = [
      defaults.bgClass,
      'pointer-events-auto flex w-11/12 max-w-xl items-start gap-3 rounded-xl border border-black/10 px-4 py-3 text-white shadow-lg transition-all duration-200 ease-out opacity-0 translate-y-2'
    ].join(' ');
    toast.setAttribute('role', options.role || defaults.role);
    toast.setAttribute('aria-live', options.live || defaults.live);

    const messageElement = document.createElement('div');
    messageElement.className = 'min-w-0 flex-1 text-sm leading-6';
    messageElement.textContent = message;
    toast.appendChild(messageElement);

    if (dismissible) {
      const closeButton = document.createElement('button');
      closeButton.type = 'button';
      closeButton.className = 'shrink-0 rounded-full p-1 text-white/80 transition-colors duration-200 hover:bg-white/10 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-white/80';
      closeButton.setAttribute('aria-label', 'Fechar aviso');
      closeButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor" class="h-5 w-5"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>';
      closeButton.addEventListener('click', () => dismissToast(toast));
      toast.appendChild(closeButton);
    }

    container.appendChild(toast);

    requestAnimationFrame(() => {
      toast.classList.remove('opacity-0', 'translate-y-2');
      toast.classList.add('opacity-100', 'translate-y-0');
    });

    if (duration > 0) {
      setTimeout(() => dismissToast(toast), duration);
    }

    return toast;
  }

  function copyFormData(data) {
    const copy = new FormData();
    data.forEach((value, key) => copy.append(key, value));
    return copy;
  }

  function acknowledgedFingerprints(data, fingerprints) {
    let previous = [];
    try {
      const parsed = JSON.parse(data.get('distinct_from') || '[]');
      if (Array.isArray(parsed)) previous = parsed;
    } catch (_) {}
    return [...new Set([...previous, ...fingerprints].filter((value) => typeof value === 'string' && value))];
  }

  function submitFormData({ form, submitBtn, action, data, onSuccess, onSkipped, onConflict, onOcrReview }) {
    submitBtn.disabled = true;
    submitBtn.classList.add('is-loading');
    return fetch(action || form.action, { method: 'POST', body: data })
      .then(async (response) => {
        let result;
        try {
          result = await response.json();
        } catch (_) {
          throw new Error(`Erro ${response.status}`);
        }

        if (response.status === 422 && result.error_code === 'ocr_review_required' && onOcrReview) {
          onOcrReview(result, data);
          return;
        }

        const ingestionFailure = response.status === 503 && result.status === 'error' && result.error_code === 'ingestion_failed';
        if (result.status === 'needs_review' || ingestionFailure) {
          if (onConflict) {
            onConflict(result, (fingerprints) => {
              const retryData = copyFormData(data);
              retryData.set('distinct_from', JSON.stringify(acknowledgedFingerprints(data, fingerprints)));
              if (result.image_ref) {
                retryData.delete('event_image');
                retryData.set('image_ref', result.image_ref);
              }
              return submitFormData({ form, submitBtn, action, data: retryData, onSuccess, onSkipped, onConflict, onOcrReview });
            }, data);
            if (ingestionFailure) showToast(result.message || `Erro ${response.status}`, 'error');
          } else if (ingestionFailure) {
            throw new Error(result.message || `Erro ${response.status}`);
          } else {
            showToast(result.message || 'É necessária uma revisão antes de continuar.', 'info');
          }
          return;
        }

        if (!response.ok) throw new Error(result.message || `Erro ${response.status}`);

        if (result.status === 'ok') {
          if (onOcrReview && (result.review_items?.length || result.results?.some(item => item.uncertain_fields))) {
            onOcrReview(result, data);
          } else if (result.outcome === 'skipped') {
            if (onSkipped) onSkipped(result);
            else showToast(result.message || 'Este evento já se encontra registado.', 'info');
          } else if (onSuccess) {
            onSuccess(result);
          } else {
            showToast(result.message || 'Submissão concluída.', 'success');
          }
        } else {
          throw new Error(result.message || 'Erro desconhecido');
        }
      })
      .catch((err) => {
        showToast(err.message, 'error');
      })
      .finally(() => {
        submitBtn.disabled = false;
        submitBtn.classList.remove('is-loading');
      });
  }

  function submitUploadForm({ form, submitBtn, action, data, onSuccess, onSkipped, onConflict, onOcrReview }) {
    return submitFormData({
      form,
      submitBtn,
      action,
      data: data || new FormData(form),
      onSuccess,
      onSkipped,
      onConflict,
      onOcrReview
    });
  }

  function appendText(parent, tagName, className, text) {
    const element = document.createElement(tagName);
    if (className) element.className = className;
    element.textContent = text;
    parent.appendChild(element);
    return element;
  }

  function eventDateTime(event) {
    const start = [event.start_date, event.start_time].filter(Boolean).join(' às ');
    const end = [event.end_date, event.end_time].filter(Boolean).join(' às ');
    return end && end !== start ? `${start} – ${end}` : start;
  }

  function renderConflictReview(container, result, { onSame, onDifferent }) {
    const conflicts = (result.results || []).filter((item) => item.status === 'conflict');
    container.replaceChildren();
    container.classList.remove('hidden');

    appendText(container, 'p', 'font-semibold', result.message || 'Há eventos semelhantes que precisam de revisão.');
    if (result.counts) {
      appendText(
        container,
        'p',
        'text-sm',
        `Adicionados: ${result.counts.added ?? 0}; já existentes: ${result.counts.skipped ?? 0}; a aguardar revisão: ${result.counts.conflicted ?? conflicts.length}.`
      );
    }

    const actionButtons = [];
    let actionPending = false;
    conflicts.forEach((conflict) => {
      const card = document.createElement('article');
      card.className = 'space-y-3 rounded-lg border border-amber-200 bg-white p-4';
      const submittedEvent = conflict.event || {};
      appendText(card, 'h2', 'font-semibold', submittedEvent.name || 'Evento submetido');
      appendText(card, 'p', 'text-sm', `Data e hora: ${eventDateTime(submittedEvent) || 'Não indicadas'}`);
      appendText(card, 'p', 'text-sm', `Local: ${submittedEvent.location || 'Não indicado'}`);
      renderUncertainFields(card, conflict);

      appendText(card, 'p', 'pt-2 text-sm font-medium', 'Eventos semelhantes já registados:');
      (conflict.candidates || []).forEach((candidate) => {
        const event = candidate.event || {};
        const candidateCard = document.createElement('div');
        candidateCard.className = 'border-l-2 border-amber-300 pl-3 text-sm';
        appendText(candidateCard, 'p', 'font-medium', event.name || 'Evento sem nome');
        appendText(candidateCard, 'p', '', `Data e hora: ${eventDateTime(event) || 'Não indicadas'}`);
        appendText(candidateCard, 'p', '', `Local: ${event.location || 'Não indicado'}`);
        (candidate.differences || []).forEach((field) => {
          const difference = document.createElement('div');
          difference.className = 'mt-2 space-y-1 break-words';
          appendText(difference, 'p', 'font-medium', EVENT_FIELD_LABELS[field] || field);
          appendText(difference, 'p', 'whitespace-pre-wrap', `Submetido: ${submittedEvent[field] || '(sem informação)'}`);
          appendText(difference, 'p', 'whitespace-pre-wrap', `Registado: ${event[field] || '(sem informação)'}`);
          candidateCard.appendChild(difference);
        });
        card.appendChild(candidateCard);
      });

      appendText(card, 'p', 'text-sm', 'Esta opção não guarda alterações. Se os dados forem novos ou corrigidos, mantenha a submissão para revisão.');

      const actions = document.createElement('div');
      actions.className = 'flex flex-wrap gap-3 pt-2';
      const sameButton = document.createElement('button');
      sameButton.type = 'button';
      sameButton.className = 'navigation-button';
      sameButton.textContent = 'Não guardar esta submissão';
      actions.appendChild(sameButton);
      actionButtons.push(sameButton);

      const differentButton = document.createElement('button');
      differentButton.type = 'button';
      differentButton.className = 'navigation-button';
      differentButton.textContent = 'É outro evento';
      actions.appendChild(differentButton);
      actionButtons.push(differentButton);

      const runAction = (handler) => {
        if (actionPending) return;
        actionPending = true;
        actionButtons.forEach((button) => { button.disabled = true; });
        return Promise.resolve()
          .then(() => handler(conflict))
          .finally(() => {
            actionPending = false;
            actionButtons.forEach((button) => { button.disabled = false; });
          });
      };
      sameButton.addEventListener('click', () => runAction(onSame));
      differentButton.addEventListener('click', () => runAction(onDifferent));
      card.appendChild(actions);
      container.appendChild(card);
    });
    renderUnresolvedEvents(container, result.results || []);
  }

  function renderUnresolvedEvents(container, results) {
    const unresolved = results.filter(item => item.status === 'failed' || item.status === 'not_attempted');
    if (!unresolved.length) return;
    appendText(container, 'p', 'font-semibold', 'Há eventos por verificar. Confirme os registos guardados antes de tentar novamente.');
    unresolved.forEach((item) => {
      const card = document.createElement('article');
      card.className = 'space-y-2 rounded-lg border border-amber-200 bg-white p-4';
      const event = item.event || {};
      appendText(card, 'h2', 'font-semibold', event.name || 'Evento sem nome');
      appendText(card, 'p', 'text-sm', item.status === 'failed' ? 'Resultado do registo por confirmar' : 'Registo ainda não tentado');
      renderUncertainFields(card, item);
      Object.entries(event).forEach(([field, value]) => {
        if (field !== 'name' && EVENT_FIELD_LABELS[field] && value) {
          appendText(card, 'p', 'whitespace-pre-wrap break-words text-sm', `${EVENT_FIELD_LABELS[field]}: ${value}`);
        }
      });
      container.appendChild(card);
    });
  }

  function showReviewNotice(container, message) {
    container.replaceChildren();
    container.classList.remove('hidden');
    appendText(container, 'p', '', message);
  }

  function renderHeldOcrEvents(container, result, useEventImage = false) {
    showReviewNotice(container, 'Nenhum evento foi submetido. Reveja e submeta cada evento no formulário.');
    renderOcrReviewItems(container, [...result.events.map(candidate => ({candidate})), ...result.review_items], useEventImage);
  }

  function renderOcrReviewItems(container, items, useEventImage) {
    if (!items.length) return;
    if (useEventImage) appendText(container, 'p', 'text-sm', 'Volte a anexar o cartaz em cada formulário antes de submeter.');

    for (const {candidate, reason, message, validation_errors: validationErrors} of items) {
      const card = document.createElement('article');
      card.className = 'space-y-2 rounded-lg border border-amber-200 bg-white p-4';
      appendText(card, 'h2', 'font-semibold', candidate?.name || 'Evento sem nome');
      const dateTime = candidate && eventDateTime(candidate);
      if (dateTime) appendText(card, 'p', 'text-sm', dateTime);
      if (candidate?.location) appendText(card, 'p', 'text-sm', candidate.location);
      const reviewMessage = Object.hasOwn(PREFILL_REVIEW_FIELDS, reason) && PREFILL_REVIEW_FIELDS[reason][1];
      if (reviewMessage || message) appendText(card, 'p', 'text-sm', reviewMessage || message);
      const invalidFields = Object.keys(validationErrors || {})
        .filter(field => Object.hasOwn(EVENT_FIELD_LABELS, field));
      validationFieldHints(invalidFields, candidate).forEach(hint => appendText(card, 'p', 'text-sm', hint));

      const link = appendText(card, 'a', 'navigation-button', candidate ? 'Rever e submeter' : 'Preencher formulário');
      link.href = '/add_event/';
      link.target = '_blank';
      link.rel = 'noopener';
      if (candidate) {
        const event = Object.fromEntries(Object.keys(EVENT_FIELD_LABELS)
          .filter(field => typeof candidate[field] === 'string')
          .map(field => [field, candidate[field]]));
        const payload = {event, reason: reason ?? null};
        if (invalidFields.length) payload.validation_fields = invalidFields;
        link.hash = 'prefill=' + encodeURIComponent(JSON.stringify(payload));
      }
      container.appendChild(card);
    }
  }

  function renderConfirmedEvents(container, results) {
    const confirmed = results.filter(item => item.event?.name && (item.status === 'added' || item.status === 'skipped'));
    if (!confirmed.length) return;
    const list = document.createElement('ul');
    list.className = 'space-y-1 text-sm';
    for (const item of confirmed) {
      const {status, event} = item;
      const label = status === 'added' ? 'Adicionado' : 'Já existente';
      const dateTime = eventDateTime(event);
      const entry = appendText(list, 'li', '', `${label}: ${event.name}${dateTime ? ` (${dateTime})` : ''}`);
      renderUncertainFields(entry, item);
    }
    container.appendChild(list);
  }

  function renderUncertainFields(container, {uncertain_fields: fields, status, range, existing_row: existingRow}) {
    if (!fields) return;
    appendText(container, 'p', 'text-sm font-medium', 'Campos a verificar');
    for (const [field, {candidate, evidence}] of Object.entries(fields)) {
      const label = EVENT_FIELD_LABELS[field] || field;
      appendText(container, 'p', 'text-sm', `${label}: valor sugerido pelo OCR: ${candidate}. Texto indicado: ${evidence}.`);
    }
    if (status === 'added' || status === 'skipped') {
      const reference = status === 'added' ? range : existingRow;
      appendText(container, 'p', 'text-sm', 'Confirme os dados no cartaz e, se necessário, corrija o registo no Google Sheets.');
      if (reference) appendText(container, 'p', 'text-sm', `Registo: ${reference}`);
    } else {
      appendText(container, 'p', 'text-sm', 'Verifique o resultado do registo antes de corrigir os dados.');
    }
  }

  window.PXOForms = { prefillEventForm, dismissToast, showToast, submitUploadForm, renderConflictReview, renderUnresolvedEvents, showReviewNotice, renderHeldOcrEvents, renderOcrReviewItems, renderConfirmedEvents };
})();
