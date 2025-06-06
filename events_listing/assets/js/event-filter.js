// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', () => {
  const eventCards = document.querySelectorAll('.event-card');
  const filterButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
  const resetAllBtn = document.getElementById('reset-filters');
  const logoLink = document.getElementById('logo-link');
  let selectedCategory = 'all';
  let selectedRange = null; // {start, end}

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
      btn.classList.remove('filter-btn--active');
      btn.classList.add('filter-btn--inactive');
    });
    event.target.classList.remove('filter-btn--inactive');
    event.target.classList.add('filter-btn--active');
    filterEvents();
  }

  function filterEvents() {
    eventCards.forEach(card => {
      const cardCategory = card.dataset.category;
      const cardDate = card.dataset.date;
      const matchCategory = selectedCategory === 'all' || cardCategory === selectedCategory;
      const matchDate = !selectedRange || (cardDate >= selectedRange.start && cardDate <= selectedRange.end);
      card.style.display = matchCategory && matchDate ? 'flex' : 'none';
    });
  }

  function resetFilters() {
    selectedCategory = 'all';
    selectedRange = null;
    document.querySelectorAll('#event-filter-controls .filter-btn').forEach(btn => {
      if (btn.dataset.filterCategory === 'all') {
        btn.classList.add('filter-btn--active');
        btn.classList.remove('filter-btn--inactive');
      } else {
        btn.classList.remove('filter-btn--active');
        btn.classList.add('filter-btn--inactive');
      }
    });
    document.dispatchEvent(new CustomEvent('calendar:reset'));
    filterEvents();
  }
});
