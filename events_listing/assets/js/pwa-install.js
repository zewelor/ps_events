document.addEventListener('DOMContentLoaded', () => {
  const installBanner = document.getElementById('pwa-install-banner');
  const installButton = document.getElementById('install-pwa-btn');
  const closeButton = document.getElementById('close-pwa-banner-btn'); // Added close button
  let deferredPrompt;

  window.addEventListener('beforeinstallprompt', (e) => {
    // Store the event so it can be triggered later.
    deferredPrompt = e;
    // Update UI to notify the user they can add to home screen
    if (installBanner) {
      installBanner.classList.remove('hidden');
    }
  });

  if (installButton) {
    installButton.addEventListener('click', async () => {
      if (deferredPrompt) {
        // Show the install prompt
        deferredPrompt.prompt();
        // Wait for the user to respond to the prompt
        const { outcome } = await deferredPrompt.userChoice;
        console.log(`User response to the install prompt: ${outcome}`);
        // We've used the prompt, and can't use it again, throw it away
        deferredPrompt = null;
        // Hide the install banner
        if (installBanner) {
          installBanner.classList.add('hidden');
        }
      } else {
        console.log('PWA install prompt not available');
        // Optionally, inform the user that the app can't be installed at this moment,
        // or that it's already installed.
        if (installBanner) {
          // Keep the close button functional even if prompt is not available
          installBanner.querySelector('span').textContent = 'A aplicação já foi instalada ou não pode ser instalada neste navegador.';
          installButton.classList.add('hidden'); // Hide install button if not available
        }
      }
    });
  }

  // Added event listener for the close button
  if (closeButton) {
    closeButton.addEventListener('click', () => {
      if (installBanner) {
        installBanner.classList.add('hidden');
      }
    });
  }

  // Check if the app is already installed
  if (window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone) {
    if (installBanner) {
      installBanner.classList.add('hidden');
    }
  }
});
