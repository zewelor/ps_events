/**
 * Scroll to Top Button Functionality
 * Shows/hides button based on scroll position and handles smooth scrolling to top
 */

(function() {
  'use strict';

  // Configuration
  const SCROLL_THRESHOLD = 700;
  const SCROLL_DURATION = 800; // Smooth scroll duration in ms
  const FOOTER_OFFSET = 200; // Distance from footer to adjust button position

  let scrollToTopBtn;
  let isVisible = false;
  let ticking = false;
  let footer;  // Initialize when DOM is ready
  function init() {
    scrollToTopBtn = document.getElementById('scroll-to-top');
    footer = document.querySelector('footer');
    
    if (!scrollToTopBtn) {
      console.warn('Scroll to top button not found');
      return;
    }

    // Add event listeners
    window.addEventListener('scroll', handleScroll, { passive: true });
    scrollToTopBtn.addEventListener('click', handleClick);
  }

  // Handle scroll events with throttling
  function handleScroll() {
    if (!ticking) {
      requestAnimationFrame(updateButtonVisibility);
      ticking = true;
    }
  }

  // Update button visibility based on scroll position
  function updateButtonVisibility() {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    const shouldShow = scrollTop > SCROLL_THRESHOLD;

    // Check if we're near the footer
    const windowHeight = window.innerHeight;
    const documentHeight = document.documentElement.scrollHeight;
    const distanceFromBottom = documentHeight - (scrollTop + windowHeight);
    const isNearFooter = distanceFromBottom < FOOTER_OFFSET;

    if (shouldShow && !isVisible) {
      showButton();
    } else if (!shouldShow && isVisible) {
      hideButton();
    }

    // Adjust button position if near footer
    if (isVisible) {
      if (isNearFooter) {
        scrollToTopBtn.classList.add('near-footer');
      } else {
        scrollToTopBtn.classList.remove('near-footer');
      }
    }

    ticking = false;
  }

  // Show the button with animation
  function showButton() {
    scrollToTopBtn.classList.add('visible');
    isVisible = true;
  }

  // Hide the button with animation
  function hideButton() {
    scrollToTopBtn.classList.remove('visible');
    isVisible = false;
  }

  // Handle button click
  function handleClick(e) {
    e.preventDefault();
    smoothScrollToTop();

    // Add a small bounce effect
    scrollToTopBtn.style.transform = 'scale(0.95)';
    setTimeout(() => {
      scrollToTopBtn.style.transform = '';
    }, 150);
  }

  // Smooth scroll to top
  function smoothScrollToTop() {
    const startPosition = window.pageYOffset;
    const startTime = performance.now();

    function scrollStep(currentTime) {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / SCROLL_DURATION, 1);

      // Easing function for smooth animation
      const ease = easeOutCubic(progress);
      const newPosition = startPosition * (1 - ease);

      window.scrollTo(0, newPosition);

      if (progress < 1) {
        requestAnimationFrame(scrollStep);
      }
    }

    requestAnimationFrame(scrollStep);
  }

  // Easing function for smooth animation
  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  // Initialize when DOM is loaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
