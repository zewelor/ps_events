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

  function submitFormData({ form, submitBtn, action, data, onSuccess, onSkipped, onConflict }) {
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
              return submitFormData({ form, submitBtn, action, data: retryData, onSuccess, onSkipped, onConflict });
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
          if (result.outcome === 'skipped') {
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

  function submitUploadForm({ form, submitBtn, action, data, onSuccess, onSkipped, onConflict }) {
    return submitFormData({
      form,
      submitBtn,
      action,
      data: data || new FormData(form),
      onSuccess,
      onSkipped,
      onConflict
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

  window.PXOForms = { dismissToast, showToast, submitUploadForm, renderConflictReview, renderUnresolvedEvents, showReviewNotice };
})();
