module Jekyll
  module CalendarHelpers
    require 'time'
    require 'uri'
    require 'icalendar'

    # Generate a Google Calendar URL for an event hash
    def google_calendar_url(event, timezone = 'Europe/Lisbon')
      start_time = parse_time(event['Start date'], event['Start time'])
      end_time = parse_time(event['End date'], event['End time'])
      return '' unless start_time && end_time

      params = {
        action: 'TEMPLATE',
        text: event['Name'].to_s.strip,
        dates: "#{format_google_time(start_time)}/#{format_google_time(end_time)}",
        details: event['Description'].to_s.strip,
        location: event['Location'].to_s.strip,
        ctz: timezone
      }
      "https://www.google.com/calendar/render?" + URI.encode_www_form(params)
    end

    # Generate an ICS string for an event hash
    def event_to_ics(event)
      start_time = parse_time(event['Start date'], event['Start time'])
      end_time = parse_time(event['End date'], event['End time'])
      cal = Icalendar::Calendar.new
      cal.append_custom_property('X-WR-CALNAME', 'PXOPulse Event')
      ev = Icalendar::Event.new
      ev.dtstart = start_time if start_time
      ev.dtend = end_time if end_time
      ev.summary = event['Name'].to_s.strip
      ev.location = event['Location'].to_s.strip
      ev.description = event['Description'].to_s.strip
      cal.add_event(ev)
      cal.publish
      cal.to_ical
    end

    private

    def parse_time(date_str, time_str)
      return nil if date_str.nil? || date_str.to_s.strip.empty?
      str = date_str.to_s
      str += " #{time_str}" if time_str && !time_str.to_s.strip.empty?
      Time.parse(str)
    rescue StandardError
      nil
    end

    def format_google_time(t)
      t.utc.strftime('%Y%m%dT%H%M%SZ')
    end
  end
end

Liquid::Template.register_filter(Jekyll::CalendarHelpers)
