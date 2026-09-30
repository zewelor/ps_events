require "minitest/autorun"
require_relative "../../lib/server/sheets_config"

class TestSheetsConfig < Minitest::Test
  ENV_KEYS = [SheetsConfig::SPREADSHEET_ID_ENV, SheetsConfig::EVENTS_RANGE_ENV, SheetsConfig::SERVICE_ACCOUNT_ENV].freeze

  def setup
    # Rakefile loads every test file into one process, so keys that were
    # originally unset have to be deleted again or they leak into other tests.
    @original_env = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    @sheets = FakeSheets.new
    SheetsConfig.instance_variable_set(:@sheets, @sheets)
  end

  def teardown
    SheetsConfig.instance_variable_set(:@sheets, nil)
    @original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_read_rows_splits_the_header_from_the_data
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"
    @sheets.rows = [%w[name start_date], %w[Festa 9/10/2026]]

    header, rows = SheetsConfig.read_rows

    assert_equal %w[name start_date], header
    assert_equal [%w[Festa 9/10/2026]], rows
  end

  def test_read_rows_uses_the_configured_range_by_default
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"

    SheetsConfig.read_rows

    assert_equal "Approved!A:O", @sheets.requested_range
  end

  def test_read_rows_prefers_an_explicit_range
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"

    SheetsConfig.read_rows(range: "Approved!A:C")

    assert_equal "Approved!A:C", @sheets.requested_range
  end

  def test_read_rows_preserves_the_returned_row_offset_for_a_named_range
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    @sheets.response_range = "'Events ! 2026'!B10:T20"

    _, _, first_row_number = SheetsConfig.read_rows(range: "EventTable")

    assert_equal "EventTable", @sheets.requested_range
    assert_equal 11, first_row_number
  end

  def test_read_rows_defaults_to_row_two_for_a_table_starting_at_row_one
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"

    _, _, first_row_number = SheetsConfig.read_rows

    assert_equal 2, first_row_number
  end

  def test_read_rows_rejects_an_unresolved_row_offset
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    @sheets.response_range = "EventTable"

    error = assert_raises(RuntimeError) { SheetsConfig.read_rows(range: "EventTable") }

    assert_includes error.message, "Cannot determine spreadsheet row"
  end

  def test_add_event_service_is_wired_to_the_configured_sheet
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"
    service = SheetsConfig.add_event_service

    assert_equal "sheet-id", service.instance_variable_get(:@spreadsheet_id)
    assert_equal "Approved!A:O", service.instance_variable_get(:@events_range)
    assert_same @sheets, service.instance_variable_get(:@google_sheets)
  end

  def test_add_event_service_accepts_an_injected_sheet
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"
    injected = FakeSheets.new

    service = SheetsConfig.add_event_service(sheets: injected)

    assert_same injected, service.instance_variable_get(:@google_sheets)
  end

  def test_missing_env_keys_reports_blank_and_absent_keys
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"
    ENV[SheetsConfig::SERVICE_ACCOUNT_ENV] = "credentials"

    assert_empty SheetsConfig.missing_env_keys

    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "   "

    assert_equal [SheetsConfig::EVENTS_RANGE_ENV], SheetsConfig.missing_env_keys
  end

  def test_missing_env_keys_accepts_an_explicit_key_list
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::SERVICE_ACCOUNT_ENV] = ""

    assert_equal [SheetsConfig::SERVICE_ACCOUNT_ENV], SheetsConfig.missing_env_keys([SheetsConfig::SERVICE_ACCOUNT_ENV])
  end

  def test_read_rows_tolerates_an_empty_sheet
    ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "sheet-id"
    ENV[SheetsConfig::EVENTS_RANGE_ENV] = "Approved!A:O"
    @sheets.rows = []

    header, rows = SheetsConfig.read_rows

    assert_nil header
    assert_empty rows
  end

  class FakeSheets
    attr_accessor :rows, :response_range
    attr_reader :requested_range

    def get_values(_spreadsheet_id, range)
      @requested_range = range
      Google::Apis::SheetsV4::ValueRange.new(values: rows || [], range: response_range || "Approved!A1:O1000")
    end
  end
end
