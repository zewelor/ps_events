require "json"
require_relative "event_validation"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/array/wrap"

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
end

class EventOcrService
  MODEL = "gemini-2.5-flash-preview-05-20"

  def initialize
    @chat = RubyLLM.chat(model: MODEL)
  end

  def analyze(image_path)
    chat.with_instructions <<~INSTR
      You are an expert in analyzing images and extracting information.
      User will provide you with an image containing text information about events.
      Your task is to analyze the provided image and extract relevant text information in a structured format.
      You will be provided with an image containing text, and you should focus on extracting concise and accurate details from it.
      Current year is #{Time.now.year}.
      Return raw JSON with requested informations.
      Return only with working raw JSON object, without any additional text or explanations.
      If you cannot extract the information, return an empty JSON object {}.
      Direclty return array with events, even if theres only one event.
      Dont respond with markdown json code block, just direclty json array
      Based on the photo / image, write concise information in European Portuguese (Portugal) about event(s), in order. For each event, include:

      <json_schema>
      #{JSON.dump(JSON.parse(File.read(File.expand_path("../event_schema.json", __dir__))))}
      </json_schema>

      - Start date and time (assume current year)
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
      - End date and time (assume current year)
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
      - Price type (field 'price_type')
        - If the price is not mentioned, use 'Desconhecido'
        - If its more comples, like free till some hour, use 'Pago' and add a note in the description
    INSTR

    # Get LLM output as string
    llm_output = chat.ask("", with: image_path).content

    # Parse and validate JSON output
    parse_and_validate_response(llm_output)
  end

  private

  attr_reader :chat

  # Parse and validate the LLM response, returning a result struct
  def parse_and_validate_response(raw_response)
    begin
      data = JSON.parse(raw_response)
    rescue JSON::ParserError => e
      raise "Erro ao analisar JSON: #{e.message}"
    end

    data = Array.wrap(data).map(&:symbolize_keys)

    validator = EventValidation.new
    valid_events = []
    data.each_with_index do |event, idx|
      result = validator.call(event)
      if result.success?
        valid_events << result.to_h
      else
        raise "Erro de validação no evento #{idx + 1}: #{result.errors.inspect}"
      end
    end
    valid_events
  end
end
