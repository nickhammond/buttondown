# Buttondown

A Ruby client for the [Buttondown](https://buttondown.com) newsletter API.

No runtime dependencies — just Net::HTTP from the standard library. It raises its
own errors, so nothing from the HTTP layer leaks into your rescues.

### Built for Shipyrd

This gem was extracted from [Shipyrd](https://shipyrd.io), a deployment dashboard
for Kamal that shows you what shipped, when, and by whom. If you deploy with
Kamal, [give Shipyrd a look](https://shipyrd.io).

## Installation

```ruby
gem "buttondown"
```

## Usage

```ruby
client = Buttondown::Client.new            # reads ENV["BUTTONDOWN_API_KEY"]
client = Buttondown::Client.new("your-key") # or pass it explicitly

subscriber = client.subscribe("subscriber@example.com")
subscriber.regular? # => true
```

### Options

`subscribe` sends two defaults, both overridable per call:

```ruby
# type: "regular" by default. Pass nil to send no type at all.
client.subscribe(email, type: nil)

# collision_behavior: "add" by default, sent as the
# X-Buttondown-Collision-Behavior header. Pass nil to omit the header.
client.subscribe(email, collision_behavior: "overwrite")
client.subscribe(email, collision_behavior: nil)
```

What Buttondown does with those values — opt-in states, how collisions resolve,
rate limits — is documented at [docs.buttondown.com](https://docs.buttondown.com).

The call returns a `Buttondown::Subscriber`. Because a merged duplicate also
comes back as a success, check the type before assuming the address is active:

```ruby
subscriber = client.subscribe("subscriber@example.com")

subscriber.type         # => "regular"
subscriber.regular?     # will receive email
subscriber.unactivated? # created, not yet confirmed
subscriber.terminal?    # unsubscribed, blocked, complained or undeliverable
subscriber.to_h         # the raw parsed body
```

### Errors

Everything the gem raises descends from `Buttondown::Error`, so one rescue is
enough to be safe. Rescue the specific classes where you want to act differently.

| Class | Raised when | Safe to retry? |
|---|---|---|
| `ConfigurationError` | No token at construction | No — fix the config |
| `InvalidEmailError` | Blank or obviously malformed address. **No request is made** | No |
| `SubscriberSuppressedError` | 400 with the `subscriber_suppressed` code | No |
| `BadRequestError` | A validation failure. Read `#code` and `#body` | No |
| `AuthenticationError` | 401 | No |
| `FeatureDisabledError` | 403 with the `feature_disabled` code | No |
| `ForbiddenError` | Any other 403 | No |
| `NotFoundError` | 404 | No |
| `UnprocessableEntityError` | 422 | No |
| `RateLimitError` | 429. Exposes `#retry_after` when the header is sent | Yes, after a wait |
| `ServerError` | 5xx | Yes |
| `TimeoutError` | Connect, read or write timed out | Yes |
| `ConnectionError` | DNS, TLS or socket failure | Yes |
| `InvalidResponseError` | A 2xx whose body wasn't usable JSON | Yes |

Every HTTP error carries `#status`, `#code`, `#body`, `#raw_body` and `#headers`:

```ruby
begin
  client.subscribe(email)
rescue Buttondown::SubscriberSuppressedError
  # terminal; retrying won't help
rescue Buttondown::RateLimitError => e
  retry_in(e.retry_after || 1.hour)
rescue Buttondown::ConnectionError, Buttondown::ServerError
  retry_later # the default collision behavior makes this idempotent
rescue Buttondown::APIError => e
  report(status: e.status, code: e.code, body: e.body)
end
```

Connection failures are wrapped, but the original exception is preserved as
`#cause` if you need it.

In Rails, that makes the retry policy for a job a single line:

```ruby
retry_on Buttondown::ConnectionError, Buttondown::ServerError
discard_on Buttondown::SubscriberSuppressedError, Buttondown::InvalidEmailError
```

Email validation before the request is deliberately loose, so the gem is never
stricter than the API itself. One consequence: dotless hosts like
`user@localhost` are rejected.

### API version

Requests pin `X-API-Version: 2026-04-01`. Override it per client:

```ruby
Buttondown::Client.new(token, api_version: "2025-01-01")
```

Timeouts are configurable the same way — `open_timeout:` (default 5s),
`read_timeout:` and `write_timeout:` (default 10s).

## Development

After checking out the repo, run `bin/setup` to install dependencies, then
`bin/console` for an interactive prompt.

`bin/ci` runs everything CI runs — tests, RuboCop, undercover and
bundler-audit. `bin/test` runs just the tests.

## Releasing a new version

Update `CHANGELOG.md`, then from a clean `main`:

```
bin/release 0.1.1
```

That runs `bin/ci`, bumps `lib/buttondown/version.rb`, tags, and pushes the
gem. One-time setup: `gem signin`.

## Contributing

Bug reports and pull requests are welcome at
https://github.com/nickhammond/buttondown.

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).

---

Built and maintained alongside [Shipyrd](https://shipyrd.io) — deployment
dashboards for Kamal.
