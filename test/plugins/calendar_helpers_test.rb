# frozen_string_literal: true

require "minitest/autorun"

# Mock Liquid to avoid dependency issues in tests
module Liquid
  class Template
    def self.register_filter(filter_module)
    end
  end
end

require_relative "../../events_listing/_plugins/calendar_helpers"

class TestCalendarHelpers < Minitest::Test
  include Jekyll::CalendarHelpers

  def setup
    @event = {
      "Name" => "Test Event",
      "Start date" => "2025-12-01",
      "Start time" => "10:00",
      "End date" => "2025-12-01",
      "End time" => "12:00",
      "Description" => "Desc",
      "Location" => "Loc"
    }
  end

  def test_google_calendar_url_contains_event_name
    url = google_calendar_url(@event)
    assert url.start_with?("https://www.google.com/calendar/render?")
    assert_includes url, "Test+Event"
  end

  def test_event_to_ics_contains_summary
    ics = event_to_ics(@event)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Test Event"
  end
end
