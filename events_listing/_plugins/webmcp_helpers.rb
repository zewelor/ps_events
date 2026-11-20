require "date"
require "json"

module Jekyll
  module WebmcpHelpers
    PUBLIC_TEXT_FIELDS = %w[name category location description organizer price image].freeze
    TIME_FIELDS = %w[start_time end_time].freeze
    LINK_FIELDS = %w[link_1 link_2 link_3 link_4].freeze

    def webmcp_events_json(events)
      records = events.map do |event|
        record = event.slice(*PUBLIC_TEXT_FIELDS)
        record["id"] = event.fetch("page_slug")
        record["url"] = event.fetch("canonical_url")
        record["start_date"] = Date.strptime(event.fetch("start_date"), "%d/%m/%Y").iso8601
        end_date = event["end_date"].to_s.strip
        record["end_date"] = end_date.empty? ? record["start_date"] : Date.strptime(end_date, "%d/%m/%Y").iso8601
        TIME_FIELDS.each do |field|
          time = event[field].to_s.strip
          record[field] = time.empty? ? nil : time
        end
        record["links"] = LINK_FIELDS.filter_map do |field|
          link = event[field].to_s.strip
          link unless link.empty?
        end
        record
      end

      # HTML parses script endings even inside a JSON string.
      JSON.generate(records).gsub("<", '\\u003c')
    end
  end
end

Liquid::Template.register_filter(Jekyll::WebmcpHelpers)
