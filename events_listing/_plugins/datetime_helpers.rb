# Helper filters for datetime formatting in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module DatetimeHelpers
    # Format event date and time with different output styles
    # Supports various formats for displaying event timing information
    #
    # Handles multiple scenarios:
    # - Date only
    # - Date with start time only
    # - Date ranges
    # - Same day with time range
    # - Multi-day events with times
    # - "Until" format for end time only
    #
    # Parameters:
    #   event: Event object with Start date, Start time, End date, End time fields
    def format_event_datetime(event)
      return "" if event.nil?

      start_date = event["Start date"]
      start_time = event["Start time"]
      end_date = event["End date"]
      end_time = event["End time"]

      raise NotImplementedError if start_date.nil?

      # Lambda to check if a value is present (not nil and not empty)
      present = ->(value) { !value.nil? && !value.to_s.strip.empty? }

      # Lambda to format time with :00 suffix if it doesn't already have seconds
      format_time_with_seconds = ->(time) do
        return "" unless present.call(time)
        time_str = time.to_s.strip
        # Add :00 if time doesn't already contain seconds
        (time_str.include?(":") && !time_str.match(/:\d{2}$/)) ? "#{time_str}:00" : time_str
      end

      start_date_formatted = start_date.to_s.strip
      end_date_formatted = end_date.to_s.strip

      # Case 1: Only start date (no times, no end date)
      if !present.call(start_time) && !present.call(end_date) && !present.call(end_time)
        return start_date_formatted
      end

      # Case 2: Start date + start time only (no end date, no end time)
      if present.call(start_time) && !present.call(end_date) && !present.call(end_time)
        return "#{start_date_formatted} #{format_time_with_seconds.call(start_time)}"
      end

      # Case 3: Start date + end date only (no times)
      if !present.call(start_time) && present.call(end_date) && !present.call(end_time)
        return "#{start_date_formatted} - #{end_date_formatted}"
      end

      # Case 4: Start date + start time + end date only (no end time)
      if present.call(start_time) && present.call(end_date) && !present.call(end_time)
        return "#{start_date_formatted} #{format_time_with_seconds.call(start_time)}"
      end

      # Case 5: Start date + end time only (no start time, no end date)
      # This creates the "until" format
      if !present.call(start_time) && !present.call(end_date) && present.call(end_time)
        return "#{start_date_formatted} (until #{end_time})"
      end

      # Case 6: Start date + same end date + end time only (no start time)
      # This also creates the "until" format
      if !present.call(start_time) && present.call(end_date) && present.call(end_time) && start_date == end_date
        return "#{start_date_formatted} (until #{end_time})"
      end

      # Case 7: Start date + different end date + end time (no start time)
      if !present.call(start_time) && present.call(end_date) && present.call(end_time) && start_date != end_date
        return "#{start_date_formatted} - #{end_date_formatted} #{end_time}"
      end

      # Case 8: Same day with start and end times
      if present.call(start_time) && present.call(end_time) && (!present.call(end_date) || start_date == end_date)
        return "#{start_date_formatted} #{start_time} - #{end_time}"
      end

      # Case 9: Multi-day event with start and end times
      if present.call(start_time) && present.call(end_time) && present.call(end_date) && start_date != end_date
        return "#{start_date_formatted} #{start_time} - #{end_date_formatted} #{end_time}"
      end

      # Fallback case - should not reach here with valid data
      start_date_formatted
    end
  end
end

Liquid::Template.register_filter(Jekyll::DatetimeHelpers)
