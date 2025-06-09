require "csv"
require "json"
require_relative "event_validation"

class EventOcrService
  MODEL = "gemini-2.5-flash-preview-05-20"
  CSV_FILE_PATH = File.expand_path("../../../events.csv", __FILE__)

  def initialize(api_key: ENV.fetch("GEMINI_API_KEY", nil))
    @api_key = api_key
    RubyLLM.configure do |config|
      config.gemini_api_key = @api_key
    end
  end

  def analyze(image_path)
    chat = RubyLLM.chat(model: MODEL)
    chat.with_instructions <<~INSTR
      You are an expert in analyzing images and extracting information. Your task is to analyze the provided image and extract relevant text information in a structured format. You will be provided with an image containing text, and you should focus on extracting concise and accurate details from it. Current year is #{Time.now.year}. Return raw JSON with requested informations. Return only with working raw JSON object, without any additional text or explanations. If you cannot extract the information, return an empty JSON object {}. Direclty return array with events, even if theres only one event. Dont respond with markdown json code block, just direclty json array
    INSTR

    prompt = <<~PROMPT
      Based on the photo / image, write concise information in European Portuguese (Portugal) about 4 events, in order. For each event, include:

      - Event name ( field 'name' )
      - Description (field 'description')
      - Location (field 'location')
      - Organizer (field 'organizer')
      - Start date and time (assume current year)
        - Date in field 'start_date' in format "%d/%m/%Y"
        - Time in field 'start_time' in format "%H:%M"
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
      - End date and time (assume current year)
        - Date in field 'end_date' in format "%d/%m/%Y"
        - Time in field 'end_time' in format "%H:%M"
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
      - Category (#{EventValidation::VALID_CATEGORIES.join(", ")}) ( field 'category' )
      - Price type (#{EventValidation::VALID_PRICE_TYPES.join(", ")}) (field 'price_type')
        - If the price is not mentioned, use 'Desconhecido'
        - If its more comples, like free till some hour, use 'Pago' and add a note in the description
    PROMPT

    response_content = chat.ask(prompt, with: image_path).content

    begin
      parsed_json = JSON.parse(response_content)
      # Assuming the response is an array of events or a single event object
      events = parsed_json.is_a?(Array) ? parsed_json : [parsed_json]

      # Get CSV headers from the events.csv file
      csv_headers = CSV.read(CSV_FILE_PATH, headers: true).headers

      events.map do |event_data|
        next if event_data.empty?

        # Build a hash with string keys for values_at
        event_data_str_keys = event_data.transform_keys(&:to_s)
        event_data_str_keys.values_at(*csv_headers).to_csv
      end.compact.join
    rescue JSON::ParserError => e
      raise "Invalid JSON response: #{e.message} - Response content: #{response_content}"
    rescue => e
      raise "Failed to process and save data: #{e.message} - Response content: #{response_content}"
    end
  end
end
