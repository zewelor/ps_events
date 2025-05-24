require "google/apis/sheets_v4"
require "googleauth"
require "json"
require "base64"

class GoogleSheetsService
  include Google::Apis::SheetsV4

  SCOPE = ["https://www.googleapis.com/auth/spreadsheets"]

  def initialize
    @service = Google::Apis::SheetsV4::SheetsService.new
    @service.authorization = authorize
  end

  def authorize
    unless ENV["GOOGLE_SERVICE_ACCOUNT_JSON_BASE64"]
      raise "GOOGLE_SERVICE_ACCOUNT_JSON_BASE64 environment variable not found. Please set it with base64 encoded service account JSON."
    end

    decoded_json = Base64.decode64(ENV["GOOGLE_SERVICE_ACCOUNT_JSON_BASE64"])
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(decoded_json),
      scope: SCOPE
    )

    credentials.fetch_access_token!
    credentials
  rescue => e
    puts "Error authorizing Google Sheets: #{e.message}"
    puts "\n💡 Setup instructions:"
    puts "1. Go to Google Cloud Console → IAM & Admin → Service Accounts"
    puts "2. Create a new service account (no roles needed at project level)"
    puts "3. Generate a JSON key file"
    puts "4. Base64 encode the JSON file content:"
    puts "   base64 -w 0 /path/to/service-account.json"
    puts "5. Set environment variable:"
    puts "   GOOGLE_SERVICE_ACCOUNT_JSON_BASE64=<base64-encoded-json>"
    puts "6. Share your Google Sheet with the service account email (Editor permission)"
    raise e
  end

  def append_row(spreadsheet_id, range, values)
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [values])

    @service.append_spreadsheet_value(
      spreadsheet_id,
      range,
      value_range,
      value_input_option: "USER_ENTERED"
    )
  rescue => e
    puts "Error appending row to spreadsheet: #{e.message}"
    raise e
  end

  def get_values(spreadsheet_id, range)
    @service.get_spreadsheet_values(spreadsheet_id, range)
  rescue => e
    puts "Error getting values from spreadsheet: #{e.message}"
    raise e
  end
end
