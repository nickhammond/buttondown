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

subscriber = client.create_subscriber("subscriber@example.com")
subscriber.regular? # => true
```

`subscribe` is an alias for `create_subscriber`, whichever reads better at your
call site.

A blank token raises `Buttondown::ConfigurationError` from the constructor, so a
misconfigured client fails at boot rather than inside a background job later.

### Double opt-in

This is the most surprising thing about Buttondown, so it's worth stating plainly:
**Buttondown defaults to double opt-in.** A new subscriber lands as `unactivated`
and receives a confirmation email before they'll get anything else.

This gem sends `type: "regular"` by default, which skips that for the subscriber
you're creating. Pass `type: nil` to let Buttondown's own default apply instead:

```ruby
client.create_subscriber("subscriber@example.com", type: nil) # => unactivated, must confirm
```

Double opt-in cannot be turned off account-wide — it's a per-subscriber decision
at creation time.

### Duplicates, and why success doesn't mean "subscribed"

By default this gem sends `X-Buttondown-Collision-Behavior: add`, so subscribing
someone who already exists **merges into the existing record and succeeds** rather
than returning a 400.

The consequence is worth internalizing: a successful call does *not* mean this
person will receive your newsletter. You may have just merged into a record that
is `unactivated`, or one belonging to someone who unsubscribed. Check the type:

```ruby
subscriber = client.create_subscriber("subscriber@example.com")

if subscriber.regular?
  # they'll receive email
elsif subscriber.unactivated?
  # created, but still needs to confirm
elsif subscriber.terminal?
  # unsubscribed, blocked, complained or undeliverable -- don't mail them
end
```

Other collision behaviors:

```ruby
# Replace the existing record. Cannot change a terminal type, and raises
# Buttondown::SubscriberSuppressedError when it would.
client.create_subscriber(email, collision_behavior: "overwrite")

# Omit the header entirely, so a duplicate raises Buttondown::BadRequestError.
# This is the only way to detect "this address is already on the list".
client.create_subscriber(email, collision_behavior: nil)
```

Because the default merges, retrying a failed call is safe.

### Rate limits

Buttondown limits subscriber creation to **100 requests per day** by default,
growing with your newsletter's reputation. Two things follow:

- Call this from a background job, not inline in a web request
- Importing a list in bulk belongs in Buttondown's CSV import, not this endpoint

On a 429 the gem raises `Buttondown::RateLimitError`, which exposes
`#retry_after` in seconds when Buttondown sends the header and `nil` otherwise.

### Errors

Everything the gem raises descends from `Buttondown::Error`, so one rescue is
enough to be safe. Rescue the specific classes where you want to act differently.

| Class | Raised when | Safe to retry? |
|---|---|---|
| `ConfigurationError` | No token at construction | No — fix the config |
| `InvalidEmailError` | Blank or obviously malformed address. **No request is made** | No |
| `SubscriberSuppressedError` | They unsubscribed, bounced or complained | No — they opted out |
| `BadRequestError` | A validation failure. Read `#code` and `#body` | No |
| `AuthenticationError` | 401. Bad or revoked key | No |
| `FeatureDisabledError` | 403. Your plan lacks the feature, e.g. tags | No |
| `ForbiddenError` | Any other 403 | No |
| `NotFoundError` | 404 | No |
| `UnprocessableEntityError` | 422 | No |
| `RateLimitError` | 429. See `#retry_after` | Yes, after a wait |
| `ServerError` | 5xx | Yes |
| `TimeoutError` | Connect, read or write timed out | Yes |
| `ConnectionError` | DNS, TLS or socket failure | Yes |
| `InvalidResponseError` | A 2xx whose body wasn't usable JSON | Yes |

Every HTTP error carries `#status`, `#code`, `#body`, `#raw_body` and `#headers`:

```ruby
begin
  client.create_subscriber(email)
rescue Buttondown::SubscriberSuppressedError
  # they opted out; don't retry and don't report it as a failure
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

Note that email validation here is deliberately loose — the gem should never be
stricter than Buttondown itself, so it rejects only what no mail server would
accept. One known consequence: dotless hosts like `user@localhost` are rejected.

### API version

Requests pin `X-API-Version: 2026-04-01`. Without a pinned version Buttondown
uses whatever is set on your account's settings page, which can change under you.
Override it per client:

```ruby
Buttondown::Client.new(token, api_version: "2025-01-01")
```

Timeouts are configurable the same way — `open_timeout:` (default 5s),
`read_timeout:` and `write_timeout:` (default 10s).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run
`bin/test` to run the tests and `bundle exec standardrb` to lint. You can also
run `bin/console` for an interactive prompt.

## Releasing a new version

`bin/release` bumps the version, tags it, and pushes to GitHub and RubyGems.

```
bin/release 0.1.1
```

## Contributing

Bug reports and pull requests are welcome at
https://github.com/nickhammond/buttondown.

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).

---

Built and maintained alongside [Shipyrd](https://shipyrd.io) — deployment
dashboards for Kamal.
