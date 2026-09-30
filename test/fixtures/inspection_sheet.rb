require "csv"
require "webmock"
require_relative "../../lib/server/sheets_config"

WebMock.enable!
WebMock.disable_net_connect!

ENV[SheetsConfig::SPREADSHEET_ID_ENV] = "fixture-sheet"
ENV[SheetsConfig::EVENTS_RANGE_ENV] = "EventTable"
ENV[SheetsConfig::SERVICE_ACCOUNT_ENV] = "fixture-credentials"

module InspectionSheetFixture
  class Sheets
    def get_values(_spreadsheet_id, range)
      raise "Unexpected spreadsheet read" if ENV["EXPECT_NO_SHEET_READ"] == "1"
      raise "Unexpected requested range: #{range}" unless range == "EventTable"

      Google::Apis::SheetsV4::ValueRange.new(
        range: "'Eventos ! outubro'!A10:S16",
        values: CSV.read(File.expand_path("inspection_events.csv", __dir__))
      )
    end
  end
end

SheetsConfig.instance_variable_set(:@sheets, InspectionSheetFixture::Sheets.new)
