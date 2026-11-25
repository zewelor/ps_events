require "digest"
require "fileutils"
require "json"
require "json-schema"
require "mini_magick"
require "stringio"
require "tmpdir"
require_relative "admission"
require_relative "client"
require_relative "prompts"
require_relative "schemas"

module Ocr
  class SourceWorkflow
    DEFAULT_MODEL = "gpt-6.1-terra".freeze
    DEFAULT_REASONING_EFFORT = "medium".freeze
    IMAGE_MAX_SIZE = 4096
    PANEL_IDS = [1].freeze

    def self.call(path, **options)
      analyze_options = options.slice(:additional_text, :fallback_year, :artifact_dir)
      new(**options.except(:additional_text, :fallback_year, :artifact_dir)).analyze(path, **analyze_options)
    end

    def initialize(model: DEFAULT_MODEL, reasoning_effort: DEFAULT_REASONING_EFFORT, request_timeout: 180)
      @model = Client.resolve_model(model)
      @effort = reasoning_effort.to_sym
      @request_timeout = request_timeout
    end

    def run_evidence
      costs = @calls.map { |call| RubyLLM::Cost.from_h(call.fetch(:cost)) }
      {
        stage: @stage, image_detail: @image_detail, models: {reader: @model.id, reader_effort: @effort.to_s},
        hashes: @hashes, calls: @calls,
        timing: {total_seconds: (clock - @started).round(4), stages: @timings},
        usage_totals: %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].to_h { |key| [key, @calls.sum { |call| call.dig(:tokens, key).to_i }] },
        cost_totals: RubyLLM::Cost.aggregate(costs, complete: costs.all? { |cost| !cost.total.nil? }).to_h
      }.compact
    end

    def analyze(path, additional_text: nil, fallback_year: Time.now.year, artifact_dir: nil)
      @started = clock
      @stage = "init"
      @calls = []
      @timings = {}
      @hashes = {}
      @image_detail = nil
      raise ArgumentError, "Input file does not exist: #{path}" unless File.file?(path)

      if artifact_dir && Dir.exist?(artifact_dir) && !Dir.empty?(artifact_dir)
        raise ArgumentError, "Artifact directory must be empty: #{artifact_dir}"
      end

      bytes = File.binread(path)
      attachment = RubyLLM::Attachment.new(StringIO.new(bytes), filename: File.basename(path), resolution: :original)
      image = attachment.image?
      pdf = attachment.pdf? && bytes.start_with?("%PDF-")
      raise ArgumentError, "Source must be an image or PDF: #{path}" unless image || pdf

      @hashes[:source_sha256] = Digest::SHA256.hexdigest(bytes)
      @hashes[:sent_sha256] = @hashes[:source_sha256]
      if image
        @image_detail = "original"
        sent_bytes, sent_filename = prepare_image(bytes, File.basename(path), attachment.mime_type)
        if sent_filename
          attachment = RubyLLM::Attachment.new(StringIO.new(sent_bytes), filename: sent_filename, resolution: :original)
          @hashes[:sent_sha256] = Digest::SHA256.hexdigest(sent_bytes)
        end
      end
      year = Integer(fallback_year)
      schema = Schemas.reader_schema(PANEL_IDS, additional_text: additional_text)
      instructions = Prompts.reader_instructions(fallback_year: year)
      prompt = Prompts.build_reader_prompt(panel_ids: PANEL_IDS, additional_text: additional_text, pdf: pdf)
      @hashes[:reader_prompt_sha256] = Digest::SHA256.hexdigest(instructions)
      @hashes[:reader_request_sha256] = Digest::SHA256.hexdigest(prompt)
      @hashes[:reader_schema_sha256] = Digest::SHA256.hexdigest(JSON.generate(schema))
      @hashes[:places_catalogue_sha256] = Places.catalogue_sha256
      @hashes[:canonical_schema_sha256] = Digest::SHA256.file(EventValidation::SCHEMA_PATH).hexdigest
      if artifact_dir
        FileUtils.mkdir_p(artifact_dir)
        File.binwrite(File.join(artifact_dir, "source#{File.extname(path)}"), bytes)
        File.binwrite(File.join(artifact_dir, sent_filename), sent_bytes) if sent_filename
        File.write(File.join(artifact_dir, "reader_request.json"), JSON.pretty_generate({instructions: instructions, prompt: prompt, schema: schema}) + "\n")
      end
      @stage = "reader"
      chat = Client.context(request_timeout: @request_timeout)
        .chat(model: @model.id, provider: @model.provider).with_schema(schema).with_thinking(effort: @effort).with_instructions(instructions)
      started = clock
      begin
        response = chat.ask(prompt, with: [attachment])
      rescue => e
        @calls << {call_index: 1, stage: "reader", model: @model.id, provider: @model.provider,
                   seconds: (clock - started).round(4), tokens: chat.tokens.to_h, cost: chat.cost.to_h,
                   error: {type: e.class.name, message: e.message}}
        File.write(File.join(artifact_dir, "reader_response.json"), JSON.pretty_generate(@calls.last) + "\n") if artifact_dir
        raise
      ensure
        @timings["reader"] = (clock - started).round(4)
      end
      @calls << {call_index: 1, stage: "reader", model: response.model || @model.id, provider: @model.provider,
                 seconds: @timings["reader"], tokens: chat.tokens.to_h, cost: chat.cost.to_h,
                 finish_reason: response.finish_reason, raw_text: response.content}
      File.write(File.join(artifact_dir, "reader_response.json"), JSON.pretty_generate(@calls.last) + "\n") if artifact_dir
      raise WorkflowError.new("Resposta do leitor OCR incompleta: #{response.finish_reason || "unknown"}", stage: :reader) unless response.stopped?

      begin
        parsed = response.parsed
      rescue JSON::ParserError => e
        raise WorkflowError.new("Erro ao analisar JSON (reader): #{e.message}", stage: :reader)
      end
      errors = JSON::Validator.fully_validate(schema, parsed)
      raise WorkflowError.new("Formato de resposta OCR inválido: #{errors.join("; ")}", stage: :reader, details: errors) unless errors.empty?

      @stage = "admission"
      admitted = Admission.evaluate(parsed.fetch("panels"), panel_ids: PANEL_IDS, additional_text: additional_text)
      result = {route: "whole_source", fallback_year: year, events: admitted[:events], review_items: admitted[:review_items], uncertain_fields_by_index: admitted[:uncertain_fields_by_index], diagnostics: {panels: admitted[:panels], artifact_dir: artifact_dir}}.merge(run_evidence)
      File.write(File.join(artifact_dir, "result.json"), JSON.pretty_generate(result) + "\n") if artifact_dir
      result
    end

    private

    def prepare_image(bytes, filename, mime_type)
      Dir.mktmpdir("ocr_source_") do |dir|
        original_path = File.join(dir, "source#{File.extname(filename)}")
        File.binwrite(original_path, bytes)
        dimensions = MiniMagick.identify do |identify|
          identify.ping
          identify.format "%w %h %W %H"
          identify << "#{original_path}[0]"
        end.split.map { |dimension| Integer(dimension) }
        animated_gif = if mime_type == "image/gif"
          frames = MiniMagick.identify do |identify|
            identify.ping
            identify.format "%n\n"
            identify << original_path
          end.lines.first
          Integer(frames) > 1
        else
          false
        end
        supported_format = %w[image/jpeg image/png image/webp].include?(mime_type) ||
          (mime_type == "image/gif" && @model.provider == "openai")
        return [bytes, nil] if supported_format && !animated_gif && dimensions.max <= IMAGE_MAX_SIZE

        sent_filename = (mime_type == "image/jpeg") ? "sent.jpg" : "sent.png"
        output_path = File.join(dir, sent_filename)
        coalesce = mime_type == "image/gif" && dimensions.first(2) != dimensions.last(2)
        MiniMagick.convert do |convert|
          convert << "#{original_path}[0]"
          convert.coalesce if coalesce
          convert.auto_orient
          convert.filter "Lanczos"
          # ImageMagick's > suffix shrinks oversized images and never upscales.
          convert.resize "#{IMAGE_MAX_SIZE}x#{IMAGE_MAX_SIZE}>"
          convert.strip
          convert << output_path
        end
        [File.binread(output_path), sent_filename]
      end
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
