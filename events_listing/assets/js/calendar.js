document.addEventListener('DOMContentLoaded', () => {
  const calendarEl = document.getElementById('calendar');
  const titleEl = document.getElementById('calendar-title');
  const resetBtn = document.getElementById('reset-date');
  const prevBtn = document.getElementById('prev-month');
  const nextBtn = document.getElementById('next-month');
  const yearDisplay = document.getElementById('year-display');
  const prevYearBtn = document.getElementById('prev-year');
  const nextYearBtn = document.getElementById('next-year');
  const todayBtn = document.getElementById('filter-today');
  const weekBtn = document.getElementById('filter-week');
  const monthBtn = document.getElementById('filter-month');
  const rangeButtons = [todayBtn, weekBtn, monthBtn];
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

  prevYearBtn.addEventListener('click', () => {
    currentYear--;
    buildCalendar(currentYear, currentMonth);
  });

  nextYearBtn.addEventListener('click', () => {
    currentYear++;
    buildCalendar(currentYear, currentMonth);
  });


  todayBtn.addEventListener('click', () => {
    const iso = formatISO(today);
    activateRangeButton(todayBtn);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start: iso, end: iso}}));
    resetBtn.classList.remove('hidden');
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
    resetBtn.classList.remove('hidden');
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectRange(start, end);
    buildCalendar(currentYear, currentMonth);
  });

  monthBtn.addEventListener('click', () => {
    const start = formatISO(new Date(today.getFullYear(), today.getMonth(), 1));
    const end = formatISO(new Date(today.getFullYear(), today.getMonth() + 1, 0));
    activateRangeButton(monthBtn);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start, end}}));
    resetBtn.classList.remove('hidden');
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectRange(start, end);
    buildCalendar(currentYear, currentMonth);
  });

  resetBtn.addEventListener('click', () => {
    document.dispatchEvent(new CustomEvent('calendar:clearDate'));
    activateRangeButton(null);
    clearSelection();
  });

  document.addEventListener('calendar:reset', clearSelection);

  function clearSelection() {
    calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
    rangeButtons.forEach(btn => {
      btn.classList.remove('btn--active');
      btn.classList.add('btn--inactive');
    });
    resetBtn.classList.add('hidden');
    currentYear = today.getFullYear();
    currentMonth = today.getMonth();
    selectedRange = null;
    buildCalendar(currentYear, currentMonth);
  }

  function buildCalendar(year, month) {
    titleEl.textContent = new Date(year, month).toLocaleString('pt-PT', {month:'long', year:'numeric'});
    calendarEl.innerHTML = '';

    const daysOfWeek = ['Sem', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    daysOfWeek.forEach(dayName => {
      const header = document.createElement('div');
      header.className = 'py-2 font-semibold border-b border-gray-200';
      header.textContent = dayName;
      calendarEl.appendChild(header);
    });

    const firstDay = new Date(year, month, 1);
    const offset = (firstDay.getDay() + 6) % 7; // monday start
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
        activateRangeButton(null);
        calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
        calendarEl.querySelectorAll('.week-btn').forEach(b => b.classList.remove('week-btn--active'));
        document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start: startISO, end: endISO}}));
        resetBtn.classList.remove('hidden');
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
        cell.className = 'h-16 border-r-2 border-b-2 border-gray-200 flex flex-col items-center justify-between p-1 cal-day';
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
            activateRangeButton(null);
            selectRange(dateStr, dateStr);
            document.dispatchEvent(new CustomEvent('calendar:dateSelected', {detail: {date: dateStr}}));
            resetBtn.classList.remove('hidden');
          }
        });

        calendarEl.appendChild(cell);
      }
    }
    highlightSelection();
  }

  function activateRangeButton(btn) {
    rangeButtons.forEach(b => {
      b.classList.remove('btn--active');
      b.classList.add('btn--inactive');
    });
    if (btn) {
      btn.classList.remove('btn--inactive');
      btn.classList.add('btn--active');
    }
  }

  function selectRange(start, end) {
    selectedRange = {start, end};
  }

  function highlightSelection() {
    yearDisplay.textContent = currentYear;
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
    const diff = (day === 0 ? -6 : 1) - day;
    d.setDate(d.getDate() + diff);
    return formatISO(d);
  }

  function endOfWeek(date) {
    const start = new Date(date);
    const day = start.getDay();
    const diff = (day === 0 ? -6 : 1) - day + 6;
    start.setDate(start.getDate() + diff);
    return formatISO(start);
  }

  function formatISO(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
});
