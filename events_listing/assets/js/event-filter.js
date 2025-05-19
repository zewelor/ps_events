// Event filtering functionality
// Moved from inline script in index.html

document.addEventListener('DOMContentLoaded', function() {
    const eventCards = document.querySelectorAll('.event-card');
    const filterControlsContainer = document.getElementById('event-filter-controls');
    const noResultsMessage = document.getElementById('no-results-message');
    const categories = new Set();
    const categoryCounts = {};

    eventCards.forEach(card => {
        const category = card.dataset.category;
        if (category) { // Ensure category exists and is not empty
            categories.add(category);
            categoryCounts[category] = (categoryCounts[category] || 0) + 1;
        }
    });

    // Tailwind classes for buttons
    const buttonBaseClasses = ['filter-btn-hook', 'px-4', 'py-2', 'mr-2', 'mb-2', 'rounded-md', 'text-sm', 'font-medium', 'transition', 'duration-150', 'ease-in-out'];
    const inactiveButtonClasses = ['text-gray-700', 'bg-white', 'hover:bg-gray-50'];
    const activeButtonClasses = ['text-white', 'bg-red-400', 'hover:bg-red-500'];

    if (categories.size > 0 && filterControlsContainer) {
        // Create "All" button
        const totalEvents = eventCards.length;
        const allButton = document.createElement('button');
        allButton.textContent = `All Categories (${totalEvents})`;
        allButton.classList.add(...buttonBaseClasses, ...activeButtonClasses); // "All" is active by default
        allButton.dataset.filterCategory = 'all';
        allButton.addEventListener('click', handleFilterClick);
        filterControlsContainer.appendChild(allButton);

        // Create buttons for each category, sorted alphabetically
        Array.from(categories).sort().forEach(category => {
            const button = document.createElement('button');
            const count = categoryCounts[category] || 0;
            button.textContent = `${category} (${count})`;
            button.classList.add(...buttonBaseClasses, ...inactiveButtonClasses);
            button.dataset.filterCategory = category;
            button.addEventListener('click', handleFilterClick);
            filterControlsContainer.appendChild(button);
        });
    } else if (filterControlsContainer && eventCards.length > 0) {
        // This case might occur if events exist but have no categories.
        // Or if categories set remains empty for some reason.
        // You could add a message here if desired.
        // filterControlsContainer.innerHTML = '<p class="text-sm text-gray-500">No categories available for filtering.</p>';
    }

    function handleFilterClick(event) {
        const selectedCategory = event.target.dataset.filterCategory;
        let visibleCount = 0;

        // Update active button style
        document.querySelectorAll('#event-filter-controls .filter-btn-hook').forEach(btn => {
            btn.classList.remove(...activeButtonClasses);
            btn.classList.add(...inactiveButtonClasses);
        });
        event.target.classList.remove(...inactiveButtonClasses);
        event.target.classList.add(...activeButtonClasses);

        eventCards.forEach(card => {
            const cardCategory = card.dataset.category;
            if (selectedCategory === 'all' || (cardCategory && cardCategory === selectedCategory)) {
                card.style.display = 'flex'; // Event cards use flex display
                visibleCount++;
            } else {
                card.style.display = 'none';
            }
        });

        if (noResultsMessage) {
            if (visibleCount === 0) {
                noResultsMessage.style.display = 'block';
            } else {
                noResultsMessage.style.display = 'none';
            }
        }
    }
});
