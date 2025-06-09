class EventOcrService
  MODEL = "gemini-2.5-flash-preview-05-20"

  def initialize(api_key: ENV.fetch("GEMINI_API_KEY", nil))
    @api_key = api_key
    RubyLLM.configure do |config|
      config.gemini_api_key = @api_key
    end
  end

  def analyze(image_path)
    chat = RubyLLM.chat(model: MODEL)
    chat.with_instructions <<~INSTR
      You are an expert in analyzing images and extracting information. Your task is to analyze the provided image and extract relevant text information in a structured format. You will be provided with an image containing text, and you should focus on extracting concise and accurate details from it. Current year is #{Time.now.year}. Return JSON with requested informations
    INSTR

    prompt = <<~PROMPT
      Based on the photos, write concise information in European Portuguese (Portugal) about 4 events, in order. For each event, include:

      - Event name
      - Description
      - Location
      - Organizer
      - Start date and time (assume current year)
        - use ISO 8601 format (YYYY-MM-DDTHH:MM:SS)
        - If the time is not mentioned, use '00:00:00'
        - assume event time zosne is Europe/Lisbon
      - End date and time (assume current year)
        - use ISO 8601 format (YYYY-MM-DDTHH:MM:SS)
        - If the time is not mentioned, use '00:00:00'
        - assume event time zosne is Europe/Lisbon
      - Category (#{EventValidation::VALID_CATEGORIES.join(', ')})
      - Price type (#{EventValidation::VALID_PRICE_TYPES.join(', ')})
        - If the price is not mentioned, use 'Desconhecido'
        - If its more comples, like free till some hour, use 'Pago' and add a note in the description
    PROMPT
    chat.ask(prompt, with: image_path).content
  end
end
