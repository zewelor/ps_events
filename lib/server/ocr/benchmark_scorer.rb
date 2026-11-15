require "date"
require "digest"
require "json"
require "ruby_llm"
require "set"
require_relative "places"

module Ocr
  module BenchmarkScorer
    STOP_WORDS = Set.new(%w[a as o os de da do das dos e no na nos nas com the em]).freeze
    PHONE_TOKEN_REGEX = /(?<!\d)(?:\+\d{1,3}[ -]?)?\d(?:[ -]?\d){5,14}(?!\d)/
    JOINED_PHONE_SEPARATOR_REGEX = %r{[/,;|]}
    NATIVE_TOKEN_KEYS = %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].freeze

    module_function

    def load_cases(cases_path, verify_sha256: true)
      payload = JSON.parse(File.read(cases_path))
      base_dir = File.dirname(cases_path)
      cases = payload.fetch("cases")

      cases.each do |entry|
        image_path = File.expand_path(entry.fetch("image"), base_dir)
        entry["resolved_image_path"] = image_path
        next unless verify_sha256 && File.file?(image_path)

        actual_sha = Digest::SHA256.file(image_path).hexdigest
        expected_sha = entry.fetch("sha256")
        if actual_sha != expected_sha
          raise "Fixture SHA256 mismatch for #{entry.fetch("id")}: expected #{expected_sha}, got #{actual_sha}"
        end
      end

      cases
    end

    def score_runs(runs, cases_path:)
      cases = load_cases(cases_path, verify_sha256: false)
      by_id = cases.to_h { |c| [c.fetch("id"), c] }
      by_image = cases.to_h { |c| [File.basename(c.fetch("image")), c] }

      scored_runs = runs.map do |raw_run|
        run = deep_symbolize(raw_run)
        case_def = find_case!(run, by_id, by_image)
        score_single_run(run, case_def)
      end

      {
        cases_path: cases_path,
        aggregates: aggregate_scores(scored_runs),
        runs: scored_runs
      }
    end

    def find_case!(run, by_id, by_image)
      case_id = run[:case_id]
      return by_id.fetch(case_id) if case_id && by_id.key?(case_id)

      image_name = File.basename(run[:image].to_s)
      return by_image.fetch(image_name) if by_image.key?(image_name)

      raise KeyError, "No case found in cases.json for case_id=#{case_id.inspect}, image=#{run[:image].inspect}"
    end

    def score_single_run(run, case_def)
      fallback_year = Integer(run[:fallback_year] || Time.now.year)
      events = Array(run[:events]).map { |event| deep_symbolize(event) }
      review_items = Array(run[:review_items]).map { |item| deep_symbolize(item) }
      error = run[:error]
      expected_route = case_def["expected_route"]
      actual_route = run[:route]

      expected = Array(case_def["expected_events"]).map { |target| expand_placeholders(target, fallback_year) }
      expected_numbers = normalized_visible_contact_numbers(case_def["visible_contact_numbers"])
      extra_contact_check = expected_numbers.any? ? 1 : 0
      timing = run[:timing] || ({total_seconds: run[:seconds], stages: {}} if run.key?(:seconds))
      usage_totals = run[:usage_totals] || run[:tokens]
      expected_fields_count = expected.sum do |target|
        checks = target.dup
        checks["end_date"] ||= target["start_date"]
        checks.length + extra_contact_check
      end
      review_candidates = Array(case_def.dig("review_candidates", "events")).map { |rc| expand_placeholders(rc, fallback_year) }
      required_omissions = flatten_required_omissions(case_def["required_omissions"], fallback_year)
      cost_summary = run_cost_summary(run)

      if error
        failed_stage = (error[:stage] || run[:stage] || "unknown").to_s
        return {
          case_id: case_def.fetch("id"),
          run: run[:run],
          fallback_year: fallback_year,
          unscored_due_to_error: true,
          failed_stage: failed_stage,
          error: error,
          expected_route: expected_route,
          actual_route: actual_route,
          route_matched: false,
          expected_events: expected.length,
          unscored_events: expected.length,
          exported_events: 0,
          matched_occurrences: 0,
          missing_occurrences: 0,
          complete_checked_events: 0,
          passed_fields: 0,
          expected_fields: expected_fields_count,
          unscored_fields: expected_fields_count,
          matched_checked_fields: 0,
          omissions: [],
          bad_fields: [],
          contact_number_checks: {total: 0, passed: 0, failed: 0, details: []},
          unmatched_extra_events: [],
          review_candidate_emissions: [],
          review_candidates_summary: {
            total: review_candidates.length,
            emitted: 0,
            in_review: 0,
            absent: 0
          },
          unscored_review_candidates: review_candidates.length,
          expected_reviews: required_omissions.length,
          unscored_reviews: required_omissions.length,
          matched_expected_reviews: 0,
          missed_expected_reviews: 0,
          unsafe_omission_emissions: [],
          review_item_count: review_items.length,
          timing: timing,
          usage_totals: usage_totals,
          cost_totals: cost_summary
        }
      end

      assignment, unmatched_indices = match_events(events, expected)

      passed_fields = 0
      matched_checked_fields = 0
      complete_checked_events = 0
      bad_fields = []
      omissions = []
      contact_details = []
      contact_passed = 0
      contact_failed = 0

      expected.each_with_index do |target, idx|
        checks = target.dup
        checks["end_date"] ||= target["start_date"]

        unless assignment.key?(idx)
          omissions << {name_contains: target["name_contains"], start_date: target["start_date"]}
          next
        end

        matched_checked_fields += checks.length + extra_contact_check
        actual = events.fetch(assignment.fetch(idx))
        failures = 0

        checks.each do |field, expected_val|
          ok, actual_val = check_field(actual, field, expected_val)
          if ok
            passed_fields += 1
          else
            failures += 1
            bad_fields << {
              event: actual[:name],
              start_date: actual[:start_date],
              field: field,
              expected: expected_val,
              actual: actual_val
            }
          end
        end

        if expected_numbers.any?
          contact_check = check_visible_contact_numbers(actual, expected_numbers)
          if contact_check[:ok]
            passed_fields += 1
            contact_passed += 1
          else
            failures += 1
            contact_failed += 1
            detail = {
              event: actual[:name],
              start_date: actual[:start_date],
              field: "visible_contact_numbers",
              reason: contact_check[:reason],
              expected: expected_numbers,
              actual: contact_check[:actual]
            }
            contact_details << detail
            bad_fields << detail
          end
        end

        complete_checked_events += 1 if failures.zero?
      end

      unmatched_events = unmatched_indices.map { |idx| events.fetch(idx) }

      rc_assignment, remaining_unmatched_indices = match_events(unmatched_events, review_candidates)
      review_candidate_emissions = rc_assignment.values.map { |idx| unmatched_events.fetch(idx) }
      unmatched_extra_events = remaining_unmatched_indices.map { |idx| unmatched_events.fetch(idx) }

      review_candidates_summary = evaluate_review_candidates(
        review_candidates: review_candidates,
        emitted_assignment: rc_assignment,
        review_items: review_items
      )

      omission_eval = evaluate_required_omissions(
        required_omissions: required_omissions,
        events: events,
        expected: expected,
        review_items: review_items
      )

      route_matched = expected_route.nil? ? nil : actual_route == expected_route

      {
        case_id: case_def.fetch("id"),
        run: run[:run],
        fallback_year: fallback_year,
        unscored_due_to_error: false,
        failed_stage: nil,
        error: nil,
        expected_route: expected_route,
        actual_route: actual_route,
        route_matched: route_matched,
        expected_events: expected.length,
        unscored_events: 0,
        exported_events: events.length,
        matched_occurrences: assignment.length,
        missing_occurrences: expected.length - assignment.length,
        complete_checked_events: complete_checked_events,
        passed_fields: passed_fields,
        expected_fields: expected_fields_count,
        unscored_fields: 0,
        matched_checked_fields: matched_checked_fields,
        omissions: omissions,
        bad_fields: bad_fields,
        contact_number_checks: {
          total: contact_passed + contact_failed,
          passed: contact_passed,
          failed: contact_failed,
          details: contact_details
        },
        unmatched_extra_events: unmatched_extra_events,
        review_candidate_emissions: review_candidate_emissions,
        review_candidates_summary: review_candidates_summary,
        unscored_review_candidates: 0,
        expected_reviews: omission_eval[:expected_reviews],
        unscored_reviews: 0,
        matched_expected_reviews: omission_eval[:matched_expected_reviews],
        missed_expected_reviews: omission_eval[:missed_expected_reviews],
        unsafe_omission_emissions: omission_eval[:unsafe_omission_emissions],
        review_item_count: review_items.length,
        timing: timing,
        usage_totals: usage_totals,
        cost_totals: cost_summary
      }
    end

    def match_events(events, targets)
      candidates = []
      targets.each_with_index do |target, i|
        target_words = Array(target["name_contains"]).each_with_object(Set.new) do |part, set|
          set.merge(semantic_words(part))
        end
        target_date = normalize_date(target["start_date"])

        events.each_with_index do |event, j|
          next unless normalize_date(event[:start_date]) == target_date

          observed = "#{event[:name]} #{event[:description]}"
          actual_words = semantic_words(observed)
          overlap = (target_words & actual_words).length.to_f / [target_words.length, 1].max
          candidates << [overlap, -i, -j, i, j] if overlap.positive?
        end
      end

      assignment = {}
      used = Set.new
      candidates.sort.reverse_each do |_overlap, _neg_i, _neg_j, i, j|
        next if assignment.key?(i) || used.include?(j)

        assignment[i] = j
        used.add(j)
      end

      unmatched_indices = (0...events.length).reject { |idx| used.include?(idx) }
      [assignment, unmatched_indices]
    end

    def check_field(actual, field, expected_val)
      case field
      when "name_contains"
        observed = "#{actual[:name]} #{actual[:description]}"
        observed_words = semantic_words(observed)
        ok = Array(expected_val).all? { |part| semantic_words(part) <= observed_words }
        [ok, actual[:name]]
      when "location_contains"
        observed = actual[:location].to_s
        ok = venue_words(expected_val) <= venue_words(observed)
        [ok, observed]
      when /\A(.+)_contains\z/
        key = Regexp.last_match(1).to_sym
        observed = actual[key].to_s
        ok = semantic_words(expected_val) <= semantic_words(observed)
        [ok, observed]
      when "start_date", "end_date"
        observed = actual[field.to_sym]
        observed = actual[:start_date] if field == "end_date" && (observed.nil? || observed.to_s.strip.empty?)
        ok = normalize_date(expected_val) == normalize_date(observed)
        [ok, observed]
      when "contact_tel"
        observed = actual[:contact_tel].to_s
        ok = observed.gsub(/\D/, "") == expected_val.to_s.gsub(/\D/, "")
        [ok, observed]
      when "contact_tel_any"
        observed = "#{actual[:contact_tel]} #{actual[:description]}"
        digits = observed.gsub(/\D/, "")
        ok = Array(expected_val).any? { |num| digits.include?(num.to_s.gsub(/\D/, "")) }
        [ok, observed]
      when "contact_email"
        observed = actual[:contact_email].to_s
        ok = observed.strip.downcase == expected_val.to_s.strip.downcase
        [ok, observed]
      else
        observed = actual[field.to_sym]
        [observed == expected_val, observed]
      end
    end

    def evaluate_review_candidates(review_candidates:, emitted_assignment:, review_items:)
      total = review_candidates.length
      return {total: 0, emitted: 0, in_review: 0, absent: 0} if total.zero?

      emitted = emitted_assignment.length
      remaining_targets = review_candidates.each_with_index.filter_map do |target, idx|
        target unless emitted_assignment.key?(idx)
      end
      in_review = match_reviews(remaining_targets, review_items).length

      {
        total: total,
        emitted: emitted,
        in_review: in_review,
        absent: total - emitted - in_review
      }
    end

    def flatten_required_omissions(raw_omissions, fallback_year)
      Array(raw_omissions).flat_map do |entry|
        if entry["reasons"].is_a?(Array)
          entry["reasons"].map do |sub|
            expand_placeholders(sub, fallback_year).merge("group" => entry["group"])
          end
        else
          [expand_placeholders(entry, fallback_year)]
        end
      end
    end

    def evaluate_required_omissions(required_omissions:, events:, expected:, review_items:)
      unsafe = []
      required_omissions.each do |omission|
        next unless omission["name_contains"]

        omission_words = identity_words(omission["name_contains"])
        events.each do |event|
          date_ok = omission["start_date"].nil? || normalize_date(event[:start_date]) == normalize_date(omission["start_date"])
          next unless date_ok

          name_match = omission_words <= semantic_words(event[:name])
          description_match = omission_words <= semantic_words("#{event[:name]} #{event[:description]}")
          unsafe_match = name_match || (description_match && !identified_subevent?(event, expected))
          next unless unsafe_match

          unsafe << {expected_omission: omission["name_contains"], emitted_event: event[:name], start_date: event[:start_date]}
        end
      end

      matched = match_reviews(required_omissions, review_items).length
      {
        expected_reviews: required_omissions.length,
        matched_expected_reviews: matched,
        missed_expected_reviews: required_omissions.length - matched,
        unsafe_omission_emissions: unsafe
      }
    end

    def identified_subevent?(event, expected)
      expected.any? do |target|
        words = identity_words(target["name_contains"])
        !words.empty? && words <= semantic_words(event[:name]) &&
          matching_valid_date?(target["start_date"], event[:start_date])
      end
    end

    # Assign each review to at most one target, including when target identities overlap.
    def match_reviews(targets, review_items)
      assigned = {}
      visit = lambda do |target_index, seen|
        review_items.each_index do |item_index|
          next if seen.include?(item_index) || !review_item_matches_target?(review_items[item_index], targets[target_index])

          seen.add(item_index)
          if !assigned.key?(item_index) || visit.call(assigned[item_index], seen)
            assigned[item_index] = target_index
            return true
          end
        end
        false
      end
      targets.each_index { |idx| visit.call(idx, Set.new) }
      assigned
    end

    def identity_words(parts)
      Array(parts).each_with_object(Set.new) { |part, words| words.merge(semantic_words(part)) }
    end

    def review_item_matches_target?(item, target)
      return item[:reason].to_s == target["reason"].to_s unless target["name_contains"]

      candidate = item[:candidate] || {}
      words = identity_words(target["name_contains"])
      return false if words.empty?

      candidate_words = semantic_words("#{candidate[:name]} #{candidate[:description]}")
      dated = target["start_date"] || target["end_date"]
      identity_match = words <= candidate_words
      identity_match ||= !dated && candidate_words.empty? && words <= semantic_words(item[:title_hint])
      return false unless identity_match

      %w[start_date end_date].all? do |field|
        !target[field] || matching_valid_date?(target[field], candidate[field.to_sym])
      end
    end

    def matching_valid_date?(expected, actual)
      date = normalize_date(expected)
      date && !date.start_with?("INVALID:") && date == normalize_date(actual)
    end

    def expand_placeholders(hash, fallback_year)
      hash.transform_values do |value|
        case value
        when String
          value.gsub("{fallback_year}", fallback_year.to_s)
        when Array
          value.map { |v| v.is_a?(String) ? v.gsub("{fallback_year}", fallback_year.to_s) : v }
        else
          value
        end
      end
    end

    def semantic_words(value)
      text = value.to_s.unicode_normalize(:nfkd)
      text = text.gsub(/\p{Mn}|\p{Cf}/, "").downcase.delete(".")
      text = text
        .gsub(/\bsc\s+portosantense\b/, "sport clube portosantense")
        .gsub(/\bcmps\b/, "camara municipal")
        .gsub("colombus", "columbus")
        .gsub("sunday", "sun day")
        .gsub("trio va", "triova")

      tokens = text.scan(/[a-z0-9]+/).map do |word|
        case word
        when "golfe" then "golf"
        when "comemoracoes" then "comemoracao"
        when "descobertas" then "descoberta"
        else word
        end
      end

      Set.new(tokens) - STOP_WORDS
    end

    def venue_words(value)
      canonical = Places.canonical_location(value) || value
      semantic_words(canonical)
    end

    def normalize_date(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Date.strptime(value.to_s.strip, "%d/%m/%Y").iso8601
    rescue ArgumentError
      "INVALID:#{value}"
    end

    def normalized_visible_contact_numbers(raw_numbers)
      Array(raw_numbers).map { |num| num.to_s.gsub(/\D/, "") }.reject(&:empty?).uniq
    end

    def extract_phone_numbers(text)
      text.to_s.scan(PHONE_TOKEN_REGEX).map { |token| token.gsub(/\D/, "") }.reject(&:empty?)
    end

    def check_visible_contact_numbers(actual, expected_numbers)
      contact_tel_raw = actual[:contact_tel].to_s.strip
      tel_numbers = extract_phone_numbers(contact_tel_raw)
      desc_numbers = extract_phone_numbers(actual[:description])

      if tel_numbers.length > 1 || contact_tel_raw.match?(JOINED_PHONE_SEPARATOR_REGEX)
        return {ok: false, reason: "joined_contact_tel", actual: {contact_tel: contact_tel_raw, description: actual[:description]}}
      end

      if tel_numbers.empty?
        return {ok: false, reason: "missing_contact_tel", actual: {contact_tel: actual[:contact_tel], description: actual[:description]}}
      end

      unless expected_numbers.include?(tel_numbers.first)
        return {ok: false, reason: "unexpected_contact_tel", actual: {contact_tel: contact_tel_raw, description: actual[:description]}}
      end

      fabricated = (tel_numbers + desc_numbers).uniq - expected_numbers
      if fabricated.any?
        return {ok: false, reason: "fabricated_contact_numbers", actual: {contact_tel: contact_tel_raw, unexpected: fabricated}}
      end

      missing_in_description = (expected_numbers - tel_numbers) - desc_numbers
      if missing_in_description.any?
        return {ok: false, reason: "missing_description_numbers", actual: {contact_tel: contact_tel_raw, missing: missing_in_description}}
      end

      {ok: true}
    end

    def run_cost_summary(run)
      calls = Array(run[:calls])
      cost_totals = run[:cost_totals].is_a?(Hash) ? run[:cost_totals] : {}
      usage_totals = run[:usage_totals].is_a?(Hash) ? run[:usage_totals] : {}

      if calls.any?
        summaries = calls.map { |call| call_cost_summary(call) }
        unknown_calls = summaries.count { |summary| !summary[:known] }
        known_costs = summaries.filter_map { |summary| summary[:known_cost] if summary[:known] }
        cold_costs = summaries.filter_map { |summary| summary[:cold_cost] if summary[:cold_known] }
        incomplete_status = !run[:error].nil? || %w[partial unknown].include?(cost_totals[:status].to_s)
        status = if known_costs.empty?
          "unknown"
        elsif unknown_calls.positive? || incomplete_status || summaries.any? { |summary| !summary[:cold_known] }
          "partial"
        else
          "complete"
        end
        return {
          status: status,
          usage_available: status != "unknown",
          calls_count: calls.length,
          unknown_cost_calls: unknown_calls,
          known_cost_usd: known_costs.empty? ? nil : known_costs.sum.round(8),
          cold_cost_usd: cold_costs.empty? ? nil : cold_costs.sum.round(8)
        }
      end

      legacy_aggregate_cost_summary(run, cost_totals, usage_totals)
    end

    def call_cost_summary(call)
      return {known: false, known_cost: nil, cold_known: false, cold_cost: nil} unless call.is_a?(Hash)

      cost = call[:cost]
      return {known: false, known_cost: nil, cold_known: false, cold_cost: nil} unless cost.is_a?(Hash)

      if %i[known_cost_usd cold_cost_usd usage_available].any? { |key| cost.key?(key) }
        known = cost[:usage_available] != false
        accounted = cost[:usage_available]
        return {
          known: known,
          known_cost: accounted ? cost[:known_cost_usd].to_f : 0.0,
          cold_known: known,
          cold_cost: accounted ? cost[:cold_cost_usd].to_f : 0.0
        }
      end

      total = RubyLLM::Cost.from_h(cost).total
      cold_cost = cold_cost_for(call)
      {
        known: !total.nil?,
        known_cost: total,
        cold_known: !cold_cost.nil?,
        cold_cost: cold_cost
      }
    end

    def cold_cost_for(call)
      token_data = call[:tokens]
      return nil unless token_data.is_a?(Hash)
      return nil if NATIVE_TOKEN_KEYS.any? { |key| !token_data.key?(key) || token_data[key].nil? }
      return 0.0 if NATIVE_TOKEN_KEYS.all? { |key| token_data[key].zero? }

      model_id = call[:model]
      provider = call[:provider]
      return nil if model_id.to_s.empty? || provider.to_s.empty?

      model = RubyLLM.models.find(model_id.to_s, provider: provider.to_s)
      # The benchmark's cold-cost scenario is hypothetical: cache reads become new writes.
      hypothetical_tokens = RubyLLM::Tokens.new(
        input: token_data[:input_tokens],
        output: token_data[:output_tokens],
        cache_read: 0,
        cache_write: token_data[:cache_read_tokens] + token_data[:cache_write_tokens],
        thinking: token_data[:thinking_tokens]
      )
      model.cost_for(hypothetical_tokens).total
    rescue RubyLLM::ModelNotFoundError
      nil
    end

    def legacy_aggregate_cost_summary(run, cost_totals, usage_totals)
      explicit_known = cost_totals[:known_cost_usd]
      explicit_cold = cost_totals[:cold_cost_usd]
      has_nonzero_usage = usage_totals.values.any? { |v| v.to_i.positive? }
      explicit_unknown = cost_totals[:usage_available] == false || cost_totals[:status].to_s == "unknown"

      if !run[:error].nil? || explicit_unknown || (!has_nonzero_usage && explicit_known.to_f.zero? && explicit_cold.to_f.zero?)
        {
          status: "unknown",
          usage_available: false,
          calls_count: 0,
          unknown_cost_calls: cost_totals[:unknown_cost_calls].to_i,
          known_cost_usd: nil,
          cold_cost_usd: nil
        }
      else
        {
          status: cost_totals[:status]&.to_s || "complete",
          usage_available: true,
          calls_count: cost_totals[:calls_count].to_i,
          unknown_cost_calls: cost_totals[:unknown_cost_calls].to_i,
          known_cost_usd: explicit_known&.to_f&.round(8),
          cold_cost_usd: explicit_cold&.to_f&.round(8)
        }
      end
    end

    def aggregate_scores(scored_runs)
      errored, scored = scored_runs.partition { |r| r[:unscored_due_to_error] }

      errors_by_stage = Hash.new(0)
      errored.each do |r|
        stage = r[:failed_stage] || "unknown"
        errors_by_stage[stage] += 1
      end

      stage_seconds = Hash.new(0.0)
      scored_runs.each do |r|
        stages = r.dig(:timing, :stages) || {}
        stages.each { |stage, secs| stage_seconds[stage.to_s] += secs.to_f }
      end

      cost_entries = scored_runs.map { |r| r[:cost_totals] || {} }
      unknown_cost_calls = cost_entries.sum { |c| c[:unknown_cost_calls].to_i }
      calls_count = cost_entries.sum { |c| c[:calls_count].to_i }
      runs_with_unknown_cost = cost_entries.count { |c| c[:status] != "complete" }
      any_known_cost = cost_entries.any? { |c| !c[:known_cost_usd].nil? }
      cost_status = if scored_runs.any? && runs_with_unknown_cost.zero? && unknown_cost_calls.zero? && errored.empty?
        "complete"
      elsif !any_known_cost
        "unknown"
      else
        "partial"
      end

      {
        runs: scored_runs.length,
        scored_runs: scored.length,
        successful_runs: scored.length,
        failed_runs: errored.length,
        errors_by_stage: errors_by_stage,
        route_evaluated_runs: scored.count { |r| !r[:expected_route].nil? },
        route_matches: scored.count { |r| r[:route_matched] },
        total_expected_events: scored_runs.sum { |r| r[:expected_events] },
        unscored_due_to_error_events: errored.sum { |r| r[:unscored_events] },
        expected_events: scored.sum { |r| r[:expected_events] },
        exported_events: scored.sum { |r| r[:exported_events] },
        matched_occurrences: scored.sum { |r| r[:matched_occurrences] },
        missing_occurrences: scored.sum { |r| r[:missing_occurrences] },
        complete_checked_events: scored.sum { |r| r[:complete_checked_events] },
        passed_fields: scored.sum { |r| r[:passed_fields] },
        expected_fields: scored.sum { |r| r[:expected_fields] },
        unscored_due_to_error_fields: errored.sum { |r| r[:unscored_fields] },
        matched_checked_fields: scored.sum { |r| r[:matched_checked_fields] },
        bad_field_count: scored.sum { |r| r[:bad_fields].length },
        contact_number_checks: {
          total: scored.sum { |r| r.dig(:contact_number_checks, :total).to_i },
          passed: scored.sum { |r| r.dig(:contact_number_checks, :passed).to_i },
          failed: scored.sum { |r| r.dig(:contact_number_checks, :failed).to_i }
        },
        unmatched_extra_count: scored.sum { |r| r[:unmatched_extra_events].length },
        total_expected_reviews: scored_runs.sum { |r| r[:expected_reviews] },
        unscored_due_to_error_reviews: errored.sum { |r| r[:unscored_reviews] },
        expected_reviews: scored.sum { |r| r[:expected_reviews] },
        matched_expected_reviews: scored.sum { |r| r[:matched_expected_reviews] },
        missed_expected_reviews: scored.sum { |r| r[:missed_expected_reviews] },
        unsafe_omission_emission_count: scored.sum { |r| r[:unsafe_omission_emissions].length },
        review_candidates: {
          total: scored.sum { |r| r.dig(:review_candidates_summary, :total) },
          unscored_due_to_error: errored.sum { |r| r[:unscored_review_candidates].to_i },
          emitted: scored.sum { |r| r.dig(:review_candidates_summary, :emitted) },
          in_review: scored.sum { |r| r.dig(:review_candidates_summary, :in_review) },
          absent: scored.sum { |r| r.dig(:review_candidates_summary, :absent) }
        },
        total_seconds: scored_runs.sum { |r| r.dig(:timing, :total_seconds).to_f }.round(4),
        stage_seconds: stage_seconds.transform_values { |v| v.round(4) },
        usage_totals: %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].to_h do |k|
          [k, scored_runs.sum { |r| r.dig(:usage_totals, k).to_i }]
        end,
        cost_totals: {
          status: cost_status,
          verified: cost_status == "complete",
          calls_count: calls_count,
          unknown_cost_calls: unknown_cost_calls,
          runs_with_unknown_cost: runs_with_unknown_cost,
          known_cost_usd: (cost_status == "unknown") ? nil : cost_entries.sum { |c| c[:known_cost_usd].to_f }.round(8),
          cold_cost_usd: (cost_status == "unknown") ? nil : cost_entries.sum { |c| c[:cold_cost_usd].to_f }.round(8)
        }
      }
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = deep_symbolize(v) }
      when Array
        value.map { |item| deep_symbolize(item) }
      else
        value
      end
    end
  end
end
