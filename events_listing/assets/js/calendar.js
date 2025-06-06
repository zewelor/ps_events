document.addEventListener('DOMContentLoaded', () => {
  const calendarEl = document.getElementById('calendar');
  const titleEl = document.getElementById('calendar-title');
  const resetBtn = document.getElementById('reset-date');
  if (!calendarEl) return;

  const eventCards = document.querySelectorAll('.event-card');
  const events = Array.from(eventCards).map(card => ({
    date: card.dataset.date,
    color: card.dataset.categoryColor,
    category: card.dataset.category
  }));

  const today = new Date();
  buildCalendar(today.getFullYear(), today.getMonth());

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
    const currentWeek = getWeekNumber(today) === getWeekNumber(firstDay) ? getWeekNumber(today) : null;

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
        cell.classList.add('bg-black', 'text-white');
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
});
