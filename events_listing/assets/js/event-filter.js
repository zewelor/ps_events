// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', function() {
    const eventCards = document.querySelectorAll('.event-card');
    const filterButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
    filterButtons.forEach(btn => btn.addEventListener('click', handleFilterClick));

    function handleFilterClick(event) {
        const selectedCategory = event.target.dataset.filterCategory;

        // Update active button style
        document.querySelectorAll('#event-filter-controls .filter-btn').forEach(btn => {
            btn.classList.remove('filter-btn--active');
            btn.classList.add('filter-btn--inactive');
        });
        event.target.classList.remove('filter-btn--inactive');
        event.target.classList.add('filter-btn--active');

        // Filter event cards
        eventCards.forEach(card => {
            const cardCategory = card.dataset.category;
            if (selectedCategory === 'all' || cardCategory === selectedCategory) {
                card.style.display = 'flex';
            } else {
                card.style.display = 'none';
            }
        });
    }
});
