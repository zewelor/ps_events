require "json-schema"
require "date"
require "time"

class EventValidation
  SCHEMA_PATH = File.expand_path("../event_schema.json", __dir__)
  SCHEMA = JSON.parse(File.read(SCHEMA_PATH))

  def self.call(params)
    new.call(params)
  end

  # Result class to encapsulate the validation result
  # and provide a consistent interface for success/failure checks.
  # It also provides a method to convert the data to a hash.

  Result = Struct.new(:data, :errors) do
    def success?
      errors.empty?
    end

    def failure?
      !success?
    end

    def to_h
      data
    end
  end

  def call(params)
    errors = schema_errors(params)
    validate_relations(params, errors)
    Result.new(params, errors)
  end

  private

  def schema_errors(params)
    errs = JSON::Validator.fully_validate(SCHEMA, params, errors_as_objects: true)
    errs.each_with_object({}) do |err, h|
      field = err[:fragment].sub("#/", "").to_sym
      (h[field] ||= []) << err[:message]
    end
  end

  def validate_relations(params, errors)
    begin
      Date.strptime(params[:start_date], "%d/%m/%Y")
    rescue ArgumentError
      (errors[:start_date] ||= []) << "must be a valid date in dd/mm/yyyy format (e.g., 01/12/2025)"
    end

    begin
      Date.strptime(params[:end_date], "%d/%m/%Y")
    rescue ArgumentError
      (errors[:end_date] ||= []) << "must be a valid date in dd/mm/yyyy format (e.g., 02/12/2025)"
    end

    if params[:start_time] && !params[:start_time].to_s.empty?
      begin
        Time.parse(params[:start_time])
      rescue ArgumentError
        (errors[:start_time] ||= []) << "must be a valid time format (HH:MM)"
      end
    end

    if params[:end_time] && !params[:end_time].to_s.empty?
      begin
        Time.parse(params[:end_time])
      rescue ArgumentError
        (errors[:end_time] ||= []) << "must be a valid time format (HH:MM)"
      end
    end

    unless errors[:end_date] || errors[:start_date]
      begin
        end_date = Date.strptime(params[:end_date], "%d/%m/%Y")
        start_date = Date.strptime(params[:start_date], "%d/%m/%Y")
        if end_date < start_date
          (errors[:end_date] ||= []) << "must be on or after start date"
        end
      rescue ArgumentError
      end
    end

    if params[:start_date] && params[:end_date] &&
        params[:start_time] && params[:end_time] &&
        !params[:start_time].to_s.empty? && !params[:end_time].to_s.empty? &&
        params[:start_date] == params[:end_date]
      begin
        start_time = Time.parse(params[:start_time])
        end_time = Time.parse(params[:end_time])
        if end_time <= start_time
          (errors[:end_time] ||= []) << "must be after start time when on the same date"
        end
      rescue ArgumentError
      end
    end
  end
end
