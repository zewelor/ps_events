// PWA Install functionality
let deferredPrompt;
let installButton;

document.addEventListener('DOMContentLoaded', function() {
  installButton = document.getElementById('install-pwa-btn');

  // Hide install button initially
  if (installButton) {
    installButton.style.display = 'none';
  }
});

// Listen for beforeinstallprompt event
window.addEventListener('beforeinstallprompt', (e) => {
  console.log('PWA install prompt available');

  // Prevent Chrome 67 and earlier from automatically showing the prompt
  e.preventDefault();

  // Stash the event so it can be triggered later
  deferredPrompt = e;

  // Show install button
  if (installButton) {
    installButton.style.display = 'inline-flex';
  }
});

// Install PWA when button is clicked
function installPWA() {
  if (deferredPrompt) {
    // Show the prompt
    deferredPrompt.prompt();

    // Wait for the user to respond to the prompt
    deferredPrompt.userChoice.then((choiceResult) => {
      if (choiceResult.outcome === 'accepted') {
        console.log('User accepted the install prompt');
      } else {
        console.log('User dismissed the install prompt');
      }
      deferredPrompt = null;
    });
  }
}

// Hide install button after app is installed
window.addEventListener('appinstalled', (evt) => {
  console.log('PWA was installed');
  if (installButton) {
    installButton.style.display = 'none';
  }
});

// Check if app is already installed (running in standalone mode)
function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches ||
         window.navigator.standalone === true;
}

// Hide install button if already in standalone mode
if (isStandalone() && installButton) {
  installButton.style.display = 'none';
}
