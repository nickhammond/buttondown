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

    USER_AGENT = "buttondown-rb/#{VERSION}"

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

    def initialize(token = ENV["BUTTONDOWN_API_KEY"],
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
    def create_subscriber(email, type: DEFAULT_TYPE, collision_behavior: DEFAULT_COLLISION_BEHAVIOR)
      payload = {email_address: normalize_email(email)}
      payload[:type] = type if type

      Subscriber.new(post("/subscribers", payload, collision_behavior: collision_behavior))
    end
    alias_method :subscribe, :create_subscriber

    # Keeps the token out of logs, error-tracker breadcrumbs and binding.irb.
    def inspect
      "#<#{self.class.name} api_version=#{api_version.inspect} token=[FILTERED]>"
    end

    private

    def post(path, payload, collision_behavior: nil)
      # Interpolated, not URI.join -- join would replace "/v1" and silently drop
      # the version prefix.
      uri = URI("#{BASE_URL}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.write_timeout = @write_timeout
      http.max_retries = 0 # never silently re-POST against a 100/day limit

      request = Net::HTTP::Post.new(uri.request_uri, request_headers(collision_behavior))
      request.body = JSON.generate(payload)

      response =
        begin
          http.request(request)
        rescue *TIMEOUT_ERRORS => e
          raise TimeoutError, "Buttondown request timed out: #{e.class}"
        rescue *CONNECTION_ERRORS => e
          raise ConnectionError, "Couldn't reach Buttondown: #{e.class}: #{e.message}"
        end

      handle(response)
    end

    def request_headers(collision_behavior)
      headers = {
        "Authorization" => "Token #{token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT,
        "X-API-Version" => api_version
      }
      headers["X-Buttondown-Collision-Behavior"] = collision_behavior.to_s if collision_behavior
      headers
    end

    # Returns the parsed body Hash on success; raises otherwise.
    def handle(response)
      status = response.code.to_i
      raw_body = response.body.to_s

      if response.is_a?(Net::HTTPSuccess)
        return {} if raw_body.empty?

        parsed = parse_json(raw_body)

        unless parsed.is_a?(Hash)
          raise InvalidResponseError.new(
            "Buttondown returned a #{status} whose body wasn't a JSON object",
            status: status,
            raw_body: raw_body
          )
        end

        return parsed
      end

      parsed = parse_json(raw_body)
      parsed = {} unless parsed.is_a?(Hash)

      code = parsed["code"] || parsed["error_code"]
      message = parsed["detail"] || parsed["error"] || parsed["message"] || response.message

      error_class = ERROR_CODES[code] ||
        STATUS_ERRORS[status] ||
        ((status >= 500) ? ServerError : APIError)

      raise error_class.new(
        message,
        status: status,
        code: code,
        body: parsed,
        raw_body: raw_body,
        headers: response.to_hash.transform_values(&:first)
      )
    end

    def parse_json(string)
      JSON.parse(string)
    rescue JSON::ParserError
      nil
    end

    # Stands in for the Rails-flavored blank check the extracted code used, and
    # guards a 100/day rate limit against addresses no mail server would accept.
    # The message deliberately omits the address, which is PII that would
    # otherwise land in an error tracker.
    def normalize_email(email)
      value = email.to_s.strip

      raise InvalidEmailError, "Email address can't be blank" if value.empty?
      raise InvalidEmailError, "Email address isn't a valid address" unless value.match?(EMAIL_PATTERN)

      value
    end
  end
end
