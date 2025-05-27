# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Música" => {"color" => "#3f7182"},
      "Comida" => {"color" => "#c26e5e"},
      "Arte" => {"color" => "#7abdc5"},
      "Natureza" => {"color" => "#7b5a50"},
      "Saúde & Bem-Estar" => {"color" => "#75c8e2"},
      "Desporto" => {"color" => "#d0a670"},
      "Aprendizagem & Workshops" => {"color" => "#2f2d2f"},
      "Comunidade & Cultura" => {"color" => "#99aab8"}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end

    # Filter events to only include those that haven't ended yet (current and future events)
    # This handles timezone conversion for Portugal (+01:00) and sorts by start time
    def filter_current_and_future_events(events)
      return [] if events.nil? || events.empty?

      current_time = Time.now

      filtered_events = events.select do |event|
        # Get the end time string from the event
        end_time_string = event["End time"]
        next false if end_time_string.nil? || end_time_string.empty?

        # Add timezone offset for Portugal (+01:00)
        end_time_with_offset = "#{end_time_string} +01:00"

        # Parse the datetime and compare with current time
        event_end_time = Time.parse(end_time_with_offset)
        event_end_time > current_time
      rescue => e
        # If there's any error parsing the date, exclude the event
        Jekyll.logger.warn "Date parsing error for event '#{event["Name"]}': #{e.message}"
        false
      end

      # Sort by start time (chronological order)
      filtered_events.sort_by do |event|
        start_time_string = event["Start time"]
        start_time_with_offset = "#{start_time_string} +01:00"
        Time.parse(start_time_with_offset)
      rescue => e
        Jekyll.logger.warn "Start time parsing error for event '#{event["Name"]}': #{e.message}"
        Time.at(0) # Sort parsing errors to the beginning
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
