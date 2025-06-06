// Category and date filtering with simple calendar

document.addEventListener('DOMContentLoaded', function() {
  const eventCards = document.querySelectorAll('.event-card');
  const categoryButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
  let selectedCategory = 'all';
  let selectedDate = null;

  categoryButtons.forEach(btn => btn.addEventListener('click', e => {
    selectedCategory = e.target.dataset.filterCategory;
    updateCategoryButtons(e.target);
    filterEvents();
  }));

  function updateCategoryButtons(active) {
    categoryButtons.forEach(btn => {
      btn.classList.remove('filter-btn--active');
      btn.classList.add('filter-btn--inactive');
    });
    active.classList.remove('filter-btn--inactive');
    active.classList.add('filter-btn--active');
  }

  const clearDateBtn = document.getElementById('clear-date');
  clearDateBtn.textContent = 'Limpar data';

  const eventsByDate = {};
  eventCards.forEach(card => {
    const date = card.dataset.date;
    const color = card.dataset.color;
    const title = card.querySelector('h2 a').textContent.trim();
    if (!eventsByDate[date]) eventsByDate[date] = [];
    eventsByDate[date].push({title, color});
  });

  const monthEl = document.getElementById('calendar-month');
  const gridEl = document.getElementById('calendar-grid');
  const prevBtn = document.getElementById('prev-month');
  const nextBtn = document.getElementById('next-month');
  const todayBtn = document.getElementById('today-month');
  let current = new Date();
  current.setDate(1);

  function formatDate(y, m, d) {
    return y + '-' + String(m).padStart(2,'0') + '-' + String(d).padStart(2,'0');
  }

  function renderCalendar() {
    monthEl.textContent = current.toLocaleString('pt-PT', {month: 'long', year: 'numeric'});
    gridEl.innerHTML = '';

    const today = new Date();
    const todayStr = formatDate(today.getFullYear(), today.getMonth()+1, today.getDate());

    const firstDay = new Date(current.getFullYear(), current.getMonth(), 1).getDay();
    const daysInMonth = new Date(current.getFullYear(), current.getMonth()+1, 0).getDate();

    for (let i=0; i<firstDay; i++) {
      const empty = document.createElement('div');
      empty.className = 'border-b border-r h-16';
      gridEl.appendChild(empty);
    }

    for (let d=1; d<=daysInMonth; d++) {
      const dateStr = formatDate(current.getFullYear(), current.getMonth()+1, d);
      const cell = document.createElement('button');
      cell.dataset.date = dateStr;
      cell.className = 'h-20 p-1 text-left hover:bg-gray-100 relative';
      const number = document.createElement('span');
      number.textContent = d;
      number.className = 'text-xs font-semibold';
      if (dateStr === todayStr) {
        number.classList.add('text-blue-600');
      }
      cell.appendChild(number);

      if (eventsByDate[dateStr]) {
        eventsByDate[dateStr].forEach(ev => {
          const dot = document.createElement('span');
          dot.className = 'block w-2 h-2 rounded-full mt-1';
          dot.style.backgroundColor = ev.color;
          cell.appendChild(dot);
        });
      }

      cell.addEventListener('click', () => {
        selectedDate = dateStr;
        clearDateBtn.classList.remove('hidden');
        renderCalendar();
        filterEvents();
      });

      if (selectedDate === dateStr) {
        cell.classList.add('bg-blue-50');
      }

      gridEl.appendChild(cell);
    }
  }

  prevBtn.addEventListener('click', () => {
    current.setMonth(current.getMonth() - 1);
    renderCalendar();
  });
  nextBtn.addEventListener('click', () => {
    current.setMonth(current.getMonth() + 1);
    renderCalendar();
  });
  todayBtn.addEventListener('click', () => {
    current = new Date();
    current.setDate(1);
    selectedDate = null;
    clearDateBtn.classList.add('hidden');
    renderCalendar();
    filterEvents();
  });

  clearDateBtn.addEventListener('click', () => {
    selectedDate = null;
    clearDateBtn.classList.add('hidden');
    filterEvents();
  });

  function filterEvents() {
    eventCards.forEach(card => {
      const categoryMatch = selectedCategory === 'all' || card.dataset.category === selectedCategory;
      const dateMatch = !selectedDate || card.dataset.date === selectedDate;
      card.style.display = categoryMatch && dateMatch ? 'flex' : 'none';
    });
  }

  renderCalendar();
});
