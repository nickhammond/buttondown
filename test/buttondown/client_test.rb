# frozen_string_literal: true

require "test_helper"

class TestButtondownClient < Minitest::Test
  CREATE_URL = "https://api.buttondown.com/v1/subscribers"

  describe Buttondown::Client do
    after do
      ENV.delete("BUTTONDOWN_API_KEY")
    end

    def client(token = "secret", **options)
      Buttondown::Client.new(token, **options)
    end

    def subscriber_body(type: "regular", email: "nick@example.com")
      {id: "sub_123", email_address: email, type: type}.to_json
    end

    def stub_create(status: 201, body: nil, headers: {})
      stub_request(:post, CREATE_URL)
        .to_return(status: status, body: body || subscriber_body, headers: headers)
    end

    describe "construction" do
      it "takes a token" do
        assert_equal "secret", client.token
      end

      it "falls back to ENV['BUTTONDOWN_API_KEY']" do
        ENV["BUTTONDOWN_API_KEY"] = "from-env"

        assert_equal "from-env", Buttondown::Client.new.token
      end

      it "prefers an explicit token over ENV" do
        ENV["BUTTONDOWN_API_KEY"] = "from-env"

        assert_equal "explicit", Buttondown::Client.new("explicit").token
      end

      it "raises without a token" do
        assert_raises(Buttondown::ConfigurationError) { Buttondown::Client.new(nil) }
      end

      it "raises on a whitespace-only token" do
        assert_raises(Buttondown::ConfigurationError) { Buttondown::Client.new("   ") }
      end

      it "strips a pasted token" do
        assert_equal "secret", Buttondown::Client.new(" secret\n").token
      end

      it "keeps the token out of #inspect" do
        refute_includes client.inspect, "secret"
        assert_includes client.inspect, "[FILTERED]"
      end
    end

    describe "the email guard" do
      [
        ["nil", nil],
        ["an empty string", ""],
        ["whitespace only", "   "],
        ["an address with no @", "nick"],
        ["an address with no dot in the host", "nick@example"]
      ].each do |description, input|
        it "rejects #{description} without making a request" do
          assert_raises(Buttondown::InvalidEmailError) { client.subscribe(input) }
          assert_not_requested :post, CREATE_URL
        end
      end

      it "strips surrounding whitespace and sends the stripped address" do
        stub = stub_request(:post, CREATE_URL)
          .with(body: {email_address: "nick@example.com", type: "regular"}.to_json)
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("  nick@example.com\n")

        assert_requested stub
      end

      it "raises a Buttondown::Error, so one rescue covers it" do
        error = assert_raises(Buttondown::InvalidEmailError) { client.subscribe("") }

        assert_kind_of Buttondown::Error, error
        assert_kind_of Buttondown::InvalidArgumentError, error
      end

      it "keeps the address out of the message, which reaches error trackers" do
        error = assert_raises(Buttondown::InvalidEmailError) { client.subscribe("nick@example") }

        refute_includes error.message, "nick@example"
      end
    end

    describe "the request" do
      # Pins every API fact that was expensive to establish. Fails if the host
      # regresses to api.buttondown.email, if auth regresses to Bearer, if the
      # field regresses to `email`, or if either header goes missing.
      it "sends the documented request" do
        stub = stub_request(:post, CREATE_URL)
          .with(
            body: {email_address: "nick@example.com", type: "regular"}.to_json,
            headers: {
              "Authorization" => "Token secret",
              "Content-Type" => "application/json",
              "Accept" => "application/json",
              "X-API-Version" => "2026-04-01",
              "X-Buttondown-Collision-Behavior" => "add"
            }
          ).to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com")

        assert_requested stub
      end

      it "sends a chosen collision behavior" do
        stub = stub_request(:post, CREATE_URL)
          .with(headers: {"X-Buttondown-Collision-Behavior" => "overwrite"})
          .to_return(status: 200, body: subscriber_body)

        client.subscribe("nick@example.com", collision_behavior: "overwrite")

        assert_requested stub
      end

      it "omits the collision header when given nil" do
        stub = stub_request(:post, CREATE_URL)
          .with { |request| !request.headers.key?("X-Buttondown-Collision-Behavior") }
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com", collision_behavior: nil)

        assert_requested stub
      end

      it "sends a chosen type" do
        stub = stub_request(:post, CREATE_URL)
          .with(body: {email_address: "nick@example.com", type: "unactivated"}.to_json)
          .to_return(status: 201, body: subscriber_body(type: "unactivated"))

        client.subscribe("nick@example.com", type: "unactivated")

        assert_requested stub
      end

      it "omits type when given nil, letting double opt-in apply" do
        stub = stub_request(:post, CREATE_URL)
          .with(body: {email_address: "nick@example.com"}.to_json)
          .to_return(status: 201, body: subscriber_body(type: "unactivated"))

        client.subscribe("nick@example.com", type: nil)

        assert_requested stub
      end

      it "sends a per-client API version" do
        stub = stub_request(:post, CREATE_URL)
          .with(headers: {"X-API-Version" => "2025-01-01"})
          .to_return(status: 201, body: subscriber_body)

        client("secret", api_version: "2025-01-01").subscribe("nick@example.com")

        assert_requested stub
      end

      it "identifies itself with the gem version" do
        stub = stub_request(:post, CREATE_URL)
          .with(headers: {"User-Agent" => "buttondown-rb/#{Buttondown::VERSION}"})
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com")

        assert_requested stub
      end
    end

    describe "success" do
      it "returns a Subscriber on 201" do
        stub_create

        s = client.subscribe("nick@example.com")

        assert_kind_of Buttondown::Subscriber, s
        assert_equal "sub_123", s.id
        assert_equal "nick@example.com", s.email_address
        assert s.regular?
      end

      # The contract of collision_behavior "add": a duplicate is a SUCCESS that
      # returns the pre-existing record, so a 2xx does not mean "will get mail".
      it "returns the pre-existing record when a duplicate merges" do
        stub_create(status: 200, body: subscriber_body(type: "unsubscribed"))

        s = client.subscribe("nick@example.com")

        refute s.regular?
        assert s.terminal?
      end

      it "surfaces a subscriber still pending double opt-in" do
        stub_create(body: subscriber_body(type: "unactivated"))

        s = client.subscribe("nick@example.com")

        assert s.unactivated?
        refute s.regular?
      end

      it "round-trips the raw body through #to_h" do
        stub_create

        s = client.subscribe("nick@example.com")

        assert_equal JSON.parse(subscriber_body), s.to_h
      end

      it "tolerates an empty success body" do
        stub_create(body: "")

        s = client.subscribe("nick@example.com")

        assert_nil s.id
      end

      it "raises when a 2xx body isn't JSON" do
        stub_create(body: "<html>maintenance</html>")

        error = assert_raises(Buttondown::InvalidResponseError) { client.subscribe("nick@example.com") }

        assert_equal 201, error.status
        assert_equal "<html>maintenance</html>", error.raw_body
      end

      it "raises when a 2xx body is JSON but not an object" do
        stub_create(body: "[]")

        assert_raises(Buttondown::InvalidResponseError) { client.subscribe("nick@example.com") }
      end
    end

    describe "API errors" do
      it "maps a suppressed subscriber to SubscriberSuppressedError" do
        stub_create(
          status: [400, "Bad Request"],
          body: {code: "subscriber_suppressed", detail: "This subscriber is suppressed"}.to_json
        )

        error = assert_raises(Buttondown::SubscriberSuppressedError) { client.subscribe("nick@example.com") }

        assert_kind_of Buttondown::BadRequestError, error
        assert_equal 400, error.status
        assert_equal "subscriber_suppressed", error.code
        assert_includes error.message, "suppressed"
        assert_equal "This subscriber is suppressed", error.body["detail"]
      end

      # Code and status confirmed against the live API on 2026-11-21.
      it "maps a duplicate to EmailAlreadyExistsError when the collision header is omitted" do
        stub_create(
          status: [400, "Bad Request"],
          body: {code: "email_already_exists", detail: "That email address is already subscribed"}.to_json
        )

        error = assert_raises(Buttondown::EmailAlreadyExistsError) do
          client.subscribe("nick@example.com", collision_behavior: nil)
        end

        assert_kind_of Buttondown::BadRequestError, error
        assert_equal 400, error.status
        assert_equal "email_already_exists", error.code
      end

      # Buttondown's firewall rejects reserved and disposable domains outright.
      # Code and status confirmed against the live API on 2026-11-21.
      it "maps a firewalled address to SubscriberBlockedError" do
        stub_create(
          status: [400, "Bad Request"],
          body: {code: "subscriber_blocked", detail: "This subscriber was blocked by your firewall."}.to_json
        )

        error = assert_raises(Buttondown::SubscriberBlockedError) { client.subscribe("nick@example.com") }

        assert_kind_of Buttondown::BadRequestError, error
        assert_equal 400, error.status
        assert_equal "subscriber_blocked", error.code
      end

      it "survives an unparseable error body" do
        stub_create(status: [400, "Bad Request"], body: "oops")

        error = assert_raises(Buttondown::BadRequestError) { client.subscribe("nick@example.com") }

        assert_nil error.code
        assert_equal({}, error.body)
        assert_equal "oops", error.raw_body
        assert_includes error.message, "Bad Request"
      end

      it "falls back to the status message on an empty error body" do
        stub_create(status: [400, "Bad Request"], body: "")

        error = assert_raises(Buttondown::BadRequestError) { client.subscribe("nick@example.com") }

        assert_includes error.message, "Bad Request"
      end

      it "maps 401 to AuthenticationError" do
        stub_create(status: [401, "Unauthorized"], body: "")

        assert_raises(Buttondown::AuthenticationError) { client.subscribe("nick@example.com") }
      end

      it "maps a disabled paid feature to FeatureDisabledError" do
        stub_create(status: [403, "Forbidden"], body: {code: "feature_disabled"}.to_json)

        error = assert_raises(Buttondown::FeatureDisabledError) { client.subscribe("nick@example.com") }

        assert_kind_of Buttondown::ForbiddenError, error
      end

      it "leaves a 403 without a code as ForbiddenError" do
        stub_create(status: [403, "Forbidden"], body: "")

        error = assert_raises(Buttondown::ForbiddenError) { client.subscribe("nick@example.com") }

        refute_kind_of Buttondown::FeatureDisabledError, error
      end

      it "maps 422 to UnprocessableEntityError" do
        stub_create(status: [422, "Unprocessable Content"], body: "")

        assert_raises(Buttondown::UnprocessableEntityError) { client.subscribe("nick@example.com") }
      end

      it "exposes Retry-After on a rate limit" do
        stub_create(status: [429, "Too Many Requests"], body: "", headers: {"Retry-After" => "3600"})

        error = assert_raises(Buttondown::RateLimitError) { client.subscribe("nick@example.com") }

        assert_equal 3600, error.retry_after
      end

      it "returns a nil Retry-After when the header is absent" do
        stub_create(status: [429, "Too Many Requests"], body: "")

        error = assert_raises(Buttondown::RateLimitError) { client.subscribe("nick@example.com") }

        assert_nil error.retry_after
      end

      it "maps 500 to ServerError and keeps the status message" do
        stub_create(status: [500, "Application Error"], body: "")

        error = assert_raises(Buttondown::ServerError) { client.subscribe("nick@example.com") }

        assert_includes error.message, "Application Error"
      end

      it "maps 503 to ServerError" do
        stub_create(status: [503, "Service Unavailable"], body: "")

        assert_raises(Buttondown::ServerError) { client.subscribe("nick@example.com") }
      end

      it "falls back to a bare APIError for an unmapped status" do
        stub_create(status: [418, "I'm a teapot"], body: "")

        error = assert_raises(Buttondown::APIError) { client.subscribe("nick@example.com") }

        assert_equal 418, error.status
      end

      it "makes every API error a Buttondown::Error" do
        [400, 401, 403, 404, 422, 429, 500].each do |status|
          WebMock.reset!
          stub_create(status: [status, "Error"], body: "")

          error = assert_raises(Buttondown::Error) { client.subscribe("nick@example.com") }

          assert_kind_of Buttondown::APIError, error
          assert_equal status, error.status
        end
      end
    end

    describe "connection failures" do
      it "wraps a connect timeout" do
        stub_request(:post, CREATE_URL).to_timeout

        error = assert_raises(Buttondown::TimeoutError) { client.subscribe("nick@example.com") }

        assert_kind_of Buttondown::ConnectionError, error
      end

      it "wraps a read timeout" do
        stub_request(:post, CREATE_URL).to_raise(Net::ReadTimeout)

        assert_raises(Buttondown::TimeoutError) { client.subscribe("nick@example.com") }
      end

      it "wraps a refused connection as ConnectionError, not a timeout" do
        stub_request(:post, CREATE_URL).to_raise(Errno::ECONNREFUSED)

        error = assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }

        refute_kind_of Buttondown::TimeoutError, error
      end

      it "wraps a DNS failure" do
        stub_request(:post, CREATE_URL).to_raise(SocketError)

        assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }
      end

      it "wraps a TLS failure" do
        stub_request(:post, CREATE_URL).to_raise(OpenSSL::SSL::SSLError)

        assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }
      end

      # The mitigation for wrapping: the original is still reachable for APM and
      # retry middleware that special-cases specific classes.
      it "keeps the original exception as #cause" do
        stub_request(:post, CREATE_URL).to_raise(SocketError)

        error = assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }

        assert_kind_of SocketError, error.cause
      end

      # Guards against a bare `rescue =>` creeping back in and turning gem bugs
      # into "connection errors".
      it "lets a programmer error escape unwrapped" do
        stub_create
        Buttondown::Subscriber.expects(:new).raises(NoMethodError)

        assert_raises(NoMethodError) { client.subscribe("nick@example.com") }
      end
    end

    describe "HTTP configuration" do
      it "preserves the 5s open and 10s read/write timeouts" do
        stub_create

        Net::HTTP.any_instance.expects(:open_timeout=).with(5)
        Net::HTTP.any_instance.expects(:read_timeout=).with(10)
        Net::HTTP.any_instance.expects(:write_timeout=).with(10)

        client.subscribe("nick@example.com")
      end

      it "accepts per-client timeouts" do
        stub_create

        Net::HTTP.any_instance.expects(:read_timeout=).with(2)

        client("secret", read_timeout: 2).subscribe("nick@example.com")
      end

      it "never silently retries a POST" do
        stub_create

        Net::HTTP.any_instance.expects(:max_retries=).with(0)

        client.subscribe("nick@example.com")
      end

      # Asserted behaviorally rather than with a mocked setter: stubbing
      # use_ssl= would stop it being applied, and WebMock distinguishes http
      # from https, so a fulfilled https stub is the real proof.
      it "uses TLS" do
        stub = stub_request(:post, "https://api.buttondown.com/v1/subscribers")
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com")

        assert_requested stub
        assert_not_requested :post, "http://api.buttondown.com/v1/subscribers"
      end
    end
  end
end
