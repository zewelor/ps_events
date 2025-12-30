require "minitest/autorun"
require_relative "../../lib/server/event_validation"

class TestEventValidation < Minitest::Test
  def setup
    @validator = EventValidation.new
  end

  def test_valid_event
    data = {
      name: "Valid Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed for valid data: #{result.errors.to_h}"
  end

  def test_invalid_name_too_short
    data = {
      name: "V",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for short name"
    refute_empty result.errors[:name]
  end

  def test_invalid_start_date_format
    data = {
      name: "Event Name",
      start_date: "01-12-2025", # Invalid format
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid start_date format"
    refute_empty result.errors[:start_date]
  end

  def test_end_date_before_start_date
    data = {
      name: "Event Name",
      start_date: "02/12/2025",
      end_date: "01/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail when end_date is before start_date"
    refute_empty result.errors[:end_date]
  end

  def test_invalid_category
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Invalid Category",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid category"
    refute_empty result.errors[:category]
  end

  def test_valid_optional_fields_empty
    data = {
      name: "Valid Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      start_time: "",
      end_time: "",
      contact_email: "",
      contact_tel: "",
      price_type: "",
      event_link1: ""
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed when optional fields are empty: #{result.errors.to_h}"
  end

  def test_valid_event_without_end_date
    data = {
      name: "Single Day Event",
      start_date: "01/12/2025",
      end_date: "",
      location: "Valid Location",
      description: "This is a valid single-day event without end_date.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed when end_date is empty (defaults to start_date): #{result.errors.to_h}"
  end

  def test_valid_event_with_times_but_no_end_date
    data = {
      name: "Single Day Event With Times",
      start_date: "01/12/2025",
      start_time: "10:00",
      end_date: "",
      end_time: "18:00",
      location: "Valid Location",
      description: "This is a valid single-day event with times but no end_date.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed when end_date is empty but times are valid: #{result.errors.to_h}"
  end

  def test_invalid_end_time_before_start_time_when_no_end_date
    data = {
      name: "Single Day Event",
      start_date: "01/12/2025",
      start_time: "18:00",
      end_date: "",
      end_time: "10:00",
      location: "Valid Location",
      description: "End time is before start time on same day.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail when end_time is before start_time (no end_date means same day)"
    refute_empty result.errors[:end_time]
  end

  def test_invalid_email
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_email: "invalid-email"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid email"
    refute_empty result.errors[:contact_email]
  end

  def test_invalid_phone_number_too_short
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_tel: "12345"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for short phone number"
    refute_empty result.errors[:contact_tel]
  end

  def test_invalid_phone_number_characters
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_tel: "123-abc"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for phone number with invalid characters"
    refute_empty result.errors[:contact_tel]
  end

  def test_invalid_price_type
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      price_type: "Expensive"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid price_type"
    refute_empty result.errors[:price_type]
  end

  def test_invalid_event_link
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      end_date: "02/12/2025",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      event_link1: "invalid-url"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid event_link1"
    refute_empty result.errors[:event_link1]
  end

  def test_end_time_before_start_time_on_same_day
    data = {
      name: "Event Name",
      start_date: "01/12/2025",
      start_time: "14:00",
      end_date: "01/12/2025",
      end_time: "12:00",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail if end_time is before start_time on the same day"
    refute_empty result.errors[:end_time]
  end

  def test_valid_event_with_all_optional_fields
    data = {
      name: "Complete Event",
      start_date: "01/12/2025",
      start_time: "10:00",
      end_date: "01/12/2025",
      end_time: "18:00",
      location: "Full Location Details",
      description: "A very detailed description of the event, ensuring it meets length requirements.",
      category: "Aprendizagem & Workshops",
      organizer: "The Main Organizer",
      contact_email: "test@example.com",
      contact_tel: "+1 (555) 123-4567",
      price_type: "Pago",
      event_link1: "http://example.com/event1",
      event_link2: "https://example.com/event2",
      event_link3: "http://example.com/event3",
      event_link4: "https://example.com/event4"
      # event_image is not tested here as it's a hash and needs specific file handling tests
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed for a complete valid event: #{result.errors.to_h}"
  end
end
