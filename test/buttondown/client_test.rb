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

    def stub_patch(segment, status: 200, body: nil)
      stub_request(:patch, "#{CREATE_URL}/#{segment}")
        .to_return(status: status, body: body || subscriber_body(type: "unsubscribed"))
    end

    def stub_retrieve(segment, status: 200, body: nil)
      stub_request(:get, "#{CREATE_URL}/#{segment}")
        .to_return(status: status, body: body || subscriber_body)
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
              "X-API-Version" => "2026-04-01"
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

      it "sends extra attributes in the body" do
        stub = stub_request(:post, CREATE_URL)
          .with(body: {
            ip_address: "203.0.113.4",
            tags: ["signup-form"],
            utm_source: "newsletter",
            email_address: "nick@example.com",
            type: "regular"
          }.to_json)
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com",
                         ip_address: "203.0.113.4", tags: ["signup-form"], utm_source: "newsletter")

        assert_requested stub
      end

      # Attributes are not checked against the documented list: the API rejects
      # an unknown one, so a new field needs no gem release.
      it "passes an attribute the gem has never heard of straight through" do
        stub = stub_request(:post, CREATE_URL)
          .with(body: {some_future_field: "x", email_address: "nick@example.com", type: "regular"}.to_json)
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com", some_future_field: "x")

        assert_requested stub
      end

      # collision_behavior arrives as an ordinary attribute so a caller need
      # not know it is a header, which means it must not also reach the body.
      it "routes collision_behavior to the header, not the body" do
        stub = stub_request(:post, CREATE_URL)
          .with(headers: {"X-Buttondown-Collision-Behavior" => "overwrite"}) do |request|
            !JSON.parse(request.body).key?("collision_behavior")
          end
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com", collision_behavior: "overwrite")

        assert_requested stub
      end

      it "keeps collision_behavior out of the body when it is nil" do
        stub = stub_request(:post, CREATE_URL)
          .with { |request| !JSON.parse(request.body).key?("collision_behavior") }
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com", collision_behavior: nil)

        assert_requested stub
      end

      # The positional argument is the address, so it wins: the alternative is
      # a call that silently subscribes someone other than who it names.
      it "prefers the positional email over an email_address attribute" do
        stub = stub_request(:post, CREATE_URL)
          .with { |request| JSON.parse(request.body)["email_address"] == "nick@example.com" }
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com", email_address: "someone-else@example.com")

        assert_requested stub
      end

      # No header at all, so Buttondown's documented no_op applies: a repeat
      # address fails instead of merging. The gem used to force "add" here.
      it "sends no collision header unless one is asked for" do
        stub = stub_request(:post, CREATE_URL)
          .with { |request| !request.headers.key?("X-Buttondown-Collision-Behavior") }
          .to_return(status: 201, body: subscriber_body)

        client.subscribe("nick@example.com")

        assert_requested stub
      end

      it "treats an explicit nil the same way" do
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

        s = client.subscribe("nick@example.com", collision_behavior: "add")

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

      # Code and status confirmed against the live API on 2026-11-21. Reachable
      # from a plain subscribe now that the gem sends no collision header.
      it "maps a duplicate to EmailAlreadyExistsError" do
        stub_create(
          status: [400, "Bad Request"],
          body: {code: "email_already_exists", detail: "That email address is already subscribed"}.to_json
        )

        error = assert_raises(Buttondown::EmailAlreadyExistsError) do
          client.subscribe("nick@example.com")
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

      # The OpenAPI spec documents 409 on every subscriber endpoint.
      it "maps 409 to ConflictError" do
        stub_create(status: [409, "Conflict"], body: "")

        error = assert_raises(Buttondown::ConflictError) { client.subscribe("nick@example.com") }

        assert_equal 409, error.status
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

      # Neither of these descends from IOError, so both escaped unwrapped until
      # 0.3.1 -- past any `retry_on Buttondown::ConnectionError` the README asks
      # callers to write, and advertising that the gem is built on Net::HTTP.
      it "wraps a malformed status line" do
        stub_request(:post, CREATE_URL).to_raise(Net::HTTPBadResponse)

        assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }
      end

      it "wraps a malformed response header" do
        stub_request(:post, CREATE_URL).to_raise(Net::HTTPHeaderSyntaxError)

        assert_raises(Buttondown::ConnectionError) { client.subscribe("nick@example.com") }
      end

      # Deliberately not rescued: these come from an HTTP status, not the
      # transport, and Net::ProtocolError was left out of the list to keep them
      # distinguishable.
      it "lets an HTTP status exception escape unwrapped" do
        stub_request(:post, CREATE_URL).to_raise(Net::HTTPFatalError.new("500", nil))

        assert_raises(Net::HTTPFatalError) { client.subscribe("nick@example.com") }
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

    # ArgumentError rather than a Buttondown::Error: an unsupported verb is a
    # bug in this gem, not something a caller can cause.
    it "refuses an HTTP verb it doesn't know" do
      error = assert_raises(ArgumentError) { client.send(:request, :put, "/subscribers") }

      assert_match "Unsupported HTTP verb :put", error.message
      assert_not_requested :put, /api\.buttondown\.com/
    end

    describe "#subscriber" do
      it "retrieves by id" do
        stub = stub_retrieve("sub_123")

        result = client.subscriber("sub_123")

        assert_requested stub
        assert_kind_of Buttondown::Subscriber, result
        assert_equal "sub_123", result.id
        assert_equal "regular", result.type
      end

      # Buttondown's path is /subscribers/{id_or_email}, so an address needs no
      # separate lookup. Confirmed against the live API on 2026-11-22.
      it "retrieves by email address" do
        stub = stub_retrieve("nick%40example.com", body: subscriber_body)

        assert_equal "sub_123", client.subscriber("nick@example.com").id
        assert_requested stub
      end

      # A "+" means a literal plus in a path, but encoding it is what the live
      # API was verified against, and it keeps the two readings from diverging.
      it "encodes a plus-addressed email" do
        stub = stub_retrieve("nick%2Btag%40example.com")

        client.subscriber("nick+tag@example.com")

        assert_requested stub
      end

      it "encodes a segment that would otherwise rewrite the path" do
        stub = stub_retrieve("..%2F..%2Fnewsletters")

        client.subscriber("../../newsletters")

        assert_requested stub
        assert_not_requested :get, "https://api.buttondown.com/v1/newsletters"
      end

      it "strips surrounding whitespace" do
        stub = stub_retrieve("sub_123")

        client.subscriber("  sub_123\n")

        assert_requested stub
      end

      # Content-Type among them: Buttondown accepts it on a bodyless request,
      # and one header set for every verb beats a conditional one.
      it "sends the same headers as a create" do
        stub = stub_request(:get, "#{CREATE_URL}/sub_123")
          .with(headers: {
                  "Authorization" => "Token secret",
                  "Accept" => "application/json",
                  "Content-Type" => "application/json",
                  "X-API-Version" => "2026-04-01",
                  "User-Agent" => "buttondown-rb/#{Buttondown::VERSION}"
                })
          .to_return(status: 200, body: subscriber_body)

        client.subscriber("sub_123")

        assert_requested stub
      end

      # 404 with code "not_found" confirmed against the live API on 2026-11-22.
      it "raises NotFoundError for a subscriber that doesn't exist" do
        stub_retrieve("nobody%40example.com", status: 404,
                                              body: {code: "not_found", detail: "Not found."}.to_json)

        error = assert_raises(Buttondown::NotFoundError) { client.subscriber("nobody@example.com") }

        assert_equal 404, error.status
        assert_equal "not_found", error.code
      end

      it "raises without a request when the id is blank" do
        ["", "   ", nil].each do |blank|
          assert_raises(Buttondown::InvalidArgumentError) { client.subscriber(blank) }
        end

        assert_not_requested :get, /api\.buttondown\.com/
      end
    end

    describe "#update_subscriber" do
      it "patches the attributes and returns the updated subscriber" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with(body: {notes: "a note"}.to_json)
          .to_return(status: 200, body: subscriber_body)

        result = client.update_subscriber("sub_123", notes: "a note")

        assert_requested stub
        assert_kind_of Buttondown::Subscriber, result
        assert_equal "sub_123", result.id
      end

      it "sends several attributes at once" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with(body: {notes: "a note", metadata: {plan: "pro"}, commenting_disabled: true}.to_json)
          .to_return(status: 200, body: subscriber_body)

        client.update_subscriber("sub_123", notes: "a note", metadata: {plan: "pro"}, commenting_disabled: true)

        assert_requested stub
      end

      # Attributes are not checked against the documented list: the API
      # rejects an unknown one, so a new field needs no gem release.
      it "passes an attribute the gem has never heard of straight through" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with(body: {some_future_field: "x"}.to_json)
          .to_return(status: 200, body: subscriber_body)

        client.update_subscriber("sub_123", some_future_field: "x")

        assert_requested stub
      end

      it "works by email address" do
        stub = stub_patch("nick%40example.com")

        client.update_subscriber("nick@example.com", notes: "a note")

        assert_requested stub
      end

      it "raises without a request when there is nothing to update" do
        error = assert_raises(Buttondown::InvalidArgumentError) { client.update_subscriber("sub_123") }

        assert_match "No attributes", error.message
        assert_not_requested :patch, /api\.buttondown\.com/
      end

      it "raises without a request when the id is blank" do
        ["", "   ", nil].each do |blank|
          assert_raises(Buttondown::InvalidArgumentError) { client.update_subscriber(blank, notes: "x") }
        end

        assert_not_requested :patch, /api\.buttondown\.com/
      end

      it "raises NotFoundError when no subscriber matches" do
        stub_patch("nobody%40example.com", status: 404,
                                           body: {code: "not_found", detail: "Not found."}.to_json)

        assert_raises(Buttondown::NotFoundError) { client.update_subscriber("nobody@example.com", notes: "x") }
      end
    end

    describe "#unsubscribe" do
      it "updates the type to unsubscribed" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with(body: {type: "unsubscribed"}.to_json)
          .to_return(status: 200, body: subscriber_body(type: "unsubscribed"))

        result = client.unsubscribe("sub_123")

        assert_requested stub
        assert_equal "unsubscribed", result.type
        assert result.terminal?
        refute result.regular?
      end

      it "sends a reason when given one" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with(body: {type: "unsubscribed", unsubscription_reason: "too many emails"}.to_json)
          .to_return(status: 200, body: subscriber_body(type: "unsubscribed"))

        client.unsubscribe("sub_123", reason: "too many emails")

        assert_requested stub
      end

      it "omits the reason when none is given" do
        stub = stub_request(:patch, "#{CREATE_URL}/sub_123")
          .with { |request| !JSON.parse(request.body).key?("unsubscription_reason") }
          .to_return(status: 200, body: subscriber_body(type: "unsubscribed"))

        client.unsubscribe("sub_123")

        assert_requested stub
      end

      it "works by email address" do
        stub = stub_patch("nick%40example.com")

        client.unsubscribe("nick@example.com")

        assert_requested stub
      end

      it "raises NotFoundError when no subscriber matches" do
        stub_patch("nobody%40example.com", status: 404,
                                           body: {code: "not_found", detail: "Not found."}.to_json)

        assert_raises(Buttondown::NotFoundError) { client.unsubscribe("nobody@example.com") }
      end
    end
  end
end
