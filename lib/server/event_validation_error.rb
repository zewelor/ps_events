class EventValidationError < StandardError
  attr_reader :validation_errors, :event_data

  def initialize(message, validation_errors: nil, event_data: nil)
    super(message)
    @validation_errors = validation_errors
    @event_data = event_data
  end

  def to_s
    message = super
    if validation_errors
      message += "\nValidation errors: #{validation_errors.inspect}"
    end
    if event_data
      message += "\nEvent data: #{event_data.inspect}"
    end
    message
  end
end
