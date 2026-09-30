require "date"
require_relative "event_validation"
require_relative "sheets_config"

# Read-only view over the events spreadsheet.
#
# Answers "what is actually published right now?" and flags data problems
# (duplicates, schema violations) before they reach the public site.
#
# Columns are resolved from the sheet's own header row, so their order can
# change without breaking this class.
class SheetInvestigator
  DATE_FORMAT = "%d/%m/%Y"

  # Spreadsheet column -> key expected by EventValidation. This is the single
  # source of truth for translating a sheet row into schema params.
  # Columns not listed here (added_at, submitted_by, image) carry metadata
  # rather than schema fields.
  SCHEMA_KEY_BY_COLUMN = {
    "name" => :name,
    "start_date" => :start_date,
    "start_time" => :start_time,
    "end_date" => :end_date,
    "end_time" => :end_time,
    "location" => :location,
    "description" => :description,
    "category" => :category,
    "organizer" => :organizer,
    "email" => :contact_email,
    "phone" => :contact_tel,
    "price" => :price_type,
    "link_1" => :event_link1,
    "link_2" => :event_link2,
    "link_3" => :event_link3,
    "link_4" => :event_link4
  }.freeze

  # Columns the report reads or filters on. The configured range
  # (Approved!A:O) stops before the link columns, so only those may be absent.
  REQUIRED_COLUMNS = %w[
    name start_date start_time end_date end_time location description category
    organizer email phone price image submitted_by
  ].freeze

  # Columns --search covers.
  SEARCHABLE_FIELDS = %i[name location description organizer category].freeze

  # A single published event, exposing sheet columns by name.
  class Event
    attr_reader :row_number, :columns

    def initialize(row_number:, columns:)
      @row_number = row_number
      @columns = columns
    end

    def [](column)
      columns[column.to_s].to_s
    end

    def name
      self[:name]
    end

    def start_date
      self[:start_date]
    end

    def start_time
      self[:start_time]
    end

    def end_date
      self[:end_date]
    end

    def location
      self[:location]
    end

    def description
      self[:description]
    end

    def category
      self[:category]
    end

    def organizer
      self[:organizer]
    end

    def image
      self[:image]
    end

    def submitted_by
      self[:submitted_by]
    end

    def normalized_name
      name.strip.downcase
    end

    # Zero-padded start date. The sheet mixes "5/6/2026" and "05/06/2026", so
    # grouping on the raw value would miss rows that are really the same event.
    def canonical_start_date
      parse_date(start_date)&.strftime(DATE_FORMAT) || start_date
    end

    # Same-day events render with a single date so the report reads cleanly.
    def date_range
      return start_date if end_date.empty? || end_date == start_date

      "#{start_date} -> #{end_date}"
    end

    def starts_on?(date)
      from = parse_date(start_date)
      to = parse_date(end_date.empty? ? start_date : end_date)

      !from.nil? && !to.nil? && date.between?(from, to)
    end

    # Each field is matched on its own, so a multi-word query cannot straddle
    # two columns and match something that is in neither.
    def matches?(needle)
      SEARCHABLE_FIELDS.any? { |field| public_send(field).to_s.downcase.include?(needle) }
    end

    # A column missing from the range reads as "", which is what lets the link
    # columns stay optional outside Approved!A:O. REQUIRED_COLUMNS is what stops
    # a genuinely needed column from silently validating as empty.
    def schema_params
      SCHEMA_KEY_BY_COLUMN.to_h { |column, key| [key, self[column]] }
    end

    private

    def parse_date(value)
      return unless EventValidation::DATE_PATTERN.match?(value)

      Date.strptime(value, DATE_FORMAT)
    rescue ArgumentError, TypeError
      nil
    end
  end

  def initialize(rows, headers:, first_row_number: 2)
    @headers = Array(headers).map(&:to_s)
    verify_headers!
    @events = rows.each_with_index.filter_map { |row, index| build_event(row, first_row_number + index) }
  end

  def self.from_spreadsheet(range: nil)
    header, rows, first_row_number = SheetsConfig.read_rows(range: range)
    new(rows, headers: header, first_row_number: first_row_number)
  end

  def all
    @events
  end

  def with_image(image_uuid)
    select(image: image_uuid)
  end

  def matching(text)
    select(text: text)
  end

  def on_date(date)
    select(date: date)
  end

  # Applies every provided filter in a single pass so the options can be
  # combined without one silently overriding another.
  def select(image: nil, text: nil, date: nil)
    needle = text.to_s.strip.downcase

    @events.select do |event|
      (image.nil? || event.image == image) &&
        (needle.empty? || event.matches?(needle)) &&
        (date.nil? || event.starts_on?(date))
    end
  end

  # Same name and same start date.
  def exact_duplicates(events = @events)
    duplicates_by(events) { |event| [event.normalized_name, event.canonical_start_date] }
  end

  # Same day, same place and same category but a different name. These are the
  # ones that slip through unnoticed, like the same tourney submitted twice
  # with slightly different wording. Heuristic only: two genuinely different
  # events can share a venue, a day and a category.
  def suspicious_duplicates(events = @events)
    duplicates_by(events) { |event| [event.canonical_start_date, normalize(event.location), normalize(event.category)] }
      .reject { |group| group.map(&:normalized_name).uniq.one? }
  end

  def validation_failures(events = @events)
    events.filter_map do |event|
      result = EventValidation.call(event.schema_params)
      [event, result.errors] if result.failure?
    end
  end

  private

  def duplicates_by(events, &key)
    events.group_by(&key).values.select { |group| group.size > 1 }
  end

  def normalize(value)
    value.to_s.strip.downcase
  end

  def verify_headers!
    missing = REQUIRED_COLUMNS - @headers
    raise "Unexpected spreadsheet header. Missing columns: #{missing.join(", ")}" if missing.any?
  end

  def build_event(row, row_number)
    # Sheets can return rows that exist but hold only empty strings.
    return nil if Array(row).all? { |value| value.to_s.strip.empty? }

    columns = row.each_with_index.to_h { |value, index| [@headers[index], value.to_s] }
    Event.new(row_number: row_number, columns: columns)
  end
end
