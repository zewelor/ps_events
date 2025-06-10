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

      <json_schema>
      #{File.read("/app/lib/event_schema.json")}

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
    PROMPT

    chat.ask(prompt, with: image_path).content
  end
end
