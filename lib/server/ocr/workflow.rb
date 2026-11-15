require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../event_ocr_service"
require_relative "admission"
require_relative "image_prep"
require_relative "judges"
require_relative "places"
require_relative "prompts"
require_relative "schemas"

module Ocr
  class Workflow
    DEFAULT_ROUTER_MODEL = "gpt-6-luna"
    DEFAULT_GEOMETRY_MODEL = "gpt-6-luna"
    DEFAULT_GEOMETRY_EFFORT = :medium
    DEFAULT_JUDGE_MODEL = "gpt-6-luna"
    DEFAULT_READER_MODEL = EventOcrService::MODEL
    DEFAULT_READER_EFFORT = EventOcrService::REASONING_EFFORT
    IMAGE_DETAILS = %w[auto low high original].freeze
    DEFAULT_IMAGE_DETAIL = "original"
    DEFAULT_UPSCALE = false
    GEOMETRY_REQUEST_PROMPT = "Locate all complete agenda panels, embedded image masks and appropriate cleanup modes."

    def self.call(input_path, **options)
      analyze_options = options.slice(:additional_text, :fallback_year, :artifact_dir)
      init_options = options.except(:additional_text, :fallback_year, :artifact_dir)
      new(**init_options).analyze(input_path, **analyze_options)
    end

    attr_reader :current_stage

    def run_evidence
      {
        stage: @current_stage.to_s,
        image_detail: @image_detail,
        upscale: @upscale,
        hashes: @hashes,
        timing: {total_seconds: @total_seconds, stages: @stage_timings.transform_keys(&:to_s)},
        calls: @calls,
        usage_totals: aggregated_usage,
        cost_totals: aggregated_cost
      }
    end

    def initialize(
      model: ENV.fetch("OCR_MODEL", DEFAULT_READER_MODEL),
      reasoning_effort: ENV["OCR_REASONING_EFFORT"] || DEFAULT_READER_EFFORT,
      router_model: DEFAULT_ROUTER_MODEL,
      geometry_model: DEFAULT_GEOMETRY_MODEL,
      geometry_effort: DEFAULT_GEOMETRY_EFFORT,
      judge_model: DEFAULT_JUDGE_MODEL,
      image_detail: DEFAULT_IMAGE_DETAIL,
      upscale: DEFAULT_UPSCALE,
      llm_recovery: :none,
      request_timeout: 180
    )
      raise ArgumentError, "unknown LLM recovery policy: #{llm_recovery.inspect}" unless %i[automatic none].include?(llm_recovery)
      raise ArgumentError, "upscale must be true or false (got #{upscale.inspect})" unless [true, false].include?(upscale)

      normalized_detail = image_detail.to_s
      unless IMAGE_DETAILS.include?(normalized_detail)
        raise ArgumentError, "unknown image detail level: #{image_detail.inspect} (expected one of: #{IMAGE_DETAILS.join(", ")})"
      end

      @reader_model_info = EventOcrService.resolve_model(model)
      @reader_effort = (reasoning_effort || DEFAULT_READER_EFFORT).to_sym
      @router_model_info = resolve_judge_model(router_model)
      @geometry_model_info = EventOcrService.resolve_model(geometry_model)
      @geometry_effort = geometry_effort.to_sym
      @judge_model_info = resolve_judge_model(judge_model)
      @image_detail = normalized_detail
      @upscale = upscale
      @llm_recovery = llm_recovery
      @request_timeout = request_timeout
    end

    def analyze(input_path, additional_text: nil, fallback_year: Time.now.year, artifact_dir: nil)
      total_started = monotonic_now
      reset_run_state(fallback_year, artifact_dir)

      if File.extname(input_path.to_s).casecmp(".pdf").zero?
        raise ArgumentError, "Detailed OCR workflow does not support PDF files yet; use EventOcrService (legacy direct path) for PDFs."
      end

      raise ArgumentError, "Input file does not exist: #{input_path}" unless File.file?(input_path)

      @hashes[:source_sha256] = Digest::SHA256.file(input_path).hexdigest

      with_workspace(artifact_dir) do |work_dir|
        original = run_stage(:source_prep) do
          ImagePrep.prepare_original(input_path, File.join(work_dir, "01-original.png"))
        end

        router_judgment = run_stage(:router) do
          invoke_router(original[:path], work_dir)
        end

        route = determine_route(router_judgment)
        if route == "review"
          return build_result(
            route: "review",
            events: [],
            review_items: [router_review_item(router_judgment)],
            diagnostics: {router: router_judgment.to_h, artifact_dir: artifact_dir},
            total_started: total_started
          )
        end

        if route == "direct_ocr"
          return execute_direct_branch(
            original: original,
            work_dir: work_dir,
            additional_text: additional_text,
            fallback_year: fallback_year,
            router_judgment: router_judgment,
            artifact_dir: artifact_dir,
            total_started: total_started
          )
        end

        execute_monthly_branch(
          original: original,
          work_dir: work_dir,
          additional_text: additional_text,
          fallback_year: fallback_year,
          router_judgment: router_judgment,
          artifact_dir: artifact_dir,
          total_started: total_started
        )
      end
    ensure
      @total_seconds = (monotonic_now - total_started).round(4)
    end

    private

    def resolve_judge_model(model_id)
      info = EventOcrService.resolve_model(model_id)
      unless info.provider == "openai"
        raise ArgumentError, "Judge model #{info.id} uses provider #{info.provider}; native RubyLLM::Judge decisions require openai"
      end

      info
    end

    def reset_run_state(fallback_year, artifact_dir)
      @current_stage = :init
      @stage_timings = Hash.new(0.0)
      @calls = []
      @hashes = {
        places_catalogue_sha256: Places.catalogue_sha256,
        canonical_schema_sha256: Digest::SHA256.file(EventValidation::SCHEMA_PATH).hexdigest,
        router_prompt_sha256: Digest::SHA256.hexdigest(Judges::ROUTER_PROMPT),
        reader_inputs: []
      }
      @fallback_year = Integer(fallback_year)
      @artifact_dir = artifact_dir
    end

    def with_workspace(artifact_dir)
      if artifact_dir
        FileUtils.mkdir_p(artifact_dir)
        yield artifact_dir
      else
        Dir.mktmpdir("ocr_workflow_") { |temp_dir| yield temp_dir }
      end
    end

    def run_stage(stage)
      @current_stage = stage
      started = monotonic_now
      yield
    ensure
      @stage_timings[stage] += (monotonic_now - started).round(4)
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def client
      EventOcrService.llm_client(llm_recovery: @llm_recovery, request_timeout: @request_timeout)
    end

    def attachment_for(path)
      return path if @image_detail == "auto"

      RubyLLM::Attachment.new(path, resolution: @image_detail.to_sym)
    end

    def invoke_router(original_path, work_dir)
      started = monotonic_now
      judgment = Judges::AgendaKindJudge.judge(
        Judges::ROUTER_PROMPT,
        with: attachment_for(original_path),
        model: @router_model_info.id,
        provider: @router_model_info.provider,
        context: client
      )
      elapsed = (monotonic_now - started).round(4)
      record_judge_call(stage: :router, model_info: @router_model_info, judgment: judgment, seconds: elapsed)
      write_artifact_json(work_dir, "02-kind.json", judgment.to_h)
      judgment
    end

    def determine_route(judgment)
      kind = judgment.fetch("kind").choice.to_s
      month = judgment.fetch("month").choice.to_s

      case kind
      when "other"
        "direct_ocr"
      when "monthly_agenda"
        Judges::MONTH_NAMES.include?(month) ? "monthly_agenda" : "review"
      else
        "review"
      end
    end

    def router_review_item(judgment)
      kind = judgment.fetch("kind").choice.to_s
      month = judgment.fetch("month").choice.to_s
      reason = (kind == "monthly_agenda") ? "ambiguous_heading_month" : "uncertain_document_format"
      {
        stage: "router",
        group_id: nil,
        title_hint: nil,
        reason: reason,
        message: "Classificação inicial inconclusiva (kind=#{kind}, month=#{month}).",
        candidate: nil,
        trace: {router: judgment.to_h[:answers], verified: false}
      }
    end

    def execute_direct_branch(original:, work_dir:, additional_text:, fallback_year:, router_judgment:, artifact_dir:, total_started:)
      prepared = run_stage(:source_prep) do
        ImagePrep.prepare_direct(
          original[:path],
          File.join(work_dir, "03-direct-ocr.png"),
          scale: @upscale ? EventOcrService::IMAGE_SCALE : 1
        )
      end

      heading = {
        fallback_year: fallback_year,
        document_type: "standalone_flyer",
        date_rule: "Preserve printed dates; fallback year only if no year is supplied."
      }
      panel_meta = {1 => {id: 1, title_hint: "standalone_flyer", banner_policy: {action: "direct", allowed_fields: []}}}
      @hashes[:reader_inputs] = [{panel_id: 1, path: prepared[:path], sha256: prepared[:sha256], dimensions: prepared[:dimensions]}]

      parsed_panels = run_stage(:reader) do
        invoke_reader(
          route: "direct_ocr",
          heading: heading,
          panel_ids: [1],
          image_paths: [prepared[:path]],
          fallback_year: fallback_year,
          additional_text: additional_text
        )
      end

      admission = run_stage(:admission) do
        Admission.evaluate(parsed_panels, panel_meta: panel_meta, additional_text: additional_text)
      end

      result = build_result(
        route: "direct_ocr",
        events: admission[:events],
        review_items: admission[:review_items],
        diagnostics: {
          router: router_judgment.to_h,
          heading: heading,
          panels: admission[:panels],
          artifact_dir: artifact_dir
        },
        total_started: total_started
      )
      write_artifact_json(work_dir, "99-result.json", result)
      result
    end

    def execute_monthly_branch(original:, work_dir:, additional_text:, fallback_year:, router_judgment:, artifact_dir:, total_started:)
      geometry = run_stage(:geometry) do
        invoke_geometry(original[:path], router_judgment, work_dir)
      end

      heading = {
        heading_text: geometry.fetch("heading_text"),
        month: geometry.fetch("month"),
        year: geometry["year"] || fallback_year,
        year_source: geometry["year"] ? "printed_main_heading" : "fallback_year"
      }

      cropped_panels = run_stage(:crop) do
        crop_monthly_panels(original, geometry.fetch("panels"), work_dir)
      end

      judge_decisions = []
      panel_policies = {}
      withheld_review_items = []
      reader_panels = []

      run_stage(:judge) do
        cropped_panels.each do |panel|
          panel_result = judge_panel_miniatures(panel, heading, work_dir)
          judge_decisions.concat(panel_result[:decisions])
          panel_policies[panel[:id]] = panel_result[:banner_policy]

          if panel_result[:withhold_reason]
            withheld_review_items << {
              stage: "judge",
              group_id: panel[:id],
              title_hint: panel[:title_hint],
              reason: panel_result[:withhold_reason],
              message: panel_result[:withhold_message],
              candidate: nil,
              trace: {
                decisions: panel_result[:decisions],
                verified: false
              }
            }
          else
            reader_panels << panel.merge(
              banner_policy: panel_result[:banner_policy],
              mask_boxes: panel_result[:mask_boxes]
            )
          end
        end
      end

      prepared_reader_panels = run_stage(:crop) do
        reader_panels.map do |panel|
          final_img = ImagePrep.prepare_panel_for_reader(
            native_crop_path: panel[:native_crop][:path],
            mask_boxes: panel[:mask_boxes],
            cleanup: panel[:cleanup],
            work_dir: work_dir,
            panel_id: panel[:id],
            save_overlay: !artifact_dir.nil?,
            scale_percent: @upscale ? ImagePrep::MONTHLY_SCALE_PERCENT : "100%"
          )
          panel.merge(final_image: final_img)
        end
      end

      @hashes[:reader_inputs] = prepared_reader_panels.map do |panel|
        {
          panel_id: panel[:id],
          path: panel[:final_image][:path],
          sha256: panel[:final_image][:sha256],
          dimensions: panel[:final_image][:dimensions]
        }
      end

      admission = if prepared_reader_panels.any?
        panel_ids = prepared_reader_panels.map { |panel| panel[:id] }
        policy_payload = prepared_reader_panels.map { |panel| {id: panel[:id], banner_policy: panel[:banner_policy]} }
        parsed_panels = run_stage(:reader) do
          invoke_reader(
            route: "monthly_agenda",
            heading: heading,
            panel_ids: panel_ids,
            image_paths: prepared_reader_panels.map { |panel| panel[:final_image][:path] },
            policy_payload: policy_payload,
            fallback_year: fallback_year,
            additional_text: additional_text
          )
        end
        panel_meta = prepared_reader_panels.to_h { |panel| [panel[:id], panel] }
        run_stage(:admission) { Admission.evaluate(parsed_panels, panel_meta: panel_meta, additional_text: additional_text) }
      else
        {events: [], review_items: [], panels: []}
      end

      result = build_result(
        route: "monthly_agenda",
        events: admission[:events],
        review_items: withheld_review_items + admission[:review_items],
        diagnostics: {
          router: router_judgment.to_h,
          heading: heading,
          geometry_panels: geometry.fetch("panels").length,
          banner_policies: panel_policies.values,
          judge_decisions: judge_decisions,
          panels: admission[:panels],
          artifact_dir: artifact_dir
        },
        total_started: total_started
      )
      write_artifact_json(work_dir, "99-result.json", result)
      result
    end

    def invoke_geometry(original_path, router_judgment, work_dir)
      schema = Schemas.geometry_schema
      instructions = Prompts.geometry_instructions
      @hashes[:geometry_prompt_sha256] = Digest::SHA256.hexdigest(instructions)
      @hashes[:geometry_schema_sha256] = Digest::SHA256.hexdigest(JSON.generate(schema))

      chat = client.chat(model: @geometry_model_info.id, provider: @geometry_model_info.provider)
        .with_schema(schema)
        .with_thinking(effort: @geometry_effort)
        .with_instructions(instructions)

      started = monotonic_now
      response = chat.ask(GEOMETRY_REQUEST_PROMPT, with: attachment_for(original_path))
      elapsed = (monotonic_now - started).round(4)
      record_chat_call(stage: :geometry, model_info: @geometry_model_info, chat: chat, response: response, seconds: elapsed)

      raise GeometryError.new("Resposta de geometria incompleta: #{response.finish_reason || "unknown"}") unless response.stopped?

      geometry = parse_json_response!(response, stage: :geometry)
      validate_geometry!(geometry, router_judgment)
      write_artifact_json(work_dir, "03-geometry.json", geometry)
      geometry
    end

    def validate_geometry!(geometry, router_judgment)
      unless geometry.is_a?(Hash) && geometry["panels"].is_a?(Array) && geometry["panels"].any?
        raise GeometryError.new("Geometria sem painéis válidos")
      end

      month_choice = router_judgment.fetch("month").choice.to_s
      expected_month = Judges::MONTH_NAMES.index(month_choice) + 1
      unless geometry["month"] == expected_month
        raise GeometryError.new("Mês divergente entre router (#{expected_month}) e geometria (#{geometry["month"].inspect})")
      end

      ids = geometry["panels"].map { |panel| panel["id"] }
      unless ids.sort == (1..ids.length).to_a
        raise GeometryError.new("IDs de painéis inválidos ou duplicados: #{ids.inspect}")
      end
    end

    def crop_monthly_panels(original, panels, work_dir)
      width, height = original.fetch(:dimensions)
      panels.map do |panel|
        id = panel.fetch("id")
        native_path = File.join(work_dir, "panel-#{id}-native.png")
        cropped = ImagePrep.crop_panel(original[:path], native_path, panel.fetch("box"), width, height, panel_id: id)
        miniature_boxes = ImagePrep.map_miniatures_to_panel(
          panel.fetch("miniatures"),
          cropped.fetch(:pixel_box),
          width,
          height,
          panel_id: id
        )
        {
          id: id,
          title_hint: panel.fetch("title_hint"),
          cleanup: panel.fetch("cleanup"),
          pixel_box: cropped.fetch(:pixel_box),
          native_crop: cropped.fetch(:crop),
          miniature_pixel_boxes: miniature_boxes
        }
      end
    end

    def judge_panel_miniatures(panel, heading, work_dir)
      id = panel[:id]
      boxes = panel[:miniature_pixel_boxes]
      if boxes.empty?
        return {
          decisions: [],
          mask_boxes: [],
          banner_policy: {panel_id: id, action: "none", allowed_fields: [], masked_boxes: []}
        }
      end

      prompt = Judges.banner_prompt(heading)
      @hashes[:judge_prompt_sha256] ||= Digest::SHA256.hexdigest(prompt)

      decisions = boxes.each_with_index.map do |box, idx|
        candidate_path = File.join(work_dir, "panel-#{id}-candidate-#{idx + 1}.png")
        ImagePrep.crop_miniature(panel[:native_crop][:path], candidate_path, box, panel_id: id)

        started = monotonic_now
        judgment = Judges::BannerContextJudge.judge(
          prompt,
          with: [attachment_for(panel[:native_crop][:path]), attachment_for(candidate_path)],
          model: @judge_model_info.id,
          provider: @judge_model_info.provider,
          context: client
        )
        elapsed = (monotonic_now - started).round(4)
        record_judge_call(stage: :judge, model_info: @judge_model_info, judgment: judgment, seconds: elapsed, panel_id: id, candidate_id: idx + 1)

        answers = judgment.answers.transform_keys(&:to_s).transform_values { |answer| answer.choice.to_s }
        relationship = answers.fetch("relationship")
        main_text_overlap = answers.fetch("main_text_overlap")
        allowed_fields = %w[location time date].select { |field| answers.fetch(field) == "allow" }
        {
          panel_id: id,
          candidate_id: idx + 1,
          box: box,
          answers: answers,
          relationship: relationship,
          main_text_overlap: main_text_overlap,
          allowed_fields: allowed_fields
        }
      end

      mask_candidates = decisions.reject { |decision| decision[:answers]["action"] == "preserve" }
      mask_boxes = mask_candidates.map { |decision| decision[:box] }
      has_review = decisions.any? { |decision| decision[:answers]["action"] == "review" }
      has_preserve = decisions.any? { |decision| decision[:answers]["action"] == "preserve" }

      withhold = determine_judge_withhold(decisions)
      if withhold
        return {
          decisions: decisions,
          mask_boxes: [],
          withhold_reason: withhold[:reason],
          withhold_message: withhold[:message],
          banner_policy: {
            panel_id: id,
            action: "review",
            original_judge_action: has_review ? "review" : "mask",
            has_preserved_banner: has_preserve,
            allowed_fields: [],
            masked_boxes: []
          }
        }
      end

      allowed = decisions.select { |d| d[:answers]["action"] == "preserve" }.flat_map { |d| d[:allowed_fields] }.uniq
      effective_action = if has_review
        "mask_unverified_inset"
      elsif has_preserve
        "preserve"
      else
        "mask"
      end

      {
        decisions: decisions,
        mask_boxes: mask_boxes,
        banner_policy: {
          panel_id: id,
          action: effective_action,
          original_judge_action: has_review ? "review" : effective_action,
          has_preserved_banner: has_preserve,
          unverified_inset_masked: has_review,
          allowed_fields: allowed,
          masked_boxes: mask_boxes,
          note: has_review ? "Miniatura secundária antiga (sem sobreposição avaliada pelo Judge) foi mascarada; confirmar apenas factos explícitos, completos e coerentes no texto principal." : nil
        }.compact
      }
    end

    def determine_judge_withhold(decisions)
      if decisions.any? { |d| d[:relationship] == "uncertain_or_main_conflict" }
        return {
          reason: "uncertain_inset_relationship",
          message: "Judge identificou relação incerta, ilegível ou conflito no texto principal; painel retido para revisão."
        }
      end

      mask_targets = decisions.reject { |d| d[:answers]["action"] == "preserve" }
      if mask_targets.any? { |d| d[:main_text_overlap] != "clear_of_main_text" }
        return {
          reason: "uncertain_mask_geometry",
          message: "Judge avaliou risco de sobreposição ou apagamento de texto principal; painel retido sem mascarar."
        }
      end

      review_targets = decisions.select { |d| d[:answers]["action"] == "review" }
      if review_targets.any? { |d| d[:relationship] != "old_secondary_inset" }
        return {
          reason: "uncertain_inset_relationship",
          message: "Miniatura em revisão não é apenas uma miniatura secundária antiga e isolada; painel retido para revisão."
        }
      end

      nil
    end

    def invoke_reader(route:, heading:, panel_ids:, image_paths:, fallback_year:, additional_text:, policy_payload: nil)
      schema = Schemas.reader_schema(panel_ids, additional_text: additional_text)
      instructions = Prompts.reader_instructions(route: route, fallback_year: fallback_year)
      prompt = Prompts.build_reader_prompt(
        route: route,
        heading: heading,
        panel_ids: panel_ids,
        policy_payload: policy_payload,
        additional_text: additional_text
      )

      @hashes[:reader_prompt_sha256] = Digest::SHA256.hexdigest(instructions)
      @hashes[:reader_schema_sha256] = Digest::SHA256.hexdigest(JSON.generate(schema))

      chat = client.chat(model: @reader_model_info.id, provider: @reader_model_info.provider)
        .with_schema(schema)
        .with_thinking(effort: @reader_effort)
        .with_instructions(instructions)

      started = monotonic_now
      response = chat.ask(prompt, with: image_paths.map { |path| attachment_for(path) })
      elapsed = (monotonic_now - started).round(4)
      record_chat_call(stage: :reader, model_info: @reader_model_info, chat: chat, response: response, seconds: elapsed)

      raise WorkflowError.new("Resposta do leitor OCR incompleta: #{response.finish_reason || "unknown"}", stage: :reader) unless response.stopped?

      parsed = parse_json_response!(response, stage: :reader)
      unless parsed.is_a?(Hash) && parsed.keys == ["panels"] && parsed["panels"].is_a?(Array)
        raise WorkflowError.new("Formato de resposta OCR inválido: é esperado um objeto com panels", stage: :reader, details: parsed)
      end

      parsed.fetch("panels")
    end

    def parse_json_response!(response, stage:)
      response.parsed
    rescue JSON::ParserError => e
      raise WorkflowError.new("Erro ao analisar JSON (#{stage}): #{e.message}", stage: stage)
    end

    def record_judge_call(stage:, model_info:, judgment:, seconds:, panel_id: nil, candidate_id: nil)
      tokens = judgment.tokens.to_h
      @calls << {
        call_index: @calls.length + 1,
        stage: stage.to_s,
        panel_id: panel_id,
        candidate_id: candidate_id,
        model: judgment.model || model_info.id,
        provider: model_info.provider,
        seconds: seconds,
        tokens: tokens,
        cost: judgment.cost.to_h,
        judgment: judgment.to_h.except(:model, :tokens, :cost)
      }.compact
    end

    def record_chat_call(stage:, model_info:, chat:, response:, seconds:)
      tokens = chat.tokens.to_h
      @calls << {
        call_index: @calls.length + 1,
        stage: stage.to_s,
        model: response.model || model_info.id,
        provider: model_info.provider,
        seconds: seconds,
        tokens: tokens,
        cost: chat.cost.to_h,
        finish_reason: response.finish_reason,
        raw_text: response.content
      }
    end

    def aggregated_usage
      %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].to_h do |key|
        [key, @calls.sum { |call| call.dig(:tokens, key).to_i }]
      end
    end

    def aggregated_cost
      costs = @calls.map { |call| RubyLLM::Cost.from_h(call.fetch(:cost)) }
      RubyLLM::Cost.aggregate(costs, complete: costs.all? { |cost| !cost.total.nil? }).to_h
    end

    def build_result(route:, events:, review_items:, diagnostics:, total_started:)
      total_seconds = (monotonic_now - total_started).round(4)

      {
        route: route,
        fallback_year: @fallback_year,
        image_detail: @image_detail,
        upscale: @upscale,
        events: events,
        review_items: review_items,
        models: {
          router: @router_model_info.id,
          geometry: @geometry_model_info.id,
          geometry_effort: @geometry_effort.to_s,
          judge: @judge_model_info.id,
          reader: @reader_model_info.id,
          reader_effort: @reader_effort.to_s
        },
        hashes: @hashes,
        timing: {
          total_seconds: total_seconds,
          stages: @stage_timings.transform_keys(&:to_s)
        },
        calls: @calls,
        usage_totals: aggregated_usage,
        cost_totals: aggregated_cost,
        diagnostics: diagnostics
      }
    end

    def write_artifact_json(work_dir, filename, payload)
      return unless @artifact_dir

      File.write(File.join(work_dir, filename), JSON.pretty_generate(payload) + "\n")
    end
  end
end
