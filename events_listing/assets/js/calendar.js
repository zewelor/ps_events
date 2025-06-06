document.addEventListener('DOMContentLoaded', () => {
  const calendarEl = document.getElementById('calendar');
  const titleEl = document.getElementById('calendar-title');
  const resetBtn = document.getElementById('reset-date');
  const prevBtn = document.getElementById('prev-month');
  const nextBtn = document.getElementById('next-month');
  const yearSelect = document.getElementById('year-select');
  const todayBtn = document.getElementById('filter-today');
  const weekBtn = document.getElementById('filter-week');
  const monthBtn = document.getElementById('filter-month');
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

  populateYears(currentYear);
  buildCalendar(currentYear, currentMonth);

  prevBtn.addEventListener('click', () => {
    currentMonth--;
    if (currentMonth < 0) {
      currentMonth = 11;
      currentYear--;
    }
    yearSelect.value = currentYear;
    buildCalendar(currentYear, currentMonth);
  });

  nextBtn.addEventListener('click', () => {
    currentMonth++;
    if (currentMonth > 11) {
      currentMonth = 0;
      currentYear++;
    }
    yearSelect.value = currentYear;
    buildCalendar(currentYear, currentMonth);
  });

  yearSelect.addEventListener('change', () => {
    currentYear = parseInt(yearSelect.value, 10);
    buildCalendar(currentYear, currentMonth);
  });

  todayBtn.addEventListener('click', () => {
    const iso = today.toISOString().slice(0,10);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start: iso, end: iso}}));
    resetBtn.classList.remove('hidden');
  });

  weekBtn.addEventListener('click', () => {
    const start = startOfWeek(today);
    const end = endOfWeek(today);
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start, end}}));
    resetBtn.classList.remove('hidden');
  });

  monthBtn.addEventListener('click', () => {
    const start = formatISO(new Date(today.getFullYear(), today.getMonth(), 1));
    const end = formatISO(new Date(today.getFullYear(), today.getMonth() + 1, 0));
    document.dispatchEvent(new CustomEvent('calendar:rangeSelected', {detail: {start, end}}));
    resetBtn.classList.remove('hidden');
  });

  resetBtn.addEventListener('click', () => {
    document.dispatchEvent(new CustomEvent('calendar:clearDate'));
    clearSelection();
  });

  document.addEventListener('calendar:reset', clearSelection);

  function clearSelection() {
    calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
    resetBtn.classList.add('hidden');
  }

  function buildCalendar(year, month) {
    titleEl.textContent = new Date(year, month).toLocaleString('pt-PT', {month:'long', year:'numeric'});
    calendarEl.innerHTML = '';

    const daysOfWeek = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    for (const dayName of daysOfWeek) {
      const header = document.createElement('div');
      header.className = 'py-2 font-semibold border-b border-gray-200';
      header.textContent = dayName;
      calendarEl.appendChild(header);
    }

    const firstDay = new Date(year, month, 1);
    const offset = (firstDay.getDay() + 6) % 7; // monday start
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    for (let i = 0; i < offset; i++) {
      const empty = document.createElement('div');
      empty.className = 'h-16 border-r border-gray-200';
      calendarEl.appendChild(empty);
    }

    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(year, month, day);
      const dateStr = date.toISOString().slice(0,10);
      const cell = document.createElement('button');
      cell.className = 'h-16 border-r border-b border-gray-200 flex flex-col items-center justify-between p-1 cal-day';
      cell.dataset.date = dateStr;
      cell.innerHTML = `<span>${day}</span>`;

      const dots = document.createElement('div');
      dots.className = 'flex space-x-1 mb-1';
      events.filter(e => e.date === dateStr).forEach(e => {
        const dot = document.createElement('span');
        dot.className = 'w-3 h-3 rounded-full';
        dot.style.backgroundColor = e.color;
        dots.appendChild(dot);
      });
      cell.appendChild(dots);

      if (getWeekNumber(date) === getWeekNumber(today)) {
        cell.classList.add('bg-[var(--color-buttons)]', 'text-[var(--color-text-secondary)]');
      }

      cell.addEventListener('click', () => {
        if (cell.classList.contains('selected')) {
          cell.classList.remove('selected');
          document.dispatchEvent(new CustomEvent('calendar:clearDate'));
        } else {
          calendarEl.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
          cell.classList.add('selected');
          document.dispatchEvent(new CustomEvent('calendar:dateSelected', {detail: {date: dateStr}}));
          resetBtn.classList.remove('hidden');
        }
      });

      calendarEl.appendChild(cell);
    }
  }

  function getWeekNumber(d) {
    d = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    const dayNum = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - dayNum);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(),0,1));
    return Math.ceil((((d - yearStart) / 86400000) + 1)/7);
  }

  function populateYears(center) {
    for (let y = center - 1; y <= center + 1; y++) {
      const opt = document.createElement('option');
      opt.value = y;
      opt.textContent = y;
      yearSelect.appendChild(opt);
    }
    yearSelect.value = center;
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
    return d.toISOString().slice(0,10);
  }
});
