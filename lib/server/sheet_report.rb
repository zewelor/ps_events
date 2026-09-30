require_relative "sheet_investigator"

# Renders SheetInvestigator findings as plain text.
#
# Kept apart from SheetInvestigator so that querying the sheet and presenting
# the results stay separate concerns, and so the output can be asserted in tests
# without capturing stdout.
class SheetReport
  # "%s" (not "%d") so the same format serves both the header and the rows.
  ROW_FORMAT = "%4s | %-25s | %-46s | %-34s | %-22s | %-8s | %s"
  TABLE_HEADERS = %w[row dates name location category image submitted_by].freeze

  def initialize(investigator)
    @investigator = investigator
  end

  def events_table(events, limit:)
    lines = [format(ROW_FORMAT, *TABLE_HEADERS)]
    events.first(limit).each { |event| lines << format(ROW_FORMAT, *event_cells(event)) }
    lines << ""
    lines << "Showing #{[events.size, limit].min} of #{events.size} matching events " \
             "(#{@investigator.all.size} rows in the sheet)."
    lines.join("\n")
  end

  def duplicates_section(events = @investigator.all)
    [
      section("Exact duplicates (same name + start date)", @investigator.exact_duplicates(events)),
      section(
        "Suspicious duplicates (same day + place + category, different name)",
        @investigator.suspicious_duplicates(events)
      )
    ].join("\n\n")
  end

  def invalid_section(events = @investigator.all)
    failures = @investigator.validation_failures(events)
    return "== Schema violations ==\n  none" if failures.empty?

    lines = ["== Schema violations =="]
    failures.each do |event, errors|
      lines << "  row #{event.row_number}: #{event.name}"
      errors.each do |field, messages|
        messages.uniq.each { |message| lines << "    #{field}: #{describe(message)}" }
      end
    end
    lines.join("\n")
  end

  private

  # json-schema appends a schema UUID to every message, which is pure noise here.
  def describe(message)
    message.to_s.sub(/ in schema [0-9a-f-]+\z/, "")
  end

  def section(title, groups)
    return "== #{title} ==\n  none" if groups.empty?

    lines = ["== #{title} =="]
    groups.each_with_index do |group, index|
      lines << "" if index.positive?
      group.sort_by(&:row_number).each do |event|
        lines << "  row #{event.row_number} | #{event.date_range} | #{event.name} | #{event.location}"
      end
    end
    lines.join("\n")
  end

  def event_cells(event)
    [
      event.row_number,
      truncate("#{event.date_range} #{event.start_time}".strip, 25),
      truncate(event.name, 46),
      truncate(event.location, 34),
      event.category,
      event.image.empty? ? "-" : event.image[0, 8],
      event.submitted_by
    ]
  end

  def truncate(value, width)
    (value.length > width) ? "#{value[0, width - 1]}…" : value
  end
end
