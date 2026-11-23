require "bundler/setup"
require "minitest/autorun"
require_relative "../test_helper"
require_relative "../../lib/server/ocr/targeted_repair"

class OcrTargetedRepairTest < Minitest::Test
  def setup
    @event = {"name" => "Concerto", "start_date" => "01/01/2026", "end_date" => "03/01/2026", "location" => "Auditório", "description" => "Um concerto de música.", "category" => "Música"}
    @report = {status: "advisory", events: [@event], review_items: [], questions: [{id: "q1", record_id: "event:1", field: "date_range", answer: {choice: "unsupported"}}]}
  end

  def test_grouped_proposals_are_validated_and_original_is_unchanged
    original_event = @event.dup
    calls = []
    repairer = ->(input, image) {
      calls << [input, image]
      {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Duas datas", "rows" => [[{"field" => "end_date", "value" => "01/01/2026"}, {"field" => "description", "value" => "Um concerto no primeiro dia."}], [{"field" => "start_date", "value" => "03/01/2026"}]]}]}
    }
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "source.png", context: "caption")
    assert_equal 1, calls.length
    assert_equal "source.png", calls.first.last
    assert_empty result.fetch(:questions_without_proposal)
    rows = result.fetch(:proposals).first.fetch(:rows)
    dates = rows.map { |row| row[:event].values_at("start_date", "end_date") }
    assert_equal [["01/01/2026", "01/01/2026"], ["03/01/2026", "03/01/2026"]], dates
    assert_equal "Um concerto no primeiro dia.", rows.first[:event]["description"]
    rows.each { |row| assert_empty row.fetch(:errors) }
    assert_equal original_event, @event
  end

  def test_invalid_and_unauthorized_proposals_fail_visibly
    repairer = ->(_input, _image) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "text", "rows" => [[{"field" => "location", "value" => "Elsewhere"}]]}]} }
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")
    assert_equal "technical_failure", result[:status]
    assert_match(/field/, result.dig(:error, :message))
  end

  def test_unsupported_missing_field_does_not_call_repair
    @report[:questions] = [{id: "q1", record_id: "event:1", field: "missing_location", answer: {choice: "unsupported"}}]
    result = Ocr::TargetedRepair.new(repairer: ->(*) { flunk "unexpected call" }).call(@report, image: "x", context: "x")
    assert_equal "not_needed", result[:status]
  end

  def test_missing_location_repair_validates_held_candidate_with_absent_optional_fields
    @report[:events] = []
    @report[:review_items] = [{"candidate" => @event.merge("location" => nil, "contact_tel" => nil)}]
    @report[:questions] = [{id: "q1", record_id: "review:1", field: "missing_location", answer: {choice: "supported"}}]
    repairer = ->(*) { {"proposals" => [{"record_id" => "review:1", "question_ids" => ["q1"], "evidence" => "no Auditório", "rows" => [[{"field" => "location", "value" => "Auditório"}]]}]} }
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "caption")
    assert_empty result.fetch(:proposals).first.fetch(:rows).first.fetch(:errors)
  end

  def test_native_choice_symbols_route_claims_and_missing_fields
    @report[:questions] = [
      {id: "q1", record_id: "event:1", field: "date_range", answer: {choice: :supported}},
      {id: "q2", record_id: "event:1", field: "missing_start_time", answer: {choice: :supported}}
    ]
    asked = nil
    repairer = lambda do |input, _image|
      asked = input[:questions].map { |question| question[:id] }
      {"proposals" => []}
    end
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "sent.jpg", context: "caption")
    assert_equal ["q2"], asked
    assert_equal ["q2"], result[:questions_without_proposal]
  end

  def test_partial_repair_leaves_questions_without_edits_pending
    @report[:events] = []
    @report[:review_items] = [{"candidate" => @event.merge("location" => nil, "organizer" => "Porta 33")}]
    @report[:questions] = [
      {id: "q1", record_id: "review:1", field: "missing_location", answer: {choice: "supported"}},
      {id: "q2", record_id: "review:1", field: "organizer", answer: {choice: "unsupported"}},
      {id: "q3", record_id: "review:1", field: "date_range", answer: {choice: "unsupported"}}
    ]
    repairer = ->(*) {
      {"proposals" => [{"record_id" => "review:1", "question_ids" => %w[q1 q2 q3], "evidence" => "Porta 33 apresenta o concerto", "rows" => [[
        {"field" => "organizer", "value" => ""},
        {"field" => "end_date", "value" => "03/01/2026"}
      ]]}]}
    }

    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "caption")

    assert_equal %w[q1 q3], result.fetch(:questions_without_proposal)
    proposal = result.fetch(:proposals).first
    assert_equal ["q2"], proposal.fetch(:question_ids)
    assert_equal "", proposal.fetch(:rows).first.dig(:event, "organizer")
  end

  def test_invalid_proposed_row_and_timeout_are_visible
    repairer = ->(*) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Data", "rows" => [[{"field" => "end_date", "value" => "invalid"}]]}]} }
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")
    refute_empty result[:proposals][0][:rows][0][:errors]
    failure = Ocr::TargetedRepair.new(repairer: ->(*) { raise Timeout::Error, "timed out" }).call(@report, image: "x", context: "x")
    assert_equal "technical_failure", failure[:status]
    assert_equal "timed out", failure.dig(:error, :message)
  end

  def test_date_range_requires_a_changed_usable_interval
    cases = [
      [[[{"field" => "start_time", "value" => "20:00"}]], false],
      [[[{"field" => "description", "value" => "Primeiro dia"}], [{"field" => "description", "value" => "Segundo dia"}]], false],
      [[[{"field" => "start_date", "value" => "1/1/2026"}]], false],
      [[[{"field" => "end_date", "value" => "invalid"}]], false],
      [[[{"field" => "end_date", "value" => " "}]], false],
      [[[{"field" => "end_date", "value" => "31/12/2025"}]], false],
      [[[{"field" => "end_date", "value" => "01/01/2026"}], [{"field" => "start_date", "value" => "31/02/2026"}]], false],
      [[[{"field" => "end_date", "value" => "01/01/2026"}], [{"field" => "description", "value" => "Segundo dia"}]], false],
      [Array.new(2) { [{"field" => "end_date", "value" => "01/01/2026"}] }, false],
      [[[{"field" => "end_date", "value" => "02/01/2026"}]], true]
    ]
    cases.each do |rows, addressed|
      repairer = ->(*) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Fonte", "rows" => rows}]} }
      result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")
      assert_equal addressed ? [] : ["q1"], result.fetch(:questions_without_proposal), rows.inspect
    end
  end

  def test_missing_start_fields_respect_the_end_of_the_event_despite_unrelated_errors
    cases = [
      ["start_date", {"start_date" => nil, "end_date" => "01/01/2026"}, "02/01/2026", ["q1"]],
      ["start_time", {"end_date" => "01/01/2026", "end_time" => "21:00"}, "22:00", ["q1"]],
      ["start_time", {"end_date" => "02/01/2026", "end_time" => "01:00"}, "22:00", []]
    ]
    cases.each do |field, original, proposed, pending|
      event = @event.merge(original, "category" => "invalid")
      report = @report.merge(events: [event], questions: [{id: "q1", record_id: "event:1", field: "missing_#{field}", answer: {choice: "supported"}}])
      repairer = ->(*) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Fonte", "rows" => [[{"field" => field, "value" => proposed}]]}]} }

      result = Ocr::TargetedRepair.new(repairer: repairer).call(report, image: "x", context: "x")

      assert_equal pending, result.fetch(:questions_without_proposal), original.inspect
    end
  end

  def test_blank_end_date_equals_the_start_date
    @event["end_date"] = "01/01/2026"
    repairer = ->(*) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Fonte", "rows" => [[{"field" => "end_date", "value" => ""}]]}]} }
    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")
    assert_equal ["q1"], result.fetch(:questions_without_proposal)
  end

  def test_invalid_role_edits_stay_pending_and_valid_edits_are_independent
    @event["organizer"] = "Porta 33"
    @event["category"] = "invalid"
    @report[:questions] = [
      {id: "q1", record_id: "event:1", field: "organizer", answer: {choice: "unsupported"}},
      {id: "q2", record_id: "event:1", field: "description_role", answer: {choice: "unsupported"}}
    ]
    [
      ["   ", "Concerto apresentado pela Porta 33.", ["q1"]],
      ["", "", ["q2"]]
    ].each do |organizer, description, pending|
      repairer = ->(*) {
        {"proposals" => [{"record_id" => "event:1", "question_ids" => %w[q1 q2], "evidence" => "Porta 33 apresenta o concerto", "rows" => [[
          {"field" => "organizer", "value" => organizer}, {"field" => "description", "value" => description}
        ]]}]}
      }

      result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")

      assert_equal pending, result.fetch(:questions_without_proposal)
      assert result.dig(:proposals, 0, :rows, 0, :errors).key?(:category)
    end
  end

  def test_split_missing_start_time_requires_a_usable_value_in_each_row
    @report[:questions] << {id: "q2", record_id: "event:1", field: "missing_start_time", answer: {choice: "supported"}}
    repairer = ->(*) {
      {"proposals" => [{"record_id" => "event:1", "question_ids" => %w[q1 q2], "evidence" => "Dois concertos", "rows" => [
        [{"field" => "end_date", "value" => "01/01/2026"}, {"field" => "start_time", "value" => "20:00"}],
        [{"field" => "start_date", "value" => "03/01/2026"}]
      ]}]}
    }

    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")

    assert_equal ["q2"], result.fetch(:questions_without_proposal)
  end

  def test_split_does_not_hide_an_invalid_organizer_edit
    @event["organizer"] = "Porta 33"
    @report[:questions] << {id: "q2", record_id: "event:1", field: "organizer", answer: {choice: "unsupported"}}
    repairer = ->(*) {
      {"proposals" => [{"record_id" => "event:1", "question_ids" => %w[q1 q2], "evidence" => "Dois concertos", "rows" => [
        [{"field" => "end_date", "value" => "01/01/2026"}, {"field" => "organizer", "value" => ""}],
        [{"field" => "start_date", "value" => "03/01/2026"}, {"field" => "organizer", "value" => "   "}]
      ]}]}
    }

    result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")

    assert_equal ["q2"], result.fetch(:questions_without_proposal)
  end

  def test_missing_fields_remain_pending_for_blank_or_invalid_values_despite_unrelated_errors
    {"missing_start_date" => ["start_date", ["", "31/02/2026"], "02/01/2026"],
     "missing_start_time" => ["start_time", [" ", "99:99"], "20:00"],
     "missing_location" => ["location", [" ", "ab"], "Auditório"]}.each do |question, (field, invalid, valid)|
      @event[field] = nil
      @event["category"] = "invalid"
      @report[:questions] = [{id: "q1", record_id: "event:1", field: question, answer: {choice: "supported"}}]
      (invalid + [valid]).each do |value|
        repairer = ->(*) { {"proposals" => [{"record_id" => "event:1", "question_ids" => ["q1"], "evidence" => "Fonte", "rows" => [[{"field" => field, "value" => value}]]}]} }
        result = Ocr::TargetedRepair.new(repairer: repairer).call(@report, image: "x", context: "x")
        assert_equal((value == valid) ? [] : ["q1"], result.fetch(:questions_without_proposal), "#{field}: #{value.inspect}")
        assert result.fetch(:proposals).first.fetch(:rows).first.fetch(:errors).key?(:category)
      end
    end
  end
end
