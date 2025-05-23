// Calendar functionality
// Handles calendar view, event display, and mobile toggle

document.addEventListener('DOMContentLoaded', function() {
    // Get event data from the page
    const eventCards = document.querySelectorAll('.event-card');
    const events = Array.from(eventCards).map(card => {
        const dateStr = card.dataset.date; // Format: "17/05/2025 17:00"
        const category = card.dataset.category;
        const title = card.querySelector('h2 a').textContent.trim();

        // Find location from the second flex container with SVG
        const locationElements = card.querySelectorAll('.flex.items-center.text-sm.text-gray-500');
        const location = locationElements.length > 1 ?
            locationElements[1].querySelector('span').textContent.trim() :
            'Location TBD';

        // Parse date from DD/MM/YYYY HH:mm format
        const [datePart, timePart] = dateStr.split(' ');
        const [day, month, year] = datePart.split('/');
        const date = new Date(year, month - 1, day);

        return {
            title,
            date,
            dateStr,
            category,
            location,
            element: card
        };
    });

    // Category colors mapping
    const categoryColors = {
        'Music': '#f59e0b',
        'Food': '#ef4444',
        'Art': '#8b5cf6',
        'Nature': '#10b981',
        'Health & Wellness': '#06b6d4',
        'Sports': '#f97316',
        'Learning & Workshops': '#3b82f6',
        'Community & Culture': '#ec4899',
        'Event': '#6b7280'
    };    // Calendar state
    let currentDate = new Date();
    let currentMonth = currentDate.getMonth();
    let currentYear = currentDate.getFullYear();
    let activeDateFilter = null; // Track active date filter
    
    // Make activeDateFilter accessible globally for event-filter.js
    window.activeDateFilter = activeDateFilter;

    // DOM elements
    const currentMonthSpan = document.getElementById('current-month');
    const prevMonthBtn = document.getElementById('prev-month');
    const nextMonthBtn = document.getElementById('next-month');
    const calendarDays = document.getElementById('calendar-days');

    // Initialize calendar
    updateCalendarDisplay();
    renderCalendar();

    // Event listeners
    prevMonthBtn?.addEventListener('click', () => changeMonth(-1));
    nextMonthBtn?.addEventListener('click', () => changeMonth(1));    function changeMonth(direction) {
        currentMonth += direction;

        if (currentMonth > 11) {
            currentMonth = 0;
            currentYear++;
        } else if (currentMonth < 0) {
            currentMonth = 11;
            currentYear--;
        }
        
        updateCalendarDisplay();
        renderCalendar();
    }

    function updateCalendarDisplay() {
        const monthNames = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
        ];

        currentMonthSpan.textContent = `${monthNames[currentMonth]} ${currentYear}`;
    }    function renderCalendar() {
        const firstDay = new Date(currentYear, currentMonth, 1);
        const lastDay = new Date(currentYear, currentMonth + 1, 0);
        const startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - firstDay.getDay());

        const today = new Date();
        calendarDays.innerHTML = '';

        // Generate 42 days (6 weeks)
        for (let i = 0; i < 42; i++) {
            const cellDate = new Date(startDate);
            cellDate.setDate(startDate.getDate() + i);

            const dayDiv = document.createElement('div');
            dayDiv.className = 'calendar-day';

            // Add day classes
            const isToday = cellDate.toDateString() === today.toDateString();
            const isCurrentMonth = cellDate.getMonth() === currentMonth;
            const dayEvents = getEventsForDate(cellDate);
            const isActiveDate = activeDateFilter && cellDate.toDateString() === activeDateFilter.toDateString();

            if (isToday) dayDiv.classList.add('calendar-day--today');
            if (!isCurrentMonth) dayDiv.classList.add('calendar-day--other-month');
            if (dayEvents.length > 0) dayDiv.classList.add('calendar-day--has-events');
            if (isActiveDate) dayDiv.classList.add('calendar-day--active');

            // Day number
            const dayNumber = document.createElement('div');
            dayNumber.className = 'calendar-day-number';
            dayNumber.textContent = cellDate.getDate();
            dayDiv.appendChild(dayNumber);

            // Event dots
            const eventDotsContainer = document.createElement('div');
            eventDotsContainer.className = 'flex flex-wrap';

            dayEvents.slice(0, 3).forEach(event => {
                const dot = document.createElement('div');
                dot.className = 'calendar-event-dot';
                dot.style.backgroundColor = categoryColors[event.category] || categoryColors['Event'];
                dot.title = `${event.title} - ${event.category}`;
                eventDotsContainer.appendChild(dot);
            });

            if (dayEvents.length > 3) {
                const moreDot = document.createElement('div');
                moreDot.className = 'text-xs text-gray-500 ml-1';
                moreDot.textContent = `+${dayEvents.length - 3}`;
                eventDotsContainer.appendChild(moreDot);
            }

            dayDiv.appendChild(eventDotsContainer);

            // Click handler for days with events
            if (dayEvents.length > 0) {
                dayDiv.addEventListener('click', () => {
                    showDayEvents(cellDate, dayEvents);
                });
            }

            calendarDays.appendChild(dayDiv);
        }
    }

    function renderMobileEvents() {
        let monthEvents = events.filter(event =>
            event.date.getMonth() === currentMonth &&
            event.date.getFullYear() === currentYear
        ).sort((a, b) => a.date - b.date);

        mobileEventsList.innerHTML = '';

        // If we have a date filter, only show events for that date
        if (activeDateFilter) {
            monthEvents = monthEvents.filter(event =>
                event.date.toDateString() === activeDateFilter.toDateString()
            );

            // Add a header for the filtered date
            const dateHeader = document.createElement('div');
            dateHeader.className = 'font-medium text-emerald-800 mb-3';
            dateHeader.textContent = `Events on ${activeDateFilter.toLocaleDateString('en-GB', {
                weekday: 'long',
                day: 'numeric',
                month: 'long'
            })}`;
            mobileEventsList.appendChild(dateHeader);
        }

        if (monthEvents.length === 0) {
            const noEvents = document.createElement('div');
            noEvents.className = 'text-gray-500 text-center py-4';
            noEvents.textContent = activeDateFilter ? 'No events on this date' : 'No events this month';
            mobileEventsList.appendChild(noEvents);
            return;
        }

        monthEvents.forEach(event => {
            const eventDiv = document.createElement('div');
            eventDiv.className = 'mobile-event-item';
            eventDiv.style.borderLeftColor = categoryColors[event.category] || categoryColors['Event'];

            const dateDiv = document.createElement('div');
            dateDiv.className = 'mobile-event-date';
            dateDiv.textContent = event.date.toLocaleDateString('en-GB', {
                weekday: 'short',
                day: 'numeric',
                month: 'short'
            });

            const titleDiv = document.createElement('div');
            titleDiv.className = 'mobile-event-title';
            titleDiv.textContent = event.title;

            const timeDiv = document.createElement('div');
            timeDiv.className = 'mobile-event-time';
            timeDiv.textContent = `${event.location} • ${event.category}`;

            eventDiv.appendChild(dateDiv);
            eventDiv.appendChild(titleDiv);
            eventDiv.appendChild(timeDiv);

            // Click to scroll to event in listing
            eventDiv.addEventListener('click', () => {
                event.element.scrollIntoView({ behavior: 'smooth', block: 'center' });
                event.element.style.animation = 'pulse 2s ease-in-out';
                setTimeout(() => {
                    event.element.style.animation = '';
                }, 2000);
            });

            mobileEventsList.appendChild(eventDiv);
        });
    }

    function getEventsForDate(date) {
        return events.filter(event =>
            event.date.toDateString() === date.toDateString()
        );
    }

    function showDayEvents(date, dayEvents) {
        // Filter event cards to show only events from the selected date
        const formattedDate = date.toLocaleDateString('en-GB', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric'
        }).replace(/\//g, '/');

        const activeCategory = document.querySelector('#event-filter-controls .filter-btn--active')?.dataset.filterCategory;

        // If clicking on the already active date, clear the filter
        if (activeDateFilter && date.toDateString() === activeDateFilter.toDateString()) {
            clearDateFilter();
            return;
        }

        // Set the active date filter
        activeDateFilter = date;
        window.activeDateFilter = activeDateFilter; // Update global reference

        // Re-render calendar to update active date styling
        renderCalendar();
        renderMobileEvents();

        // Apply filter - use the shared function from event-filter.js if available
        if (window.applyEventFilters) {
            window.applyEventFilters(activeCategory || 'all');
        } else {
            // Fallback if the other script hasn't loaded
            const eventCards = document.querySelectorAll('.event-card');
            eventCards.forEach(card => {
                const cardDate = card.dataset.date.split(' ')[0]; // Get just the date part
                const cardCategory = card.dataset.category;

                const dateMatches = cardDate === formattedDate;
                const categoryMatches = activeCategory === 'all' || cardCategory === activeCategory;

                // Show card only if it matches both date and category filters
                if (dateMatches && categoryMatches) {
                    card.style.display = 'flex';
                } else {
                    card.style.display = 'none';
                }
            });
        }

        // Scroll to event list
        document.getElementById('event-list').scrollIntoView({ behavior: 'smooth' });
    }

    function clearDateFilter() {
        activeDateFilter = null;
        window.activeDateFilter = null; // Update global reference

        // Remove date filter indicator
        const indicator = document.getElementById('date-filter-indicator');
        if (indicator) {
            indicator.remove();
        }

        // Re-render calendar to update active date styling
        renderCalendar();

        // Reapply only category filter using the shared function
        const activeCategory = document.querySelector('#event-filter-controls .filter-btn--active')?.dataset.filterCategory;

        if (window.applyEventFilters) {
            window.applyEventFilters(activeCategory || 'all');
        } else {
            // Fallback if the other script hasn't loaded
            const eventCards = document.querySelectorAll('.event-card');
            eventCards.forEach(card => {
                const cardCategory = card.dataset.category;

                if (activeCategory === 'all' || cardCategory === activeCategory) {
                    card.style.display = 'flex';
                } else {
                    card.style.display = 'none';
                }
            });
        }
    }

    // Auto-advance to current month if we're viewing past months
    function autoAdvanceToCurrentMonth() {
        const now = new Date();
        if (currentYear < now.getFullYear() ||
            (currentYear === now.getFullYear() && currentMonth < now.getMonth())) {
            currentMonth = now.getMonth();
            currentYear = now.getFullYear();
            updateCalendarDisplay();
            renderCalendar();
            renderMobileEvents();
        }
    }

    // Initialize with current month
    autoAdvanceToCurrentMonth();
});
