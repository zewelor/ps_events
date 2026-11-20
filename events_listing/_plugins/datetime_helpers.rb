require "date"

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

      start_date = event["start_date"]
      start_time = event["start_time"]
      end_date = event["end_date"]
      end_time = event["end_time"]

      # Check if start_date is nil or empty/whitespace-only
      raise NotImplementedError if start_date.nil? || start_date.to_s.strip.empty?

      # Lambda to check if a value is present (not nil and not empty)
      present = ->(value) { !value.nil? && !value.to_s.strip.empty? }

      start_date_formatted = start_date.to_s.strip
      start_time_formatted = start_time.to_s.strip if present.call(start_time)
      end_date_formatted = end_date.to_s.strip if present.call(end_date)
      end_time_formatted = end_time.to_s.strip if present.call(end_time)

      start = [start_date_formatted, start_time_formatted].compact.join(" ")
      if end_date_formatted && (end_date_formatted != start_date_formatted || (!start_time_formatted && !end_time_formatted))
        return "#{start} - #{[end_date_formatted, end_time_formatted].compact.join(" ")}"
      end
      return start unless end_time_formatted
      return "#{start} (until #{end_time_formatted})" unless start_time_formatted

      "#{start} - #{end_time_formatted}"
    end

    # Convert date (DD/MM/YYYY) and optional time (HH:MM) to ISO 8601 string
    def to_iso_datetime(date_str, time_str = nil)
      return nil if date_str.nil? || date_str.to_s.strip.empty?

      begin
        parsed_date = Date.strptime(date_str.to_s.strip, "%d/%m/%Y")
        if time_str.nil? || time_str.to_s.strip.empty?
          parsed_date.strftime("%Y-%m-%d")
        else
          time_part = time_str.to_s.strip
          "#{parsed_date.strftime("%Y-%m-%d")}T#{time_part}"
        end
      rescue ArgumentError
        nil
      end
    end

    # Derive a valid schema.org endDate from the event's effective end date.
    def to_iso_end_datetime(start_date, start_time, end_date, end_time)
      end_time_present = !end_time.nil? && !end_time.to_s.strip.empty?
      effective_end_date = if !end_date.nil? && !end_date.to_s.strip.empty?
        end_date
      elsif end_time_present
        start_date
      end
      return nil unless effective_end_date

      return to_iso_datetime(effective_end_date, end_time) if end_time_present

      start_iso = to_iso_datetime(start_date, start_time)
      end_iso = to_iso_datetime(effective_end_date)
      return nil if start_iso&.include?("T") && end_iso == to_iso_datetime(start_date)

      end_iso
    end
  end
end

Liquid::Template.register_filter(Jekyll::DatetimeHelpers)
