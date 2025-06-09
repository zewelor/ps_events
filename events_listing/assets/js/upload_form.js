(function() {
  function showToast(message, type = 'success') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const bg = type === 'success' ? 'bg-green-500' : 'bg-red-500';
    const toast = document.createElement('div');
    toast.className = `${bg} text-white px-4 py-2 rounded shadow transition-opacity duration-500`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => {
      toast.classList.add('opacity-0');
      toast.addEventListener('transitionend', () => toast.remove());
    }, 3000);
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

  window.PXOForms = { showToast, submitUploadForm };
})();
