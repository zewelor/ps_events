# frozen_string_literal: true

module Jekyll
  module CalendarHelpers
    require "time"
    require "uri"
    require "icalendar"

    # Generate a Google Calendar URL for an event hash
    def google_calendar_url(event, timezone = "Europe/Lisbon")
      start_time = parse_time(event["start_date"], event["start_time"])
      end_time = parse_time(event["end_date"], event["end_time"])

      # Handle full-day events (when both times are empty)
      is_full_day = is_full_day_event?(event)

      if is_full_day
        start_date = parse_date_only(event["start_date"])
        end_date = parse_date_only(event["end_date"]) || start_date
        return "" unless start_date

        # For full-day events, use date format YYYYMMDD
        dates_param = "#{format_google_date(start_date)}/#{format_google_date(end_date + 1)}"
      else
        return "" unless start_time

        # If no end time, default to 23:59 on the same day as start time
        end_time ||= default_end_time(start_time)

        dates_param = "#{format_google_time(start_time)}/#{format_google_time(end_time)}"
      end

      params = {
        action: "TEMPLATE",
        text: event["_name"].to_s.strip,
        dates: dates_param,
        details: event["description"].to_s.strip,
        location: event["location"].to_s.strip,
        ctz: timezone
      }
      "https://www.google.com/calendar/render?" + URI.encode_www_form(params)
    end

    # Generate an ICS string for an event hash
    def event_to_ics(event)
      start_time = parse_time(event["start_date"], event["start_time"])
      end_time = parse_time(event["end_date"], event["end_time"])

      # Handle full-day events (when both times are empty)
      is_full_day = is_full_day_event?(event)

      cal = Icalendar::Calendar.new
      cal.append_custom_property("X-WR-CALNAME", "PXOPulse Event")
      ev = Icalendar::Event.new

      if is_full_day
        start_date = parse_date_only(event["start_date"])
        end_date = parse_date_only(event["end_date"]) || start_date
        if start_date
          ev.dtstart = Icalendar::Values::Date.new(start_date)
          ev.dtend = Icalendar::Values::Date.new(end_date + 1) if end_date
        end
      elsif start_time
        ev.dtstart = start_time
        # If no end time, default to 23:59 on the same day as start time
        end_time ||= default_end_time(start_time)
        ev.dtend = end_time
      end

      ev.summary = event["_name"].to_s.strip
      ev.location = event["location"].to_s.strip
      ev.description = event["description"].to_s.strip
      cal.add_event(ev)
      cal.publish
      cal.to_ical
    end

    private

    def is_full_day_event?(event)
      start_time = event["start_time"]
      end_time = event["end_time"]
      (start_time.nil? || start_time.to_s.strip.empty?) &&
        (end_time.nil? || end_time.to_s.strip.empty?)
    end

    def parse_date_only(date_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?
      Date.parse(date_str.to_s)
    rescue
      nil
    end

    def parse_time(date_str, time_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?
      return nil if time_str.nil? || time_str.to_s.strip.empty?

      str = date_str.to_s + " #{time_str}"
      # Parse time and treat as local Lisbon time (no timezone conversion)
      Time.parse(str)
    rescue
      nil
    end

    def format_google_time(t)
      # Format time in the original timezone instead of converting to UTC
      t.strftime("%Y%m%dT%H%M%S")
    end

    def format_google_date(d)
      d.strftime("%Y%m%d")
    end

    def default_end_time(start_time)
      # Set end time to 23:59 on the same day as start time
      Time.new(start_time.year, start_time.month, start_time.day, 23, 59, 0)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CalendarHelpers)
