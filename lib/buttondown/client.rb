# frozen_string_literal: true

module Buttondown
  class Client
    BASE_URL = "https://api.buttondown.com/v1"

    # Pins the API version. Unpinned requests use whatever version is set on the
    # account's settings page, which can change under you.
    API_VERSION = "2026-04-01"

    # "regular" opts the subscriber in directly, skipping Buttondown's double
    # opt-in for this subscriber.
    DEFAULT_TYPE = "regular"

    # "add" merges a repeat subscribe into the existing subscriber instead of
    # returning a 400.
    DEFAULT_COLLISION_BEHAVIOR = "add"

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    WRITE_TIMEOUT = 10

    USER_AGENT = "buttondown-rb/#{VERSION}".freeze

    # Deliberately permissive: never stricter than Buttondown itself. Rejects
    # only what no mail server would accept. Known false negative: dotless hosts
    # such as "user@localhost".
    EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    # Listed first, because these are also Timeout::Error descendants and Ruby
    # takes the first matching rescue clause.
    TIMEOUT_ERRORS = [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Net::WriteTimeout
    ].freeze

    CONNECTION_ERRORS = [
      SocketError,
      EOFError,
      IOError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      OpenSSL::SSL::SSLError
    ].freeze

    attr_reader :token, :api_version

    def initialize(token = ENV.fetch("BUTTONDOWN_API_KEY", nil),
                   api_version: API_VERSION,
                   open_timeout: OPEN_TIMEOUT,
                   read_timeout: READ_TIMEOUT,
                   write_timeout: WRITE_TIMEOUT)
      @token = token.to_s.strip

      if @token.empty?
        raise ConfigurationError,
              'No Buttondown API token. Pass one to Buttondown::Client.new or set ENV["BUTTONDOWN_API_KEY"].'
      end

      @api_version = api_version
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
    end

    # Creates a subscriber. Returns a Buttondown::Subscriber.
    #
    #   type:               "regular" (default) skips Buttondown's double opt-in
    #                       for this subscriber. Pass nil to let Buttondown apply
    #                       its own default, leaving them "unactivated" until
    #                       they confirm by email.
    #   collision_behavior: "add" (default) merges into an existing subscriber
    #                       instead of failing. "overwrite" replaces. nil omits
    #                       the header, so a duplicate raises BadRequestError --
    #                       the only way to detect "already subscribed".
    #
    # Because "add" turns a duplicate into a success returning the pre-existing
    # record, a successful call does NOT mean this person will receive email.
    # Check Subscriber#regular?.
    def subscribe(email, type: DEFAULT_TYPE, collision_behavior: DEFAULT_COLLISION_BEHAVIOR)
      payload = {email_address: normalize_email(email)}
      payload[:type] = type if type

      Subscriber.new(
        request(Net::HTTP::Post, "/subscribers", payload: payload, collision_behavior: collision_behavior)
      )
    end

    # Retrieves a subscriber. Returns a Buttondown::Subscriber, or raises
    # NotFoundError when no such subscriber exists.
    #
    # Buttondown's path is /subscribers/{id_or_email}, so either identifies a
    # subscriber and there is no need to store the id:
    #
    #   client.subscriber("sub_0dys87p9a08v1ttfy6ascstnpx")
    #   client.subscriber("reader@example.com")
    def subscriber(id_or_email)
      Subscriber.new(request(Net::HTTP::Get, "/subscribers/#{path_segment(id_or_email)}"))
    end

    # Permanently deletes a subscriber, by Buttondown id or email address.
    #
    # Returns nil. There is nothing to report on success -- Buttondown answers
    # 204 with no body -- and failure raises, so there is no false to check:
    # NotFoundError when no subscriber matches, which means a second delete
    # raises rather than quietly succeeding.
    #
    # This is not unsubscribing. It removes the record and its history instead
    # of moving the subscriber to the "unsubscribed" type, and Buttondown does
    # NOT cancel a backing Stripe subscription on delete -- set the type to
    # "unsubscribed" first when that matters.
    def delete_subscriber(id_or_email)
      request(Net::HTTP::Delete, "/subscribers/#{path_segment(id_or_email)}")

      nil
    end

    # Keeps the token out of logs, error-tracker breadcrumbs and binding.irb.
    def inspect
      "#<#{self.class.name} api_version=#{api_version.inspect} token=[FILTERED]>"
    end

    private

    # The one path every public method takes: build the request, send it, and
    # return the parsed body Hash. A DELETE answers 204 with no body, which
    # arrives here as an empty Hash.
    #
    # The URL is interpolated rather than joined -- URI.join would replace
    # "/v1" and silently drop the version prefix.
    def request(type, path, payload: nil, collision_behavior: nil)
      uri = URI("#{BASE_URL}#{path}")

      http_request = type.new(
        uri.request_uri,
        request_headers(payload: payload, collision_behavior: collision_behavior)
      )
      http_request.body = JSON.generate(payload) if payload

      perform(build_http(uri), http_request)
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @write_timeout
      http.max_retries = 0 # never silently re-POST against a rate-limited endpoint
      http
    end

    # Sends the request and returns the parsed body, or raises.
    #
    # Rescues an explicit list rather than bare `rescue`, so a bug in this gem
    # surfaces as itself instead of being reported as a connection failure.
    # Classifying the response is inside the rescues but raises only APIError
    # and InvalidResponseError, neither of which they catch.
    def perform(http, http_request)
      response = http.request(http_request)

      return success_body(response) if response.is_a?(Net::HTTPSuccess)

      raise_api_error(response)
    rescue *TIMEOUT_ERRORS => e
      raise TimeoutError, "Buttondown request timed out: #{e.class}"
    rescue *CONNECTION_ERRORS => e
      raise ConnectionError, "Couldn't reach Buttondown: #{e.class}: #{e.message}"
    end

    def request_headers(payload: nil, collision_behavior: nil)
      headers = {
        "Authorization" => "Token #{token}",
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT,
        "X-API-Version" => api_version
      }
      headers["Content-Type"] = "application/json" if payload
      headers["X-Buttondown-Collision-Behavior"] = collision_behavior.to_s if collision_behavior
      headers
    end

    def success_body(response)
      status = response.code.to_i
      raw_body = response.body.to_s

      return {} if raw_body.empty?

      parsed = parse_json(raw_body)
      return parsed if parsed.is_a?(Hash)

      raise InvalidResponseError.new(
        "Buttondown returned a #{status} whose body wasn't a JSON object",
        status: status,
        raw_body: raw_body
      )
    end

    def raise_api_error(response)
      status = response.code.to_i
      raw_body = response.body.to_s

      parsed = parse_json(raw_body)
      parsed = {} unless parsed.is_a?(Hash)

      code = parsed["code"] || parsed["error_code"]

      raise error_class_for(code, status).new(
        error_message(parsed, response),
        status: status,
        code: code,
        body: parsed,
        raw_body: raw_body,
        headers: response.to_hash.transform_values(&:first)
      )
    end

    # Buttondown's own wording wherever it gives any, falling back to the
    # status line.
    def error_message(parsed, response)
      parsed["detail"] || parsed["error"] || parsed["message"] || response.message
    end

    # Code before status: a code is more specific than the status carrying it.
    def error_class_for(code, status)
      ERROR_CODES[code] || STATUS_ERRORS[status] || (status >= 500 ? ServerError : APIError)
    end

    def parse_json(string)
      JSON.parse(string)
    rescue JSON::ParserError
      nil
    end

    # Stands in for the Rails-flavored blank check the extracted code used, and
    # guards a 100/day rate limit against addresses no mail server would accept.
    #
    # This message omits the address, but that is a local courtesy rather than a
    # gem-wide guarantee: Buttondown quotes the address back in its own error
    # `detail` (see `email_already_exists`) and APIError#to_s passes that
    # through unchanged. Scrub at the error-tracker boundary if messages must
    # be address-free.
    # An id or an email address goes in a path segment. "@" and "+" are legal
    # there and Buttondown accepts them raw, but encoding is equally accepted
    # and stops a stray "/" or "?" from rewriting the request path.
    def path_segment(value)
      segment = value.to_s.strip

      raise InvalidArgumentError, "Subscriber id or email address can't be blank" if segment.empty?

      URI.encode_uri_component(segment)
    end

    def normalize_email(email)
      value = email.to_s.strip

      raise InvalidEmailError, "Email address can't be blank" if value.empty?
      raise InvalidEmailError, "Email address isn't a valid address" unless value.match?(EMAIL_PATTERN)

      value
    end
  end
end
