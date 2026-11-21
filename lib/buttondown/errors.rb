# frozen_string_literal: true

module Buttondown
  # Base class for everything this gem raises. `rescue Buttondown::Error` is the
  # whole contract -- no Net::HTTP or JSON exception escapes the client.
  class Error < StandardError; end

  # No token was passed and ENV["BUTTONDOWN_API_KEY"] is unset or blank.
  class ConfigurationError < Error; end

  # A bad argument, caught locally. No HTTP request was made.
  class InvalidArgumentError < Error; end

  class InvalidEmailError < InvalidArgumentError; end

  # The request never produced a complete HTTP response.
  class ConnectionError < Error; end

  class TimeoutError < ConnectionError; end

  # Buttondown answered 2xx but the body wasn't a JSON object we could use -- a
  # proxy maintenance page, or a truncated response.
  class InvalidResponseError < Error
    attr_reader :status, :raw_body

    def initialize(message, status: nil, raw_body: nil)
      @status = status
      @raw_body = raw_body
      super(message)
    end
  end

  # Buttondown answered with a non-2xx status.
  #
  # Exposes the response as plain data (`headers`, `raw_body`) rather than the
  # Net::HTTPResponse itself, so swapping the HTTP backend stays a patch release.
  class APIError < Error
    attr_reader :status, :code, :body, :raw_body, :headers

    def initialize(message, status: nil, code: nil, body: nil, raw_body: nil, headers: nil)
      @status = status
      @code = code
      @body = body || {}
      @raw_body = raw_body
      @headers = headers || {}
      super(message)
    end

    def to_s
      [super, code && "(#{code})", status && "[HTTP #{status}]"].compact.join(" ")
    end
  end

  class BadRequestError < APIError; end

  class SubscriberSuppressedError < BadRequestError; end

  class AuthenticationError < APIError; end

  class ForbiddenError < APIError; end

  class FeatureDisabledError < ForbiddenError; end

  class NotFoundError < APIError; end

  class UnprocessableEntityError < APIError; end

  class ServerError < APIError; end

  class RateLimitError < APIError
    # Seconds to wait, when Buttondown tells us. Nil otherwise -- the 100/day
    # subscriber-creation limit often comes back without a hint.
    def retry_after
      value = headers["retry-after"]
      value&.to_i
    end
  end

  # Buttondown's machine-readable error codes, for the cases where the code is
  # more specific than the status. Consulted BEFORE the status, so a suppressed
  # subscriber classifies correctly whichever status carries it.
  ERROR_CODES = {
    "subscriber_suppressed" => SubscriberSuppressedError,
    "feature_disabled" => FeatureDisabledError
  }.freeze

  STATUS_ERRORS = {
    400 => BadRequestError,
    401 => AuthenticationError,
    403 => ForbiddenError,
    404 => NotFoundError,
    422 => UnprocessableEntityError,
    429 => RateLimitError
  }.freeze
end
