// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', () => {
  const eventCards = document.querySelectorAll('.event-card');
  const filterButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
  const resetAllBtn = document.getElementById('reset-filters');
  let selectedCategory = 'all';
  let selectedDate = null;

  filterButtons.forEach(btn => btn.addEventListener('click', handleCategoryClick));
  document.addEventListener('calendar:dateSelected', e => { selectedDate = e.detail.date; filterEvents(); });
  document.addEventListener('calendar:clearDate', () => { selectedDate = null; filterEvents(); });
  resetAllBtn.addEventListener('click', resetFilters);

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
      const matchDate = !selectedDate || cardDate === selectedDate;
      card.style.display = matchCategory && matchDate ? 'flex' : 'none';
    });
  }

  function resetFilters() {
    selectedCategory = 'all';
    selectedDate = null;
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
