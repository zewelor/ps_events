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

    def filter_current_and_future_events(events)
      return [] if events.nil? || events.empty?

      current_date = Date.today

      filtered_events = events.select do |event|
        end_date_string = event.fetch("End date")

        if end_date_string && !end_date_string.empty?
          # Use End Date field for date comparison
          begin
            event_end_date = Date.parse(end_date_string)
            event_end_date >= current_date
          rescue => e
            Jekyll.logger.warn "End date parsing error for event '#{event["Name"]}': #{e.message}"
            false
          end
        end
      end

      # Sort by start time (chronological order)
      filtered_events.sort_by do |event|
        start_time_string = event["Start date"]
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
