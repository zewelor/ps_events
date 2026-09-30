require "minitest/autorun"
require "active_support"
require_relative "../../lib/server/add_event_service"
require_relative "../../lib/server/event_validation_error"

class AddEventServiceTest < Minitest::Test
  class RecordingSheets
    attr_reader :rows

    def initialize
      @rows = []
    end

    def append_row(_spreadsheet_id, _range, row)
      @rows << row
      nil
    end
  end

  def setup
    @sheets = RecordingSheets.new
    @service = AddEventService.new(google_sheets: @sheets, spreadsheet_id: "test-sheet", events_range: "Events!A:S")
    @event = {
      name: "Concerto de teste",
      start_date: "9/10/2026",
      start_time: "18:00",
      end_date: "09/10/2026",
      end_time: "20:00",
      location: "Largo do Pelourinho",
      description: "Concerto de teste com entrada gratuita.",
      category: "Música",
      organizer: "Organização de teste"
    }
  end

  def test_valid_dates_are_appended_without_changing_their_format
    %w[9/1/2026 09/1/2026 9/01/2026 09/01/2026].each do |date|
      capture_io do
        @service.add_event(@event.merge(start_date: date, end_date: date), submitter_email: "test@example.com")
      end

      assert_equal [date, date], @sheets.rows.last.values_at(3, 5)
    end
  end

  def test_invalid_dates_never_reach_the_sheet
    %i[start_date end_date].each do |field|
      ["09/10/26", "09/10/2026junk", "09/10/2026\njunk", "31/02/2026"].each do |date|
        error = nil
        capture_io do
          error = assert_raises(EventValidationError) do
            @service.add_event(@event.merge(field => date), submitter_email: "test@example.com")
          end
        end

        assert error.validation_errors.key?(field), "Expected #{field} error for #{date.inspect}"
        assert_empty @sheets.rows
      end
    end
  end

  def test_same_day_time_order_is_checked_across_different_date_padding
    capture_io do
      error = assert_raises(EventValidationError) do
        @service.add_event(@event.merge(end_time: "17:00"), submitter_email: "test@example.com")
      end
      assert error.validation_errors.key?(:end_time)
    end

    assert_empty @sheets.rows
  end

  def test_other_event_validation_errors_also_prevent_an_append
    capture_io do
      error = assert_raises(EventValidationError) do
        @service.add_event(@event.merge(category: "Unknown"), submitter_email: "test@example.com")
      end
      assert error.validation_errors.key?(:category)
    end

    assert_empty @sheets.rows
  end
end
