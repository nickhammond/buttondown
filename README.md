# Buttondown

A Ruby client for the [Buttondown](https://buttondown.com) newsletter API.

No runtime dependencies — just Net::HTTP from the standard library.

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

client.subscriber("subscriber@example.com") # or a "sub_..." id
```

### Options

One keyword has a default, so the call above is the same as writing:

```ruby
client.subscribe(email, type: "regular")
```

Everything else is sent only if you ask for it, Buttondown's own defaults
standing in otherwise.

Anything else Buttondown accepts goes along as given — `ip_address`, `tags`,
`notes`, `metadata`, `referrer_url`, `referring_subscriber_id` and the `utm_*`
fields:

```ruby
client.subscribe(email,
                 ip_address: request.remote_ip,
                 referrer_url: request.referer,
                 tags: ["signup-form"],
                 utm_source: params[:utm_source])
```

Attributes aren't checked against that list, so the API rejects an unknown one
with a 422 and a new field needs no gem release.

`ip_address` is worth sending from a web form: Buttondown uses it to locate the
subscriber and to judge whether the signup is legitimate. It and the `utm_*`
fields can **only** be set at creation — the update endpoint doesn't accept
them, so a value missed here is gone.

`type:` is the state the subscriber starts in.

| Value | Effect |
|---|---|
| `"regular"` (default) | Subscribed immediately, skipping Buttondown's double opt-in |
| `nil` | Sends no type, so Buttondown's own default applies: `"unactivated"` until they confirm by email |

`collision_behavior:` decides what happens when the address is already a
subscriber. Pass it like any other attribute; the gem sends it as a header
rather than a field, which is Buttondown's business and not yours.

| Value | Effect |
|---|---|
| unset (default) | Buttondown's `no_op`: a duplicate raises `EmailAlreadyExistsError`, which is how you detect "already subscribed" |
| `"add"` | Merges into the existing subscriber and returns it, so a duplicate is a success |
| `"overwrite"` | Replaces the existing data. A terminal subscriber raises `SubscriberSuppressedError` |

Leaving it unset is Buttondown's behavior, not the gem's idea of a good
default — pick one deliberately. `"add"` is the forgiving choice for a
signup form, at the cost of silently reactivating someone who unsubscribed.

What Buttondown does with those values — opt-in states, how collisions resolve,
rate limits — is documented at [docs.buttondown.com](https://docs.buttondown.com).

### Retrieving a subscriber

`subscriber` takes either a Buttondown id or an email address — the endpoint is
`/subscribers/{id_or_email}`, so there's no need to store the id:

```ruby
client.subscriber("sub_0dys87p9a08v1ttfy6ascstnpx")
client.subscriber("reader@example.com")
```

It returns a `Buttondown::Subscriber`, and raises `NotFoundError` when nobody
matches. A blank argument raises `InvalidArgumentError` before any request.

### Updating a subscriber

`update_subscriber` patches whatever attributes you give it and returns the
updated subscriber:

```ruby
client.update_subscriber("reader@example.com", notes: "met at a conference")
client.update_subscriber("sub_0dys87p9a08v1ttfy6ascstnpx",
                         metadata: {plan: "pro"}, commenting_disabled: true)
```

Buttondown accepts `type`, `email_address`, `tags`, `notes`, `metadata`,
`referrer_url`, `commenting_disabled`, `unsubscription_reason` and
`email_which_prompted_unsubscription_id`. Attributes are passed through rather
than checked against that list, so the API rejects an unknown one with a 422
and a new field needs no gem release.

Only the attributes you pass are touched. Calling it with none raises
`InvalidArgumentError` before any request, and `NotFoundError` means nobody
matched.

### Unsubscribing

`unsubscribe` is the update worth naming — it sets the type to
`unsubscribed`:

```ruby
client.unsubscribe("reader@example.com")
client.unsubscribe("reader@example.com", reason: "too many emails")
```

`reason:` is free text stored as `unsubscription_reason`. Calling it twice on
an already-unsubscribed subscriber is harmless — it stays unsubscribed.

Not every subscriber can be unsubscribed, though. One still in double opt-in
raises `BadRequestError` with the code `subscriber_type_invalid`: Buttondown
refuses to unsubscribe an `unactivated` record and directs you to delete it
instead, which this gem deliberately cannot do. Check `unactivated?` first if
that case is reachable in your flow.

This is almost always what you want when someone asks to stop receiving
email. The subscriber keeps their id, their history and their stats — opens,
clicks, tags, the date and reason they left — and Buttondown remembers the
opt-out:

```ruby
client.unsubscribe("reader@example.com")
client.subscribe("reader@example.com", collision_behavior: "overwrite")
# => raises Buttondown::SubscriberSuppressedError
```

Two sharp edges, both verified against the API:

- `collision_behavior: "add"` **does** reactivate an unsubscribed subscriber,
  and `regular?` then reports true because of it. Check `terminal?` first, or
  pass `collision_behavior: "overwrite"` and rescue
  `SubscriberSuppressedError`. Sending no collision behavior at all — the
  default — raises `EmailAlreadyExistsError` instead, which is the safe
  outcome.
- `update_subscriber(type: "regular")` reactivates one too, and bypasses
  suppression entirely — no error at all.

Removing a subscriber outright isn't supported. Deleting takes the history and
the stats with it, and Buttondown then has no record that the person opted
out, so a later `subscribe` recreates them as `regular` with no error at all.

### The subscriber

`subscribe` returns a `Buttondown::Subscriber`, a thin read-only view of the
JSON Buttondown sent back:

```ruby
subscriber = client.subscribe("subscriber@example.com")

subscriber.id            # => "sub_..." (a TypeID on 2026-01-01 and later)
subscriber.email_address # => "subscriber@example.com"
subscriber.type          # => "regular"
subscriber.to_h          # the raw parsed body
```

A merged duplicate also comes back as a success, returning the pre-existing
record, so with `collision_behavior: "add"` check the type before assuming
the address is active:

```ruby
subscriber.regular?     # will receive email
subscriber.unactivated? # created, not yet confirmed
subscriber.terminal?    # unsubscribed, blocked, complained or undeliverable
```

Fields without a reader stay reachable, so a new API field doesn't need a gem
release:

```ruby
subscriber[:creation_date]
```

### Errors

Everything the gem raises descends from `Buttondown::Error`, so one rescue is
enough to be safe. Rescue the specific classes where you want to act differently.

| Class | Raised when | Safe to retry? |
|---|---|---|
| `ConfigurationError` | No token at construction | No — fix the config |
| `InvalidEmailError` | Blank or obviously malformed address. **No request is made** | No |
| `SubscriberSuppressedError` | 400 with the `subscriber_suppressed` code | No |
| `EmailAlreadyExistsError` | 400 with the `email_already_exists` code — the address is already a subscriber | No |
| `SubscriberBlockedError` | 400 with the `subscriber_blocked` code — Buttondown's firewall rejected the address | No |
| `BadRequestError` | A validation failure. Read `#code` and `#body` | No |
| `AuthenticationError` | 401 | No |
| `FeatureDisabledError` | 403 with the `feature_disabled` code | No |
| `ForbiddenError` | Any other 403 | No |
| `NotFoundError` | 404 | No |
| `ConflictError` | 409. The request collided with concurrent work on the record | Yes |
| `UnprocessableEntityError` | 422 | No |
| `RateLimitError` | 429. Exposes `#retry_after` when the header is sent | Yes, after a wait |
| `ServerError` | 5xx | Yes |
| `TimeoutError` | Connect, read or write timed out | Yes |
| `ConnectionError` | DNS, TLS, socket or malformed-response failure | Yes |
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
  retry_later # pass collision_behavior: "add" to make this idempotent
rescue Buttondown::APIError => e
  report(status: e.status, code: e.code, body: e.body)
end
```

Connection failures are wrapped, but the original exception is preserved as
`#cause` if you need it.

In Rails, that makes the retry policy for a job a single line:

```ruby
retry_on Buttondown::ConnectionError, Buttondown::ServerError
discard_on Buttondown::SubscriberSuppressedError, Buttondown::InvalidEmailError,
           Buttondown::EmailAlreadyExistsError
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

`AGENTS.md` collects the API behavior that isn't in Buttondown's own docs, and
points at the OpenAPI spec to check before adding an endpoint.

## Releasing a new version

Give the CHANGELOG's `## Unreleased` section the version it's shipping as,
with the date — `## 0.3.0 - 2026-11-23` — and **commit that first**. Then,
from a clean `main`:

```
git commit -am "Cut the 0.3.0 CHANGELOG section"
bin/release 0.3.0
```

That order isn't housekeeping. `gem bump` aborts on a dirty working tree, so
an uncommitted CHANGELOG stops the release after `bin/ci` has already run.
And the tag and the packaged `.gem` capture the CHANGELOG as it stands when
the version is bumped, so committing it afterwards ships a release that files
its own changes under "Unreleased" — which is how 0.2.1 went out.

`bin/release` refuses to start unless `CHANGELOG.md` already has a
`## <version>` section, so forgetting costs a second instead of a release. It
then runs `bin/ci`, bumps `lib/buttondown/version.rb`, tags, pushes the gem to
RubyGems, and creates the GitHub release last, so a failure there leaves a
published gem missing its release rather than a release pointing at a version
that never shipped. The release notes themselves come from the pull requests
merged since the last tag, not from the CHANGELOG.

One-time setup: `gem signin`, and `gh auth login` for the release step.

## Contributing

Bug reports and pull requests are welcome at
https://github.com/nickhammond/buttondown.

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).

---

Built and maintained alongside [Shipyrd](https://shipyrd.io) — deployment
dashboards for Kamal.
