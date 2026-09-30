require "addressable/uri"

module Jekyll
  module UrlHelpers
    HTTP_SCHEMES = %w[http https].freeze

    def http_url(value)
      url = value.to_s.strip
      return if url.empty?

      uri = Addressable::URI.parse(url)
      return unless HTTP_SCHEMES.include?(uri.normalized_scheme) && !uri.host.to_s.empty?

      url
    rescue Addressable::URI::InvalidURIError
      nil
    end
  end
end

Liquid::Template.register_filter(Jekyll::UrlHelpers)
