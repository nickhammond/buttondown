# frozen_string_literal: true

module Buttondown
  class Client
    BASE_URL = "https://api.buttondown.com/v1"

    # Unpinned requests use whatever the account's settings page says, which can
    # change under you.
    API_VERSION = "2026-04-01"

    # Skips Buttondown's double opt-in for this subscriber.
    DEFAULT_TYPE = "regular"

    # Merges a repeat subscribe into the existing subscriber instead of failing.
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

    # Creates a subscriber. Further attributes -- ip_address, tags, metadata and
    # the rest -- are passed through for the API to validate. See the README.
    #
    # With the default collision_behavior "add" a duplicate is a success that
    # returns the existing record, so this returning does not mean the person
    # will receive email. Check Subscriber#regular?.
    def subscribe(email, type: DEFAULT_TYPE, **attributes)
      # Routed to a header rather than the body, so the caller need not know
      # which is which. fetch, not delete-or-default: an explicit nil means
      # "omit the header" and has to survive.
      collision_behavior = attributes.fetch(:collision_behavior, DEFAULT_COLLISION_BEHAVIOR)

      payload = attributes.except(:collision_behavior).merge(email_address: normalize_email(email))
      payload[:type] = type if type

      Subscriber.new(request(:post, "/subscribers", payload: payload, collision_behavior: collision_behavior))
    end

    # Retrieves a subscriber by id or email address -- Buttondown's path is
    # /subscribers/{id_or_email}, so either works.
    def subscriber(id_or_email)
      Subscriber.new(request(:get, "/subscribers/#{path_segment(id_or_email)}"))
    end

    # Updates a subscriber by id or email address. Only the attributes given are
    # touched, and they are passed through for the API to validate.
    #
    # This bypasses the suppression rules: setting type back to "regular"
    # reactivates an unsubscribed subscriber with no error at all.
    def update_subscriber(id_or_email, **attributes)
      raise InvalidArgumentError, "No attributes to update" if attributes.empty?

      Subscriber.new(request(:patch, "/subscribers/#{path_segment(id_or_email)}", payload: attributes))
    end

    # Unsubscribes a subscriber. Buttondown has no unsubscribe endpoint: this is
    # an update setting the type, named for the action worth having. Keeping the
    # record is what makes the opt-out stick -- see the README.
    def unsubscribe(id_or_email, reason: nil)
      attributes = {type: "unsubscribed"}
      attributes[:unsubscription_reason] = reason if reason

      update_subscriber(id_or_email, **attributes)
    end

    # Keeps the token out of logs, error-tracker breadcrumbs and binding.irb.
    def inspect
      "#<#{self.class.name} api_version=#{api_version.inspect} token=[FILTERED]>"
    end

    private

    # Interpolated rather than joined: URI.join would replace "/v1" and silently
    # drop the version prefix.
    def request(verb, path, payload: nil, collision_behavior: nil)
      uri = URI("#{BASE_URL}#{path}")
      headers = request_headers(collision_behavior: collision_behavior)

      http_request = http_class(verb).new(uri.request_uri, headers)
      http_request.body = JSON.generate(payload) if payload

      perform(build_http(uri), http_request)
    end

    def http_class(verb)
      case verb
      when :get then Net::HTTP::Get
      when :post then Net::HTTP::Post
      when :patch then Net::HTTP::Patch
      else raise ArgumentError, "Unsupported HTTP verb #{verb.inspect}"
      end
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

    # An explicit rescue list rather than bare `rescue`, so a bug in this gem
    # surfaces as itself instead of as a connection failure. Classifying the
    # response sits inside the rescues but raises only APIError and
    # InvalidResponseError, neither of which they catch.
    def perform(http, http_request)
      response = http.request(http_request)

      return success_body(response) if response.is_a?(Net::HTTPSuccess)

      raise_api_error(response)
    rescue *TIMEOUT_ERRORS => e
      raise TimeoutError, "Buttondown request timed out: #{e.class}"
    rescue *CONNECTION_ERRORS => e
      raise ConnectionError, "Couldn't reach Buttondown: #{e.class}: #{e.message}"
    end

    def request_headers(collision_behavior: nil)
      headers = {
        "Authorization" => "Token #{token}",
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => USER_AGENT,
        "X-API-Version" => api_version
      }
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

    # Guards a 100/day rate limit against addresses no mail server would accept.
    # "@" and "+" are legal in a path segment and Buttondown accepts them raw,
    # but encoding is accepted too and stops a stray "/" rewriting the path.
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
