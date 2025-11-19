document.addEventListener('DOMContentLoaded', () => {
  const calendarEl = document.getElementById('calendar');
  const titleEl = document.getElementById('calendar-title');
  const resetBtn = document.getElementById('reset-date');
  const prevBtn = document.getElementById('prev-month');
  const nextBtn = document.getElementById('next-month');
  const todayBtn = document.getElementById('filter-today');
  const weekBtn = document.getElementById('filter-week');
  const rangeButtons = [resetBtn, todayBtn, weekBtn];
  if (!calendarEl) return;

  const eventCards = document.querySelectorAll('.event-card');
  const events = Array.from(eventCards).map(card => ({
    date: card.dataset.date,
    color: card.dataset.categoryColor,
    category: card.dataset.category
  }));

  const today = new Date();
  let currentYear = today.getFullYear();
  let currentMonth = today.getMonth();
  let selectedRange = null; // {start, end}

  // Set "Todas As Datas" as active by default
  activateRangeButton(resetBtn);

  buildCalendar(currentYear, currentMonth);

  prevBtn.addEventListener('click', () => {
    currentMonth--;
    if (currentMonth < 0) {
      currentMonth = 11;
      currentYear--;
    }
    buildCalendar(currentYear, currentMonth);
  });

  nextBtn.addEventListener('click', () => {
    currentMonth++;
    if (currentMonth > 11) {
      currentMonth = 0;
      currentYear++;
    }
    buildCalendar(currentYear, currentMonth);
  });


  todayBtn.addEventListener('click', () => {
    const iso = formatISO(today);
    activateRangeButton(todayBtn);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', { detail: { start: iso, end: iso } }));
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectRange(iso, iso);
    buildCalendar(currentYear, currentMonth);
  });

  weekBtn.addEventListener('click', () => {
    const start = startOfWeek(today);
    const end = endOfWeek(today);
    activateRangeButton(weekBtn);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', { detail: { start, end } }));
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectRange(start, end);
    buildCalendar(currentYear, currentMonth);
  });

  resetBtn.addEventListener('click', () => {
    document.dispatchEvent(new CustomEvent('calendar:clearDate'));
    activateRangeButton(resetBtn);
    clearSelection();
  });

  document.addEventListener('calendar:reset', clearSelection);

  function clearSelection() {
    calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectedRange = null;
    activateRangeButton(resetBtn);
    buildCalendar(currentYear, currentMonth);
  }

  function buildCalendar(year, month) {
    const monthName = new Date(year, month).toLocaleString('pt-PT', { month: 'long', year: 'numeric' });
    titleEl.textContent = `${monthName}`;
    calendarEl.innerHTML = '';

    const daysOfWeek = ['', 'Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    daysOfWeek.forEach(dayName => {
      const header = document.createElement('div');
      header.className = 'calendar-header';
      header.textContent = dayName;
      calendarEl.appendChild(header);
    });

    const firstDay = new Date(year, month, 1);
    const offset = firstDay.getDay(); // domingo start
    const startDate = new Date(year, month, 1 - offset);

    for (let week = 0; week < 6; week++) {
      const weekStart = new Date(startDate);
      weekStart.setDate(startDate.getDate() + week * 7);

      const weekBtn = document.createElement('button');
      weekBtn.className = 'week-btn';
      const weekEnd = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 6);
      const weekLabel = `Selecionar semana de ${formatDisplayDate(weekStart)} a ${formatDisplayDate(weekEnd)}`;
      weekBtn.type = 'button';
      weekBtn.setAttribute('aria-label', weekLabel);
      weekBtn.innerHTML = `<span class="sr-only">${weekLabel}</span><span aria-hidden="true" class="week-btn-icon">&raquo;</span>`;
      const startISO = formatISO(weekStart);
      const endISO = formatISO(weekEnd);
      weekBtn.dataset.start = startISO;
      weekBtn.dataset.end = endISO;
      if (selectedRange && selectedRange.start === startISO && selectedRange.end === endISO) {
        weekBtn.classList.add('week-btn--active');
      }
      weekBtn.addEventListener('click', () => {
        activateRangeButton(null); // Desativar filtros rápidos ao escolher uma semana manualmente
        calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
        calendarEl.querySelectorAll('.week-btn').forEach(b => b.classList.remove('week-btn--active'));
        document.dispatchEvent(new CustomEvent('calendar:rangeSelected', { detail: { start: startISO, end: endISO } }));
        selectRange(startISO, endISO);
        weekBtn.classList.add('week-btn--active');
        highlightSelection();
      });
      calendarEl.appendChild(weekBtn);

      for (let i = 0; i < 7; i++) {
        const date = new Date(weekStart);
        date.setDate(weekStart.getDate() + i);
        const dateStr = formatISO(date);
        const cell = document.createElement('button');
        cell.type = 'button';
        cell.className = 'cal-day';
        cell.dataset.date = dateStr;
        cell.innerHTML = `<span class="calendar-day-number">${date.getDate()}</span>`;
        if (dateStr === formatISO(new Date())) {
          cell.classList.add('is-today');
        }
        if (date.getMonth() !== month) {
          cell.querySelector('.calendar-day-number').classList.add('text-gray-400', 'font-normal');
        }

        const dots = document.createElement('div');
        dots.className = 'calendar-event-dots';
        const categoriesOnDate = new Set();
        events.filter(e => e.date === dateStr).forEach(e => {
          if (!categoriesOnDate.has(e.category)) {
            const dot = document.createElement('span');
            dot.className = 'calendar-event-dot';
            dot.style.backgroundColor = e.color;
            dots.appendChild(dot);
            categoriesOnDate.add(e.category);
          }
        });
        if (dots.children.length > 0) {
          dots.setAttribute('role', 'presentation');
          cell.appendChild(dots);
        } else {
          const spacer = document.createElement('span');
          spacer.className = 'calendar-event-spacer';
          spacer.setAttribute('aria-hidden', 'true');
          cell.appendChild(spacer);
        }

        if (selectedRange && dateStr >= selectedRange.start && dateStr <= selectedRange.end) {
          cell.classList.add('selected');
        }

        cell.addEventListener('click', () => {
          if (cell.classList.contains('selected')) {
            cell.classList.remove('selected');
            selectedRange = null;
            document.dispatchEvent(new CustomEvent('calendar:clearDate'));
          } else {
            calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
            cell.classList.add('selected');
            activateRangeButton(null); // Desativar filtros rápidos ao escolher uma data individual
            selectRange(dateStr, dateStr);
            document.dispatchEvent(new CustomEvent('calendar:dateSelected', { detail: { date: dateStr } }));
          }
        });

        calendarEl.appendChild(cell);
      }
    }
    highlightSelection();
  }

  function activateRangeButton(btn) {
    // Reset all buttons to inactive before applying the desired state
    rangeButtons.forEach(b => {
      b.classList.remove('btn--active');
      b.classList.add('btn--inactive');
    });

    if (btn === resetBtn) {
      resetBtn.classList.remove('btn--inactive');
      resetBtn.classList.add('btn--active');
    } else if (btn) {
      btn.classList.remove('btn--inactive');
      btn.classList.add('btn--active');
    }
  }

  function selectRange(start, end) {
    selectedRange = { start, end };
  }

  function highlightSelection() {
    calendarEl.querySelectorAll('.week-btn').forEach(btn => {
      btn.classList.remove('week-btn--active');
      if (selectedRange && btn.dataset.start === selectedRange.start && btn.dataset.end === selectedRange.end) {
        btn.classList.add('week-btn--active');
      }
    });
    if (!selectedRange) return;
    calendarEl.querySelectorAll('.cal-day').forEach(cell => {
      const d = cell.dataset.date;
      if (d >= selectedRange.start && d <= selectedRange.end) {
        cell.classList.add('selected');
      }
    });
  }


  function startOfWeek(date) {
    const d = new Date(date);
    const day = d.getDay();
    d.setDate(d.getDate() - day); // domingo start
    return formatISO(d);
  }

  function endOfWeek(date) {
    const start = new Date(date);
    const day = start.getDay();
    start.setDate(start.getDate() + (6 - day)); // domingo start
    return formatISO(start);
  }

  function formatISO(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * Formats a JavaScript Date object into a short, localized string for display.
   * Used for accessibility labels and UI elements.
   * @param {Date} date - The date to format.
   * @returns {string} - Formatted date string in 'dd MMM' format (Portuguese).
   */
  function formatDisplayDate(date) {
    return date.toLocaleDateString('pt-PT', { day: '2-digit', month: 'short' });
  }
});
