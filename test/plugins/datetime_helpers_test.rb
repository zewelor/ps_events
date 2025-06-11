require "minitest/autorun"

require_relative "plugins_helpers"
require_relative "../../events_listing/_plugins/datetime_helpers"

class TestDatetimeHelpers < Minitest::Test
  include Jekyll::DatetimeHelpers

  def test_nil_event_returns_empty_string
    assert_equal "", format_event_datetime(nil)
  end

  def test_nil_start_date_raises_not_implemented_error
    assert_raises(NotImplementedError) { format_event_datetime({}) }
  end

  def test_case1_only_start_date
    event = {
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => nil,
      "end_time" => nil
    }
    assert_equal "01/12/2025", format_event_datetime(event)
  end

  def test_case1_only_start_date_with_empty_strings
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "",
      "end_date" => "",
      "end_time" => ""
    }
    assert_equal "01/12/2025", format_event_datetime(event)
  end

  def test_case1_only_start_date_with_whitespace
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "   ",
      "end_date" => "   ",
      "end_time" => "   "
    }
    assert_equal "01/12/2025", format_event_datetime(event)
  end

  def test_case2_start_date_and_start_time_only
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "14:30",
      "end_date" => nil,
      "end_time" => nil
    }
    assert_equal "01/12/2025 14:30", format_event_datetime(event)
  end

  def test_case3_start_date_and_end_date_only
    event = {
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => "03/12/2025",
      "end_time" => nil
    }
    assert_equal "01/12/2025 - 03/12/2025", format_event_datetime(event)
  end

  def test_case4_same_day_start_date_start_time_end_date_no_end_time
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "14:30",
      "end_date" => "01/12/2025",
      "end_time" => nil
    }
    assert_equal "01/12/2025 14:30", format_event_datetime(event)
  end

  def test_case4_multi_day_start_date_start_time_end_date_no_end_time
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "14:30",
      "end_date" => "03/12/2025",
      "end_time" => nil
    }
    assert_equal "01/12/2025 14:30 - 03/12/2025", format_event_datetime(event)
  end

  def test_case5_start_date_and_end_time_only_until_format
    event = {
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => nil,
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 (until 18:00)", format_event_datetime(event)
  end

  def test_case6_same_day_start_date_end_date_end_time_until_format
    event = {
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => "01/12/2025",
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 (until 18:00)", format_event_datetime(event)
  end

  def test_case7_different_dates_start_date_end_date_end_time
    event = {
      "start_date" => "01/12/2025",
      "start_time" => nil,
      "end_date" => "03/12/2025",
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 - 03/12/2025 18:00", format_event_datetime(event)
  end

  def test_case8_same_day_with_start_and_end_times
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "01/12/2025",
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 10:00 - 18:00", format_event_datetime(event)
  end

  def test_case8_same_day_with_start_and_end_times_no_end_date
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => nil,
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 10:00 - 18:00", format_event_datetime(event)
  end

  def test_case9_multi_day_event_with_start_and_end_times
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "03/12/2025",
      "end_time" => "18:00"
    }
    assert_equal "01/12/2025 10:00 - 03/12/2025 18:00", format_event_datetime(event)
  end

  def test_fallback_case_with_unexpected_combination
    # This should hit the fallback case at the end of the method
    # We'll create a scenario that doesn't match any of the specific cases
    # but still has a valid start_date
    event = {
      "start_date" => "01/12/2025"
      # No other fields to trigger any specific case
    }
    assert_equal "01/12/2025", format_event_datetime(event)
  end

  def test_whitespace_handling_in_dates_and_times
    event = {
      "start_date" => "  01/12/2025  ",
      "start_time" => "  14:30  ",
      "end_date" => nil,
      "end_time" => nil
    }
    assert_equal "01/12/2025 14:30", format_event_datetime(event)
  end

  def test_edge_case_empty_start_date_string
    event = {
      "start_date" => "",
      "start_time" => "14:30",
      "end_date" => nil,
      "end_time" => nil
    }
    # This should raise NotImplementedError because empty string is treated as nil
    assert_raises(NotImplementedError) { format_event_datetime(event) }
  end

  def test_edge_case_whitespace_only_start_date
    event = {
      "start_date" => "   ",
      "start_time" => "14:30",
      "end_date" => nil,
      "end_time" => nil
    }
    # This should raise NotImplementedError because whitespace-only string is treated as nil
    assert_raises(NotImplementedError) { format_event_datetime(event) }
  end

  def test_complex_scenario_all_fields_present_same_day
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "01/12/2025",
      "end_time" => "18:30"
    }
    assert_equal "01/12/2025 10:00 - 18:30", format_event_datetime(event)
  end

  def test_complex_scenario_all_fields_present_multi_day
    event = {
      "start_date" => "01/12/2025",
      "start_time" => "10:00",
      "end_date" => "03/12/2025",
      "end_time" => "18:30"
    }
    assert_equal "01/12/2025 10:00 - 03/12/2025 18:30", format_event_datetime(event)
  end

  def test_real_world_example_music_concert
    event = {
      "start_date" => "15/06/2025",
      "start_time" => "20:00",
      "end_date" => nil,
      "end_time" => nil
    }
    assert_equal "15/06/2025 20:00", format_event_datetime(event)
  end

  def test_real_world_example_weekend_festival
    event = {
      "start_date" => "19/07/2025",
      "start_time" => "10:00",
      "end_date" => "21/07/2025",
      "end_time" => "22:00"
    }
    assert_equal "19/07/2025 10:00 - 21/07/2025 22:00", format_event_datetime(event)
  end

  def test_real_world_example_all_day_event
    event = {
      "start_date" => "10/08/2025",
      "start_time" => nil,
      "end_date" => "12/08/2025",
      "end_time" => nil
    }
    assert_equal "10/08/2025 - 12/08/2025", format_event_datetime(event)
  end

  def test_real_world_example_until_format
    event = {
      "start_date" => "05/09/2025",
      "start_time" => nil,
      "end_date" => nil,
      "end_time" => "23:59"
    }
    assert_equal "05/09/2025 (until 23:59)", format_event_datetime(event)
  end
end
