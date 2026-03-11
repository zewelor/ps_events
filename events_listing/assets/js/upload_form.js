(function() {
  const TOAST_DEFAULTS = {
    success: {
      bgClass: 'bg-green-600',
      duration: 4000,
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

  function submitUploadForm({ form, submitBtn, onSuccess }) {
    const data = new FormData(form);
    submitBtn.disabled = true;
    submitBtn.classList.add('is-loading');
    fetch(form.action, { method: 'POST', body: data })
      .then(async (response) => {
        if (!response.ok) {
          let msg = `Erro ${response.status}`;
          try {
            const r = await response.json();
            msg = r.message || msg;
          } catch (_) {}
          throw new Error(msg);
        }
        const result = await response.json();
        if (result.status === 'ok') {
          onSuccess(result);
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

  window.PXOForms = { dismissToast, showToast, submitUploadForm };
})();
