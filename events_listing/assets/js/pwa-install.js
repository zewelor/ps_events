document.addEventListener('DOMContentLoaded', () => {
  const BANNER_DISMISS_KEY = 'pxo-pwa-banner-dismissed-until';
  const BANNER_DISMISS_MS = 7 * 24 * 60 * 60 * 1000;
  const IOS_SAFARI_STATE = 'manual-ios-safari';
  const IOS_OTHER_STATE = 'manual-ios-other';
  const ANDROID_SAMSUNG_STATE = 'manual-android-samsung';
  const OTHER_STATE = 'manual-other';
  const PROMPT_STATE = 'prompt-ready';
  const IOS_SAFARI_STEPS = [
    'Toque em Partilhar. É o botão com uma seta para cima.',
    'Deslize a lista e toque em "Adicionar ao ecrã principal".',
    'Toque em "Adicionar".'
  ];
  const IOS_OTHER_STEPS = [
    'Abra este site no Safari.',
    'No Safari, toque em Partilhar. É o botão com uma seta para cima.',
    'Toque em "Adicionar ao ecrã principal".',
    'Toque em "Adicionar".'
  ];
  const SAMSUNG_STEPS = [
    'Toque no Menu do navegador.',
    'Procure a opção "Adicionar ao ecrã principal" ou "Instalar aplicação".',
    'Confirme para adicionar.'
  ];
  const OTHER_STEPS = [
    'Toque nos 3 pontos ou no Menu do navegador.',
    'Toque em "Instalar app" ou "Adicionar ao ecrã inicial".',
    'Confirme para instalar.'
  ];

  const installBanner = document.getElementById('pwa-install-banner');
  const installCopy = document.getElementById('pwa-install-copy');
  const installButton = document.getElementById('install-pwa-btn');
  const closeButton = document.getElementById('close-pwa-banner-btn');
  const footerCta = document.getElementById('pwa-footer-cta');
  const footerButton = document.getElementById('pwa-footer-install-btn');
  const helpDialog = document.getElementById('pwa-install-help');
  const helpCopy = document.getElementById('pwa-install-help-copy');
  const helpSteps = document.getElementById('pwa-install-steps');
  const closeHelpButton = document.getElementById('close-pwa-help-btn');
  const installTriggers = [installButton, footerButton].filter(Boolean);
  const standaloneQuery = window.matchMedia('(display-mode: standalone)');

  if (!installBanner || !installCopy || !installButton || !closeButton || !footerCta || !footerButton || !helpDialog || !helpCopy || !helpSteps || !closeHelpButton) {
    return;
  }

  let deferredPrompt = null;
  let currentState = fallbackState();
  let footerCtaVisible = false;

  function isIosDevice() {
    return /iPad|iPhone|iPod/.test(window.navigator.userAgent) ||
      (window.navigator.platform === 'MacIntel' && window.navigator.maxTouchPoints > 1);
  }

  function isSafariOnIos() {
    return isIosDevice() && /Safari/.test(window.navigator.userAgent) && !/CriOS|FxiOS|EdgiOS|OPiOS/.test(window.navigator.userAgent);
  }

  function isSamsungInternet() {
    return /SamsungBrowser/i.test(window.navigator.userAgent);
  }

  function isStandalone() {
    return standaloneQuery.matches || window.navigator.standalone === true;
  }

  function isMobileViewport() {
    return window.matchMedia('(max-width: 767px)').matches;
  }

  function shouldShowInstallUi() {
    return isMobileViewport() && !isStandalone();
  }

  function fallbackState() {
    if (isSafariOnIos()) {
      return IOS_SAFARI_STATE;
    }

    if (isIosDevice()) {
      return IOS_OTHER_STATE;
    }

    if (isSamsungInternet()) {
      return ANDROID_SAMSUNG_STATE;
    }

    return OTHER_STATE;
  }

  function installGuide() {
    if (currentState === PROMPT_STATE) {
      return {
        bannerCopy: 'Quer ter o PXO Pulse como app? Toque em Instalar.',
        primaryLabel: 'Instalar',
        footerLabel: 'Instalar app'
      };
    }

    if (currentState === IOS_SAFARI_STATE) {
      return {
        bannerCopy: 'Tem iPhone? Toque em Como instalar.',
        primaryLabel: 'Como instalar',
        footerLabel: 'Como instalar',
        helpCopy: 'Siga estes passos no iPhone ou iPad.',
        steps: IOS_SAFARI_STEPS
      };
    }

    if (currentState === IOS_OTHER_STATE) {
      return {
        bannerCopy: 'No iPhone, a instalação é mais simples no Safari.',
        primaryLabel: 'Ver passos',
        footerLabel: 'Ver passos',
        helpCopy: 'No iPhone ou iPad, instale a app a partir do Safari.',
        steps: IOS_OTHER_STEPS
      };
    }

    if (currentState === ANDROID_SAMSUNG_STATE) {
      return {
        bannerCopy: 'Tem Android? Toque em Como instalar.',
        primaryLabel: 'Como instalar',
        footerLabel: 'Como instalar',
        helpCopy: 'Siga estes passos no navegador Samsung Internet.',
        steps: SAMSUNG_STEPS
      };
    }

    return {
      bannerCopy: 'Se não aparecer o pedido, mostramos como instalar.',
      primaryLabel: 'Como instalar',
      footerLabel: 'Como instalar',
      helpCopy: 'Siga estes passos no seu navegador.',
      steps: OTHER_STEPS
    };
  }

  function isBannerDismissed() {
    const dismissedUntil = Number.parseInt(window.localStorage.getItem(BANNER_DISMISS_KEY) || '0', 10);
    return Number.isFinite(dismissedUntil) && dismissedUntil > Date.now();
  }

  function dismissBanner() {
    window.localStorage.setItem(BANNER_DISMISS_KEY, String(Date.now() + BANNER_DISMISS_MS));
    installBanner.classList.add('hidden');
  }

  function clearBannerDismissal() {
    window.localStorage.removeItem(BANNER_DISMISS_KEY);
  }

  function hideBanner() {
    installBanner.classList.add('hidden');
  }

  function syncBannerVisibility() {
    if (!shouldShowInstallUi() || isBannerDismissed() || footerCtaVisible) {
      hideBanner();
      return;
    }

    installBanner.classList.remove('hidden');
  }

  function syncFooterCtaVisibility() {
    if (footerCta.classList.contains('hidden')) {
      footerCtaVisible = false;
      syncBannerVisibility();
      return;
    }

    const rect = footerCta.getBoundingClientRect();
    footerCtaVisible = rect.top < window.innerHeight && rect.bottom > 0;
    syncBannerVisibility();
  }

  function showBanner() {
    syncBannerVisibility();
  }

  function showFooterCta() {
    if (shouldShowInstallUi()) {
      footerCta.classList.remove('hidden');
    } else {
      footerCta.classList.add('hidden');
    }

    window.requestAnimationFrame(syncFooterCtaVisibility);
  }

  function closeHelpDialog() {
    helpDialog.classList.add('hidden');
  }

  function renderHelpSteps(copy, steps) {
    helpCopy.textContent = copy;
    helpSteps.replaceChildren(
      ...steps.map((step, index) => {
        const item = document.createElement('li');
        item.className = 'flex items-start gap-3';

        const bullet = document.createElement('span');
        bullet.className = 'mt-1 inline-flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-[var(--color-buttons)] text-sm font-semibold text-[var(--color-text-primary)]';
        bullet.textContent = String(index + 1);

        const text = document.createElement('span');
        text.textContent = step;

        item.append(bullet, text);
        return item;
      })
    );
  }

  function openHelpDialog() {
    const guide = installGuide();
    renderHelpSteps(guide.helpCopy, guide.steps);

    helpDialog.classList.remove('hidden');
  }

  function setUiState() {
    currentState = deferredPrompt ? PROMPT_STATE : fallbackState();
    closeHelpDialog();

    if (!shouldShowInstallUi()) {
      hideBanner();
      showFooterCta();
      return;
    }

    const guide = installGuide();
    installCopy.textContent = guide.bannerCopy;
    installButton.textContent = guide.primaryLabel;
    footerButton.textContent = guide.footerLabel;

    showFooterCta();
    showBanner();
  }

  async function handleInstallClick() {
    if (currentState !== PROMPT_STATE || !deferredPrompt) {
      openHelpDialog();
      return;
    }

    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    console.log(`User response to the install prompt: ${outcome}`);
    deferredPrompt = null;

    if (outcome === 'accepted') {
      clearBannerDismissal();
      hideBanner();
      footerCta.classList.add('hidden');
      closeHelpDialog();
      return;
    }

    setUiState();
  }

  installTriggers.forEach((trigger) => {
    trigger.addEventListener('click', handleInstallClick);
  });

  closeButton.addEventListener('click', dismissBanner);
  closeHelpButton.addEventListener('click', closeHelpDialog);
  helpDialog.addEventListener('click', (event) => {
    if (event.target === helpDialog) {
      closeHelpDialog();
    }
  });

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    setUiState();
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    clearBannerDismissal();
    hideBanner();
    footerCta.classList.add('hidden');
    closeHelpDialog();
  });

  const handleDisplayModeChange = () => {
    if (isStandalone()) {
      hideBanner();
      footerCta.classList.add('hidden');
      closeHelpDialog();
      return;
    }

    setUiState();
  };

  if (typeof standaloneQuery.addEventListener === 'function') {
    standaloneQuery.addEventListener('change', handleDisplayModeChange);
  } else if (typeof standaloneQuery.addListener === 'function') {
    standaloneQuery.addListener(handleDisplayModeChange);
  }

  window.addEventListener('scroll', syncFooterCtaVisibility, { passive: true });
  window.addEventListener('resize', setUiState);

  setUiState();
});
