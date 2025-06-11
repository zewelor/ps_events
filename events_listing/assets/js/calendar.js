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
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start: iso, end: iso}}));
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectRange(iso, iso);
    buildCalendar(currentYear, currentMonth);
  });

  weekBtn.addEventListener('click', () => {
    const start = startOfWeek(today);
    const end = endOfWeek(today);
    activateRangeButton(weekBtn);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start, end}}));
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
    rangeButtons.forEach(btn => {
      btn.classList.remove('btn--active');
      btn.classList.add('btn--inactive');
    });
    // Activate "Todas as Datas" (resetBtn) when clearing selection
    resetBtn.classList.remove('btn--inactive');
    resetBtn.classList.add('btn--active');
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectedRange = null;
    buildCalendar(currentYear, currentMonth);
  }

  function buildCalendar(year, month) {
    const monthName = new Date(year, month).toLocaleString('pt-PT', {month:'long', year:'numeric'});
    titleEl.textContent = `${monthName}`;
    calendarEl.innerHTML = '';

    const daysOfWeek = ['Sem', 'Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    daysOfWeek.forEach(dayName => {
      const header = document.createElement('div');
      header.className = 'py-2 font-semibold border-b border-gray-200';
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
      weekBtn.innerHTML = '&raquo;';
      const startISO = formatISO(weekStart);
      const endISO = formatISO(new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 6));
      weekBtn.dataset.start = startISO;
      weekBtn.dataset.end = endISO;
      if (selectedRange && selectedRange.start === startISO && selectedRange.end === endISO) {
        weekBtn.classList.add('week-btn--active');
      }
      weekBtn.addEventListener('click', () => {
        activateRangeButton(null); // This will deactivate all date filter buttons including "Todas as Datas"
        calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
        calendarEl.querySelectorAll('.week-btn').forEach(b => b.classList.remove('week-btn--active'));
        document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start: startISO, end: endISO}}));
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
        cell.className = 'cal-day';
        cell.dataset.date = dateStr;
        cell.innerHTML = `<span>${date.getDate()}</span>`;
        if (date.getMonth() !== month) {
          cell.querySelector('span').classList.add('text-gray-300');
        }

        const dots = document.createElement('div');
        dots.className = 'flex space-x-1 mb-1';
        events.filter(e => e.date === dateStr).forEach(e => {
          const dot = document.createElement('span');
          dot.className = 'w-5 h-5 rounded-full';
          dot.style.backgroundColor = e.color;
          dots.appendChild(dot);
        });
        cell.appendChild(dots);

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
            activateRangeButton(null); // This will deactivate all date filter buttons including "Todas as Datas"
            selectRange(dateStr, dateStr);
            document.dispatchEvent(new CustomEvent('calendar:dateSelected', {detail: {date: dateStr}}));
          }
        });

        calendarEl.appendChild(cell);
      }
    }
    highlightSelection();
  }

  function activateRangeButton(btn) {
    if (btn === resetBtn) {
      // When "Todas as Datas" is selected, deactivate all other date filters
      rangeButtons.forEach(b => {
        b.classList.remove('btn--active');
        b.classList.add('btn--inactive');
      });
      resetBtn.classList.remove('btn--inactive');
      resetBtn.classList.add('btn--active');
    } else if (btn) {
      // When any specific date filter is selected, deactivate all including "Todas as Datas"
      rangeButtons.forEach(b => {
        b.classList.remove('btn--active');
        b.classList.add('btn--inactive');
      });
      btn.classList.remove('btn--inactive');
      btn.classList.add('btn--active');
    } else {
      // When null is passed (for calendar date/week selections), deactivate all buttons including "Todas as Datas"
      rangeButtons.forEach(b => {
        b.classList.remove('btn--active');
        b.classList.add('btn--inactive');
      });
    }
  }

  function selectRange(start, end) {
    selectedRange = {start, end};
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
});
