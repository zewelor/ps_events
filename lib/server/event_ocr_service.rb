require "json"
require "fileutils"
require "mini_magick"
require "retryable"
require "tmpdir"
require_relative "event_validation"
require_relative "event_validation_error"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/enumerable"

RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  # config.log_level = :debug
end

class EventOcrService
  MODEL = "gemini-3-flash-preview"
  PDF_DENSITY = 200

  def self.call(*args, **kwargs)
    new = self.new
    new.analyze(*args, **kwargs)
  rescue => e
    raise "Erro ao analisar imagem: #{e.message}"
  end

  def initialize
    @chat = RubyLLM.chat(model: MODEL).with_schema(build_schema).with_thinking(effort: :medium)
  end

  def analyze(input_path, retry_sleep: 0)
    # Set initial instructions
    chat.with_instructions(build_instructions)

    return analyze_pdf(input_path, retry_sleep: retry_sleep) if pdf_file?(input_path)

    analyze_image(input_path, retry_sleep: retry_sleep)
  end

  private

  attr_reader :chat

  def analyze_image(image_path, retry_sleep:)
    llm_output = chat.ask(with: image_path).content

    begin
      # Parse and validate JSON output - this may raise EventValidationError
      parse_and_validate_response(llm_output)
    rescue EventValidationError => first_error
      # If first attempt fails, retry with error feedback
      puts "🔄 Retrying due to validation error: #{first_error.message}"
      Retryable.retryable(tries: 5, sleep: retry_sleep, on: [EventValidationError]) do |retries, exception|
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

  def analyze_pdf(pdf_path, retry_sleep:)
    page_image_paths, temp_dir = extract_pdf_pages_to_images(pdf_path)
    events = page_image_paths.flat_map do |page_image_path|
      analyze_image(page_image_path, retry_sleep: retry_sleep)
    end

    events
  ensure
    cleanup_temp_dir(temp_dir)
  end

  def extract_pdf_pages_to_images(pdf_path)
    temp_dir = Dir.mktmpdir("event_ocr_pdf_")
    output_pattern = File.join(temp_dir, "page-%04d.png")
    MiniMagick.convert do |convert|
      convert.density(PDF_DENSITY)
      convert << pdf_path
      convert << output_pattern
    end

    page_image_paths = Dir.glob(File.join(temp_dir, "page-*.png")).sort
    raise "Erro ao converter PDF: nenhum conteúdo de imagem foi gerado" if page_image_paths.empty?

    [page_image_paths, temp_dir]
  rescue => e
    cleanup_temp_dir(temp_dir)
    raise "Erro ao converter PDF: #{e.message}"
  end

  def cleanup_temp_dir(path)
    return if path.nil? || !Dir.exist?(path)

    FileUtils.remove_entry(path)
  end

  def pdf_file?(input_path)
    File.extname(input_path).casecmp(".pdf").zero?
  end

  def build_schema
    schema = JSON.parse(File.read(File.expand_path("../event_schema.json", __dir__)))
    {
      "type" => "array",
      "items" => schema
    }
  end

  def build_instructions
    <<~INSTR
      You are an expert in analyzing images and extracting information:

      - Your task is to analyze the provided image and extract relevant text information in a structured format.
      - Think extra hard to not miss any event on the image.
      - Use only the information from the image, do not make assumptions or use external knowledge.
      - You will be provided with an image containing text, and you should focus on extracting concise and accurate details from it.
      - Current year is #{Time.now.year}.
      - Based on the photo / image, write concise information in European Portuguese (Portugal) about event(s), in order.
      - If you cannot extract the information, return an empty JSON object {}.
      - For location, skip writing / adding "Porto Santo". We always assume the location is somewhere on island Porto Santo.
      - Directly return array with events, even if theres only one event.
      - Focus on required fields, do not add any additional information, unless explicitly mentioned and contained in the image and json schema.
      - If all of the events are in the same day AND same place / location, return only single event
        - In description write hours and whats happening at what time. For example:
          "10:00 - Abertura do evento, 11:00 - Palestra sobre tecnologia, 12:00 - Almoço"
        - For start_time use hour from the first thing happening / listed.
        - Unless there is a clear / explicit end or finish time, leave it empty. Do not assume end_time.
      - Start date and time (assume current year)
        - If the start time is not mentioned, leave it empty. If there are multiple events in the same day, AND place, use the first time mentioned.
        - assume event time zone is Europe/Lisbon
      - End date and time (assume current year)
        - If the end / finish time is not explicitly mentioned, leave it empty.
        - assume event time zone is Europe/Lisbon
        - Only include end time if it is different from start time
      - Price type (field 'price_type')
        - If the price of an event is not specifically mentioned, use 'Desconhecido'
        - If its more complex, like free till some hour, use 'Pago' and add a note in the description
        - Be sure that price mentioned is price for attending the event, not for something else, like parking / extra menu / etc.
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
    message += "- The JSON response follows the expected schema\n"
    message += "- All required fields are present\n"
    message += "- Dates are in the format dd/mm/yyyy\n"
    message += "- The category is one of the valid schema categories\n"
    message += "- The event name has at least 3 characters"

    message
  end

  # Parse and validate the LLM response, returning a result struct
  def parse_and_validate_response(response)
    if response.is_a?(Hash) || response.is_a?(Array)
      data = response
    else
      begin
        data = JSON.parse(response)
      rescue JSON::ParserError => e
        error_msg = "Erro ao analisar JSON: #{e.message}"
        raise EventValidationError.new(error_msg, validation_errors: [e.message])
      end
    end

    # We can get a single object or an array of objects
    data = Array.wrap(data).each do |item|
      item.compact_blank!
      item.symbolize_keys!
      item[:responsibility_agreement] = "on"
    end

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
