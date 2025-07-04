require "json"
require "retryable"
require_relative "event_validation_error"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/array/wrap"

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
end

class EventOcrService
  MODEL = "gemini-2.5-flash-preview-05-20"

  def self.call(*args, **kwargs)
    new = self.new
    new.analyze(*args, **kwargs)
  rescue => e
    raise "Erro ao analisar imagem: #{e.message}"
  end

  def initialize
    @chat = RubyLLM.chat(model: MODEL)
  end

  def analyze(image_path, retry_sleep: 0)
    # Set initial instructions
    chat.with_instructions(build_instructions)

    llm_output = chat.ask("", with: image_path).content

    begin
      # Parse and validate JSON output - this may raise EventValidationError
      parse_and_validate_response(llm_output)
    rescue EventValidationError => first_error
      # If first attempt fails, retry with error feedback
      puts "🔄 Retrying due to validation error: #{first_error.message}"
      Retryable.retryable(tries: 2, sleep: retry_sleep, on: [EventValidationError]) do |retries, exception|
        puts "🔄 Retry attempt #{retries}"

        current_error = exception || first_error
        puts "📋 Original error message: #{current_error.message}"
        error_message = build_retry_message(current_error)
        llm_output = chat.ask(error_message, with: image_path).content

        # Parse and validate JSON output - this may raise EventValidationError
        parse_and_validate_response(llm_output)
      end
    end
  rescue EventValidationError => e
    raise "Erro ao analisar imagem: #{e.message}"
  end

  private

  attr_reader :chat

  def build_instructions
    <<~INSTR
      You are an expert in analyzing images and extracting information:

      - Your task is to analyze the provided image and extract relevant text information in a structured format.
      - Use only the information from the image, do not make assumptions or use external knowledge.
      - You will be provided with an image containing text, and you should focus on extracting concise and accurate details from it.
      - Current year is #{Time.now.year}.
      - Return raw JSON with requested informations.
        - Return only with working raw JSON object, without any additional text or explanations.
      - If you cannot extract the information, return an empty JSON object {}.
      - Directly return array with events, even if theres only one event.
      - Dont respond with markdown json code block, just directly json array
      - Based on the photo / image, write concise information in European Portuguese (Portugal) about event(s), in order. For each event, include:

      <json_schema>
      #{JSON.dump(JSON.parse(File.read(File.expand_path("../event_schema.json", __dir__))))}
      </json_schema>

      - Start date and time (assume current year)
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
      - End date and time (assume current year)
        - If the time is not mentioned, leave it empty
        - assume event time zone is Europe/Lisbon
        - Only include end time if it is different from start time
      - Price type (field 'price_type')
        - If the price is not mentioned, use 'Desconhecido'
        - If its more comples, like free till some hour, use 'Pago' and add a note in the description
    INSTR
  end

  def build_retry_message(exception)
    message = "The previous response failed validation. Please correct the following issues and try again with a valid JSON response:\n\n"

    if exception.validation_errors&.any?
      message += "Validation errors:\n"
      exception.validation_errors.each_with_index do |error, idx|
        message += "#{idx + 1}. #{error}\n"
      end
    else
      message += "Error: #{exception.message}\n"
    end

    if exception.event_data
      message += "\nData that failed validation:\n#{JSON.pretty_generate(exception.event_data)}\n"
    end

    message += "\nPlease ensure that:\n"
    message += "- The JSON is well formatted\n"
    message += "- All required fields are present\n"
    message += "- Dates are in the format dd/mm/yyyy\n"
    message += "- The category is one of the valid schema categories\n"
    message += "- The event name has at least 3 characters\n"
    message += "\nReturn only the corrected JSON, without any additional text."

    message
  end

  # Parse and validate the LLM response, returning a result struct
  def parse_and_validate_response(raw_response)
    begin
      data = JSON.parse(raw_response)
    rescue JSON::ParserError => e
      error_msg = "Erro ao analisar JSON: #{e.message}"
      raise EventValidationError.new(error_msg, validation_errors: [e.message])
    end

    data = Array.wrap(data).map(&:symbolize_keys)

    validator = EventValidation.new
    valid_events = []

    data.each_with_index do |event, idx|
      result = validator.call(event)

      if result.success?
        valid_events << result.to_h
      else
        raise EventValidationError.new(
          "Erro de validação no evento #{idx + 1}: #{result.errors.inspect}",
          validation_errors: result.errors,
          event_data: data
        )
      end
    end

    valid_events
  end
end
