// Toggle calendar visibility on mobile

(function() {
  'use strict';
  document.addEventListener('DOMContentLoaded', () => {
    const toggleBtn = document.getElementById('calendar-toggle');
    const calendarWrapper = document.getElementById('calendar-wrapper');
    if (!toggleBtn || !calendarWrapper) return;

    function updateText() {
      toggleBtn.textContent = calendarWrapper.classList.contains('hidden') ? 'Mostrar Calendário' : 'Esconder Calendário';
    }

    toggleBtn.addEventListener('click', () => {
      calendarWrapper.classList.toggle('hidden');
      updateText();
    });

    updateText();
  });
})();
