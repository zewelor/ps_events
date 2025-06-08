class SecurityService
  WHITELISTED_EMAILS = [
    "pxopulse@gmail.com"
  ].freeze

  def self.is_valid?(email)
    return false unless email && !email.strip.empty?

    WHITELISTED_EMAILS.include?(email.strip.downcase)
  end
end
