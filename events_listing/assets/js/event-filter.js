// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', () => {
  const eventCards = document.querySelectorAll('.event-card');
  const filterButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
  const resetAllBtn = document.getElementById('reset-filters');
  const logoLink = document.getElementById('logo-link');
  let selectedCategory = 'all';
  let selectedRange = null; // {start, end}

  // store button labels for easy count updates
  filterButtons.forEach(btn => {
    const label = btn.dataset.label || btn.textContent.replace(/\s*\(.+\)$/, '');
    btn.dataset.label = label.trim();
  });

  updateCategoryCounts();

  filterButtons.forEach(btn => btn.addEventListener('click', handleCategoryClick));
  document.addEventListener('calendar:dateSelected', e => { selectedRange = {start: e.detail.date, end: e.detail.date}; filterEvents(); });
  document.addEventListener('calendar:rangeSelected', e => { selectedRange = e.detail; filterEvents(); });
  document.addEventListener('calendar:clearDate', () => { selectedRange = null; filterEvents(); });
  resetAllBtn.addEventListener('click', resetFilters);
  document.addEventListener('filters:reset', resetFilters);
  if (logoLink) logoLink.addEventListener('click', e => { e.preventDefault(); document.dispatchEvent(new CustomEvent('filters:reset')); });

  function handleCategoryClick(event) {
    selectedCategory = event.target.dataset.filterCategory;
    document.querySelectorAll('#event-filter-controls .filter-btn').forEach(btn => {
      btn.classList.remove('btn--active');
      btn.classList.add('btn--inactive');
    });
    event.target.classList.remove('btn--inactive');
    event.target.classList.add('btn--active');
    filterEvents();
  }

  function filterEvents() {
    updateCategoryCounts();
    eventCards.forEach(card => {
      const cardCategory = card.dataset.category;
      const cardDate = card.dataset.date;
      const matchCategory = selectedCategory === 'all' || cardCategory === selectedCategory;
      const matchDate = !selectedRange || (cardDate >= selectedRange.start && cardDate <= selectedRange.end);
      card.style.display = matchCategory && matchDate ? 'flex' : 'none';
    });
  }

  function updateCategoryCounts() {
    const counts = {};
    let total = 0;
    eventCards.forEach(card => {
      const date = card.dataset.date;
      const category = card.dataset.category;
      const matchDate = !selectedRange || (date >= selectedRange.start && date <= selectedRange.end);
      if (matchDate) {
        counts[category] = (counts[category] || 0) + 1;
        total++;
      }
    });

    filterButtons.forEach(btn => {
      const label = btn.dataset.label;
      const category = btn.dataset.filterCategory;
      const count = category === 'all' ? total : (counts[category] || 0);
      btn.textContent = `${label} (${count})`;
      if (category !== 'all') {
        btn.style.display = count ? '' : 'none';
      }
    });
  }

  function resetFilters() {
    selectedCategory = 'all';
    selectedRange = null;
    document.querySelectorAll('#event-filter-controls .filter-btn').forEach(btn => {
      if (btn.dataset.filterCategory === 'all') {
        btn.classList.add('btn--active');
        btn.classList.remove('btn--inactive');
      } else {
        btn.classList.remove('btn--active');
        btn.classList.add('btn--inactive');
      }
    });
    document.dispatchEvent(new CustomEvent('calendar:reset'));
    filterEvents();
  }
});
