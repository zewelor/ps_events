# frozen_string_literal: true

require "minitest/autorun"

require_relative "plugins_helpers"
require_relative "../../events_listing/_plugins/calendar_helpers"

class TestCalendarHelpers < Minitest::Test
  include Jekyll::CalendarHelpers

  def setup
    @event = {
      "_name" => "Test Event",
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "01/12/2025",
      "end_time" => "12:00",
      "description" => "Desc",
      "location" => "Loc"
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

  # Full-day event tests
  def test_is_full_day_event_with_no_times
    full_day_event = {
      "_name" => "Full Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "01/12/2025",
      "end_time" => "",
      "description" => "All day event",
      "location" => "location"
    }

    assert send(:is_full_day_event?, full_day_event), "Should detect full-day event when times are empty"
  end

  def test_is_full_day_event_with_nil_times
    full_day_event = {
      "_name" => "Full Day Event",
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => "01/12/2025",
      "end_time" => nil,
      "description" => "All day event",
      "location" => "location"
    }

    assert send(:is_full_day_event?, full_day_event), "Should detect full-day event when times are nil"
  end

  def test_is_not_full_day_event_with_start_time
    timed_event = {
      "_name" => "Timed Event",
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "01/12/2025",
      "end_time" => "",
      "description" => "Timed event",
      "location" => "location"
    }

    refute send(:is_full_day_event?, timed_event), "Should not detect full-day event when start time exists"
  end

  def test_is_not_full_day_event_with_end_time
    timed_event = {
      "_name" => "Timed Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "01/12/2025",
      "end_time" => "12:00",
      "description" => "Timed event",
      "location" => "location"
    }

    refute send(:is_full_day_event?, timed_event), "Should not detect full-day event when end time exists"
  end

  def test_google_calendar_url_full_day_single_day
    full_day_event = {
      "_name" => "Full Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "01/12/2025",
      "end_time" => "",
      "description" => "All day event",
      "location" => "location"
    }

    url = google_calendar_url(full_day_event)
    assert url.start_with?("https://www.google.com/calendar/render?")
    assert_includes url, "20251201%2F20251202", "Should use date format and add 1 day to end"
    assert_includes url, "Full+Day+Event"
  end

  def test_google_calendar_url_full_day_multi_day
    full_day_event = {
      "_name" => "Multi Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "03/12/2025",
      "end_time" => "",
      "description" => "Multi day event",
      "location" => "location"
    }

    url = google_calendar_url(full_day_event)
    assert url.start_with?("https://www.google.com/calendar/render?")
    assert_includes url, "20251201%2F20251204", "Should use date format and add 1 day to end date"
    assert_includes url, "Multi+Day+Event"
  end

  def test_google_calendar_url_full_day_no_end_date
    full_day_event = {
      "_name" => "Single Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "",
      "end_time" => "",
      "description" => "Single day event",
      "location" => "location"
    }

    url = google_calendar_url(full_day_event)
    assert url.start_with?("https://www.google.com/calendar/render?")
    assert_includes url, "20251201%2F20251202", "Should use start date for both start and end when no end date"
  end

  def test_event_to_ics_full_day_single_day
    full_day_event = {
      "_name" => "Full Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "01/12/2025",
      "end_time" => "",
      "description" => "All day event",
      "location" => "location"
    }

    ics = event_to_ics(full_day_event)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Full Day Event"
    assert_includes ics, "DTSTART;VALUE=DATE:20251201"
    assert_includes ics, "DTEND;VALUE=DATE:20251202", "Should add 1 day to end date for full-day events"
  end

  def test_event_to_ics_full_day_multi_day
    full_day_event = {
      "_name" => "Multi Day Event",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "03/12/2025",
      "end_time" => "",
      "description" => "Multi day event",
      "location" => "location"
    }

    ics = event_to_ics(full_day_event)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Multi Day Event"
    assert_includes ics, "DTSTART;VALUE=DATE:20251201"
    assert_includes ics, "DTEND;VALUE=DATE:20251204", "Should add 1 day to end date for multi-day events"
  end

  def test_event_to_ics_timed_event_format
    ics = event_to_ics(@event)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Test Event"
    # Should contain time-based format, not VALUE=DATE format
    refute_includes ics, "VALUE=DATE"
    assert_includes ics, "DTSTART:"
    assert_includes ics, "DTEND:"
  end

  def test_parse_date_only_valid_date
    date = send(:parse_date_only, "01/12/2025")
    assert_equal Date.new(2025, 12, 1), date
  end

  def test_parse_date_only_invalid_date
    date = send(:parse_date_only, "invalid-date")
    assert_nil date
  end

  def test_parse_date_only_empty_string
    date = send(:parse_date_only, "")
    assert_nil date
  end

  def test_parse_date_only_nil
    date = send(:parse_date_only, nil)
    assert_nil date
  end

  def test_format_google_date
    date = Date.new(2025, 12, 1)
    formatted = send(:format_google_date, date)
    assert_equal "20251201", formatted
  end

  # Edge case tests
  def test_full_day_event_with_whitespace_times
    full_day_event = {
      "_name" => "Whitespace Event",
      "start_date" => "01/12/2025",
      "start_time" => "   ",
      "end_date" => "01/12/2025",
      "end_time" => "  ",
      "description" => "Event with whitespace times",
      "location" => "location"
    }

    assert send(:is_full_day_event?, full_day_event), "Should detect full-day event when times are whitespace"
  end

  def test_google_calendar_url_returns_empty_for_invalid_full_day_event
    invalid_event = {
      "_name" => "Invalid Event",
      "start_date" => "",
      "start_time" => "",
      "end_date" => "",
      "end_time" => "",
      "description" => "Invalid event",
      "location" => "location"
    }

    url = google_calendar_url(invalid_event)
    assert_equal "", url, "Should return empty string for event with no start date"
  end

  def test_event_to_ics_full_day_with_no_start_date
    invalid_event = {
      "_name" => "Invalid Event",
      "start_date" => "",
      "start_time" => "",
      "end_date" => "",
      "end_time" => "",
      "description" => "Invalid event",
      "location" => "location"
    }

    ics = event_to_ics(invalid_event)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Invalid Event"
    # Should not include DTSTART or DTEND for invalid dates
    refute_includes ics, "DTSTART"
    refute_includes ics, "DTEND"
  end

  # Timezone tests
  def test_parse_time_creates_valid_time
    time = send(:parse_time, "01/12/2025", "10:00")
    refute_nil time
    # Should parse the time correctly
    assert_equal 10, time.hour
    assert_equal 0, time.min
  end

  def test_format_google_time_does_not_convert_to_utc
    # Create a time
    time = send(:parse_time, "01/12/2025", "10:00")
    formatted = send(:format_google_time, time)
    # Should preserve the local time, not convert to UTC
    assert_equal "20251201T100000", formatted
    # Should not have 'Z' suffix which indicates UTC
    refute_includes formatted, "Z"
  end

  def test_google_calendar_url_preserves_timezone
    url = google_calendar_url(@event)
    # Should contain the original times without UTC conversion
    assert_includes url, "20251201T100000%2F20251201T120000"
    # Should not contain 'Z' which would indicate UTC
    refute_includes url, "Z"
  end

  # Default end time tests
  def test_google_calendar_url_with_start_time_no_end_time
    event_no_end = {
      "_name" => "Event No End",
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "",
      "end_time" => "",
      "description" => "Event with no end time",
      "location" => "location"
    }

    url = google_calendar_url(event_no_end)
    assert url.start_with?("https://www.google.com/calendar/render?")
    # Should default end time to 23:59 on the same day
    assert_includes url, "20251201T100000%2F20251201T235900"
    assert_includes url, "Event+No+End"
  end

  def test_event_to_ics_with_start_time_no_end_time
    event_no_end = {
      "_name" => "Event No End",
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "",
      "end_time" => "",
      "description" => "Event with no end time",
      "location" => "location"
    }

    ics = event_to_ics(event_no_end)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Event No End"
    assert_includes ics, "DTSTART:"
    assert_includes ics, "DTEND:"
    # Should contain times, not VALUE=DATE format since it's not a full-day event
    refute_includes ics, "VALUE=DATE"
  end

  def test_default_end_time_helper
    start_time = Time.new(2025, 12, 1, 10, 30, 0)
    end_time = send(:default_end_time, start_time)

    assert_equal 2025, end_time.year
    assert_equal 12, end_time.month
    assert_equal 1, end_time.day
    assert_equal 23, end_time.hour
    assert_equal 59, end_time.min
    assert_equal 0, end_time.sec
  end

  def test_google_calendar_url_with_start_time_and_nil_end_time
    event_nil_end = {
      "_name" => "Event Nil End",
      "start_date" => "01/12/2025",
      "start_time" => "14:30",
      "end_date" => "01/12/2025",
      "end_time" => nil,
      "description" => "Event with nil end time",
      "location" => "location"
    }

    url = google_calendar_url(event_nil_end)
    assert url.start_with?("https://www.google.com/calendar/render?")
    # Should default end time to 23:59 on the same day
    assert_includes url, "20251201T143000%2F20251201T235900"
  end

  def test_google_calendar_url_no_start_time_returns_empty
    event_no_start = {
      "_name" => "Event No Start",
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "01/12/2025",
      "end_time" => "18:00",
      "description" => "Event with no start time",
      "location" => "location"
    }

    url = google_calendar_url(event_no_start)
    assert_equal "", url, "Should return empty string when no start time"
  end

  def test_event_to_ics_with_start_time_no_end_time_afternoon
    event_afternoon = {
      "_name" => "Afternoon Event",
      "start_date" => "01/12/2025",
      "start_time" => "15:30",
      "end_date" => "",
      "end_time" => "",
      "description" => "Afternoon event with no end time",
      "location" => "location"
    }

    ics = event_to_ics(event_afternoon)
    assert_includes ics, "BEGIN:VEVENT"
    assert_includes ics, "SUMMARY:Afternoon Event"
    # Should have both start and end times
    assert_includes ics, "DTSTART:"
    assert_includes ics, "DTEND:"
  end

  def test_default_end_time_different_start_times
    # Test with morning start time
    morning_start = Time.new(2025, 12, 1, 8, 15, 0)
    morning_end = send(:default_end_time, morning_start)
    assert_equal 23, morning_end.hour
    assert_equal 59, morning_end.min

    # Test with evening start time
    evening_start = Time.new(2025, 12, 1, 20, 45, 0)
    evening_end = send(:default_end_time, evening_start)
    assert_equal 23, evening_end.hour
    assert_equal 59, evening_end.min

    # Both should be on the same day as start time
    assert_equal morning_start.day, morning_end.day
    assert_equal evening_start.day, evening_end.day
  end
end
