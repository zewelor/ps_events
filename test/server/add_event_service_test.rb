require "minitest/autorun"
require "active_support"
require_relative "../../lib/server/add_event_service"
require_relative "../../lib/server/event_validation_error"
require_relative "../fixtures/memory_sheets"

class AddEventServiceTest < Minitest::Test
  def setup
    @sheets = MemorySheets.new
    @service = AddEventService.new(google_sheets: @sheets, spreadsheet_id: "test-sheet", events_range: "Events!A:S")
    @event = {
      name: "Concerto de teste",
      start_date: "9/10/2026",
      start_time: "18:00",
      end_date: "09/10/2026",
      end_time: "20:00",
      location: "Largo do Pelourinho",
      description: "Concerto de teste com entrada gratuita.",
      category: "Música",
      organizer: "Organização de teste"
    }
  end

  def test_valid_dates_are_appended_without_changing_their_format
    %w[9/1/2026 09/1/2026 9/01/2026 09/01/2026].each do |date|
      setup
      capture_io do
        @service.add_event(@event.merge(start_date: date, end_date: date), submitter_email: "test@example.com")
      end

      assert_equal [date, date], @sheets.rows.last.values_at(3, 5)
    end
  end

  def save(event = @event, **options)
    result = nil
    capture_io { result = @service.add_event(event, submitter_email: "test@example.com", **options) }
    result
  end

  def test_equivalent_replay_ignores_metadata_and_normalizes_dates_case_and_whitespace
    original = save(image_path: "original.webp")
    replay = save(@event.merge(name: "  CONCERTO   DE TESTE ", start_date: "09/10/2026"), image_path: "new-uuid.webp")

    assert_equal "added", original[:status]
    assert_equal "skipped", replay[:status]
    assert_equal "Events!A2:S2", replay[:existing_row]
    assert_equal 1, @sheets.rows.size
  end

  def test_material_differences_are_conflicts_with_existing_data
    save
    result = save(@event.merge(start_time: "19:00", location: "Biblioteca Municipal"))

    assert_equal "conflict", result[:status]
    assert_equal "19:00", result[:event][:start_time]
    candidate = result[:candidates].first
    assert_equal "Events!A2:S2", candidate[:reference]
    assert_includes candidate[:differences], :start_time
    assert_includes candidate[:differences], :location
    assert_equal "18:00", candidate[:event][:start_time]
    assert_equal 1, @sheets.rows.size
  end

  def test_changed_name_category_and_venue_still_produce_review_candidates_on_same_day
    save
    result = save(@event.merge(name: "Apresentação de música", category: "Arte", location: "Outro local"))

    assert_equal "conflict", result[:status]
    assert_equal 1, @sheets.rows.size
  end

  def test_other_dates_remain_separate_and_in_request_replays_are_skipped
    results = [@event, @event.merge(start_date: "10/10/2026", end_date: "10/10/2026"), @event].map { |event| save(event) }

    assert_equal %w[added added skipped], results.map { |result| result[:status] }
    assert_equal 2, @sheets.rows.size
    assert_equal 1, @sheets.reads.count("Approved!A:S")
  end

  def test_approved_is_checked_even_when_target_is_another_tab
    save
    @sheets.approved_rows << @sheets.rows.pop
    @service = AddEventService.new(google_sheets: @sheets, spreadsheet_id: "test-sheet", events_range: "Events!A:O")

    result = save

    assert_equal "skipped", result[:status]
    assert_equal "Approved!A2:S2", result[:existing_row]
    assert_empty @sheets.rows
  end

  def test_reordered_headers_are_used_for_reading_and_appending
    @sheets.headers.reverse!
    save

    assert_equal @event[:name], @sheets.rows.first[@sheets.headers.index("name")]
    assert_equal "skipped", save[:status]
  end

  def test_live_read_failure_never_appends
    @sheets.read_error = "Sheets unavailable"

    capture_io { assert_raises(StandardError) { @service.add_event(@event, submitter_email: "test@example.com") } }

    assert_empty @sheets.rows
  end

  def test_missing_headers_fail_closed
    @sheets.headers.delete("name")

    capture_io { assert_raises(StandardError) { @service.add_event(@event, submitter_email: "test@example.com") } }

    assert_empty @sheets.rows
  end

  def test_distinct_occurrence_requires_acknowledging_the_actual_candidate
    save
    incoming = @event.merge(start_time: "19:00")
    conflict = save(incoming)
    result = save(incoming, distinct_from: conflict[:candidates].map { |candidate| candidate[:fingerprint] })

    assert_equal "added", result[:status]
    assert_equal 2, @sheets.rows.size
    assert_equal "skipped", save(incoming)[:status]
  end

  def test_acknowledgement_is_invalid_when_input_changes
    save
    conflict = save(@event.merge(start_time: "19:00"))
    result = save(@event.merge(location: "Outro local"), distinct_from: conflict[:candidates].map { |candidate| candidate[:fingerprint] })

    assert_equal "conflict", result[:status]
    assert_equal 1, @sheets.rows.size
  end

  def test_tournament_already_in_aggregate_description_reaches_review
    aggregate = @event.merge(name: "Porto Santo Golfe", start_date: "1/11/2026", end_date: "29/11/2026", location: "Porto Santo Golfe", description: "14 - Torneio Vila Baleira.", category: "Desporto")
    save(aggregate)
    tournament = aggregate.merge(name: "Torneio Vila Baleira", start_date: "14/11/2026", end_date: "14/11/2026")
    result = save(tournament)

    assert_equal "conflict", result[:status]
    assert_equal aggregate[:description], result[:candidates].first[:event][:description]
    assert_equal 1, @sheets.rows.size
  end

  def test_lost_append_response_is_reconciled_from_live_data_before_retry
    real_append = @sheets.method(:append_row)
    @sheets.define_singleton_method(:append_row) do |*arguments|
      real_append.call(*arguments)
      raise "Response lost"
    end
    capture_io { assert_raises(RuntimeError) { @service.add_event(@event, submitter_email: "test@example.com") } }

    assert_equal "skipped", save[:status]
    assert_equal 1, @sheets.rows.size
  end

  def test_duplicate_does_not_publish_another_image
    save
    published = false
    capture_io { @service.add_event(@event, submitter_email: "test@example.com") { published = true } }

    refute published
  end

  def test_named_range_with_shifted_header_preserves_real_row_reference
    save
    stored_row = @sheets.rows.pop
    requested = []
    read = @sheets.method(:get_values)
    @sheets.define_singleton_method(:get_values) do |id, range|
      requested << range
      if range == "Approved!A:S"
        read.call(id, range)
      else
        MemorySheets::Response.new("'Events ! 2026'!B10:T11", [headers, stored_row])
      end
    end
    @service = AddEventService.new(google_sheets: @sheets, spreadsheet_id: "test-sheet", events_range: "EventTable")

    result = save

    assert_equal "skipped", result[:status]
    assert_equal "'Events ! 2026'!B11:T11", result[:existing_row]
    assert_includes requested, "'Events ! 2026'!B10:T"
  end

  def test_invalid_dates_never_reach_the_sheet
    %i[start_date end_date].each do |field|
      ["09/10/26", "09/10/2026junk", "09/10/2026\njunk", "31/02/2026"].each do |date|
        error = nil
        capture_io do
          error = assert_raises(EventValidationError) do
            @service.add_event(@event.merge(field => date), submitter_email: "test@example.com")
          end
        end

        assert error.validation_errors.key?(field), "Expected #{field} error for #{date.inspect}"
        assert_empty @sheets.rows
      end
    end
  end

  def test_same_day_time_order_is_checked_across_different_date_padding
    capture_io do
      error = assert_raises(EventValidationError) do
        @service.add_event(@event.merge(end_time: "17:00"), submitter_email: "test@example.com")
      end
      assert error.validation_errors.key?(:end_time)
    end

    assert_empty @sheets.rows
  end

  def test_other_event_validation_errors_also_prevent_an_append
    capture_io do
      error = assert_raises(EventValidationError) do
        @service.add_event(@event.merge(category: "Unknown"), submitter_email: "test@example.com")
      end
      assert error.validation_errors.key?(:category)
    end

    assert_empty @sheets.rows
  end
end
