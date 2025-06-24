// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', () => {
  const eventCards = document.querySelectorAll('.event-card');
  const categorySelect = document.getElementById('category-select');
  const categoryOptions = categorySelect ? categorySelect.querySelectorAll('option') : [];
  const clearAllBtn = document.getElementById('clear-all-filters');
  const logoLink = document.getElementById('logo-link');
  let selectedCategory = 'all';
  let selectedRange = null; // {start, end}

  // store option labels for easy count updates
  categoryOptions.forEach(opt => {
    const label = opt.dataset.label || opt.textContent.replace(/\s*\(.+\)$/, '');
    opt.dataset.label = label.trim();
  });

  updateCategoryCounts();
  updateClearButtonVisibility(); // Initialize button visibility

  if (categorySelect) categorySelect.addEventListener('change', handleCategoryChange);
  document.addEventListener('calendar:dateSelected', e => { selectedRange = {start: e.detail.date, end: e.detail.date}; filterEvents(); });
  document.addEventListener('calendar:rangeSelected', e => { selectedRange = e.detail; filterEvents(); });
  document.addEventListener('calendar:clearDate', () => { selectedRange = null; filterEvents(); });
  if (clearAllBtn) clearAllBtn.addEventListener('click', resetFilters);
  document.addEventListener('filters:reset', resetFilters);
  if (logoLink) logoLink.addEventListener('click', e => { e.preventDefault(); document.dispatchEvent(new CustomEvent('filters:reset')); });

  function handleCategoryChange(event) {
    selectedCategory = event.target.value;
    filterEvents();
  }

  function filterEvents() {
    updateCategoryCounts();
    updateClearButtonVisibility();
    const rangeStart = selectedRange ? new Date(selectedRange.start) : null;
    const rangeEnd = selectedRange ? new Date(selectedRange.end) : null;
    eventCards.forEach(card => {
      const cardCategory = card.dataset.category;
      const cardStart = new Date(card.dataset.startDate || card.dataset.date);
      const cardEnd = new Date(card.dataset.endDate || cardStart);
      const matchCategory = selectedCategory === 'all' || cardCategory === selectedCategory;
      const matchDate = !selectedRange || (cardEnd >= rangeStart && cardStart <= rangeEnd);
      card.style.display = matchCategory && matchDate ? 'flex' : 'none';
    });
  }

  function updateClearButtonVisibility() {
    if (!clearAllBtn) return; // Safety check
    const hasFilters = selectedCategory !== 'all' || selectedRange !== null;
    if (hasFilters) {
      clearAllBtn.classList.remove('hidden');
    } else {
      clearAllBtn.classList.add('hidden');
    }
  }

  function updateCategoryCounts() {
    const counts = {};
    let total = 0;
    const rangeStart = selectedRange ? new Date(selectedRange.start) : null;
    const rangeEnd = selectedRange ? new Date(selectedRange.end) : null;
    eventCards.forEach(card => {
      const start = new Date(card.dataset.startDate || card.dataset.date);
      const end = new Date(card.dataset.endDate || start);
      const category = card.dataset.category;
      const matchDate = !selectedRange || (end >= rangeStart && start <= rangeEnd);
      if (matchDate) {
        counts[category] = (counts[category] || 0) + 1;
        total++;
      }
    });

    categoryOptions.forEach(opt => {
      const label = opt.dataset.label;
      const value = opt.value;
      const count = value === 'all' ? total : (counts[value] || 0);
      opt.textContent = `${label} (${count})`;
      if (value !== 'all') {
        opt.hidden = count === 0;
      }
    });
  }

  function resetFilters() {
    selectedCategory = 'all';
    selectedRange = null;
    if (categorySelect) categorySelect.value = 'all';
    document.dispatchEvent(new CustomEvent('calendar:reset'));
    filterEvents();
  }
});
