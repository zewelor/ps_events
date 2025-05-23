// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', function() {
    const eventCards = document.querySelectorAll('.event-card');
    const filterButtons = document.querySelectorAll('#event-filter-controls .filter-btn');
    filterButtons.forEach(btn => btn.addEventListener('click', handleFilterClick));
    
    // Expose filter function globally to be used by calendar.js
    window.applyEventFilters = applyEventFilters;

    function handleFilterClick(event) {
        const selectedCategory = event.target.dataset.filterCategory;

        // Update active button style
        document.querySelectorAll('#event-filter-controls .filter-btn').forEach(btn => {
            btn.classList.remove('filter-btn--active');
            btn.classList.add('filter-btn--inactive');
        });
        event.target.classList.remove('filter-btn--inactive');
        event.target.classList.add('filter-btn--active');

        // Apply filters
        applyEventFilters(selectedCategory);
    }
    
    function applyEventFilters(selectedCategory) {
        // Get current date filter if any
        const dateFilterIndicator = document.getElementById('date-filter-indicator');
        const hasDateFilter = !!dateFilterIndicator;
        
        // Apply both category and date filters if applicable
        eventCards.forEach(card => {
            const cardCategory = card.dataset.category;
            const categoryMatches = selectedCategory === 'all' || cardCategory === selectedCategory;
            
            if (hasDateFilter && window.activeDateFilter) {
                // If date filter is active, apply both filters
                const cardDateStr = card.dataset.date.split(' ')[0]; // Get date part
                const cardDate = parseDateString(cardDateStr);
                const dateMatches = cardDate.toDateString() === window.activeDateFilter.toDateString();
                
                card.style.display = (categoryMatches && dateMatches) ? 'flex' : 'none';
            } else {
                // Only apply category filter
                card.style.display = categoryMatches ? 'flex' : 'none';
            }
        });
    }
    
    // Helper function to parse date string in format DD/MM/YYYY
    function parseDateString(dateStr) {
        const [day, month, year] = dateStr.split('/');
        return new Date(year, month - 1, day);
    }
});
