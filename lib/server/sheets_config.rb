require_relative "google_sheets_service"
require_relative "add_event_service"

# Single place where the spreadsheet location and its services are resolved
# from the environment, so bin scripts wire them identically instead of
# repeating the ENV lookups. bin/server.rb keeps its own wiring because it
# swaps in a nil service under APP_ENV=test.
module SheetsConfig
  SPREADSHEET_ID_ENV = "GOOGLE_SPREADSHEET_ID"
  EVENTS_RANGE_ENV = "EVENTS_SHEET_RANGE"
  SERVICE_ACCOUNT_ENV = "GOOGLE_SERVICE_ACCOUNT_JSON_BASE64"

  REQUIRED_ENV_KEYS = [SPREADSHEET_ID_ENV, EVENTS_RANGE_ENV, SERVICE_ACCOUNT_ENV].freeze

  module_function

  # Which of the keys this module owns are absent or blank. Scripts check this
  # before building a service, so a missing key produces a one-line message
  # instead of a KeyError from ENV.fetch.
  def missing_env_keys(keys = REQUIRED_ENV_KEYS)
    keys.select { |key| ENV[key].to_s.strip.empty? }
  end

  def spreadsheet_id
    ENV.fetch(SPREADSHEET_ID_ENV)
  end

  def events_range
    ENV.fetch(EVENTS_RANGE_ENV)
  end

  def sheets
    @sheets ||= GoogleSheetsService.new
  end

  def add_event_service(sheets: self.sheets)
    AddEventService.new(
      google_sheets: sheets,
      spreadsheet_id: spreadsheet_id,
      events_range: events_range
    )
  end

  # A nil range means "use the configured one", so callers can forward an
  # optional override without special-casing it. Return the first event's sheet
  # row number from the resolved range, including when the caller used a name.
  def read_rows(range: nil)
    response = sheets.get_values(spreadsheet_id, range || events_range)
    first_cell = response.range.to_s.split("!").last.to_s.split(":").first.to_s
    row_match = /\A[A-Z]+([1-9]\d*)\z/.match(first_cell)
    raise "Cannot determine spreadsheet row from range #{response.range.inspect}" unless row_match

    header, *rows = response.values
    [header, rows, row_match[1].to_i + 1]
  end
end
