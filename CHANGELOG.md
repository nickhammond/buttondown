# Changelog

All notable changes to this gem are documented here. The error classes are part
of the public API -- callers rescue them by name -- so every change to the error
hierarchy is listed.

## 0.3.1 - 2026-11-23

- `Net::HTTPBadResponse` and `Net::HTTPHeaderSyntaxError` are now wrapped as
  `Buttondown::ConnectionError`. Neither descends from `IOError`, so both
  escaped unwrapped -- past a `retry_on Buttondown::ConnectionError` that the
  README asks for. `Net::ProtocolError` is deliberately still not rescued: it
  would also catch HTTP status exceptions

## 0.3.0 - 2026-11-23

- **Breaking:** `#subscribe` no longer sends a collision behavior of its own,
  so Buttondown's documented default applies: a repeat address raises
  `Buttondown::EmailAlreadyExistsError` rather than merging into the existing
  subscriber. Pass `collision_behavior: "add"` to keep the old behavior
- Removed `Buttondown::Client::DEFAULT_COLLISION_BEHAVIOR`. There is no gem
  default left to name

## 0.2.1 - 2026-11-23

- `Buttondown::Client#subscribe` now passes any further attributes to the API:
  `ip_address`, `tags`, `notes`, `metadata`, `referrer_url`,
  `referring_subscriber_id` and the `utm_*` fields. `ip_address` and the
  `utm_*` fields can only be set at creation, so they were previously
  unreachable
- `collision_behavior:` is now one of those attributes rather than its own
  keyword. Existing calls are unaffected: it still goes out as the
  `X-Buttondown-Collision-Behavior` header, and never as a field

## 0.2.0 - 2026-11-23

- Added `Buttondown::Client#subscriber`, covering
  `GET /v1/subscribers/{id_or_email}`. Takes a Buttondown id or an email
  address, returns a `Buttondown::Subscriber`, and raises
  `Buttondown::NotFoundError` when no subscriber matches
- Added `Buttondown::Client#update_subscriber`, covering
  `PATCH /v1/subscribers/{id_or_email}`. Takes a Buttondown id or an email
  address and any attributes the API accepts, and returns the updated
  `Buttondown::Subscriber`
- Added `Buttondown::Client#unsubscribe`, which sets the type to
  `"unsubscribed"` with an optional `reason:`. An `unactivated` subscriber
  cannot be unsubscribed and raises `Buttondown::BadRequestError`
- Added `Buttondown::ConflictError`, mapped from 409. The OpenAPI spec
  documents 409 on every subscriber endpoint, so it also applies to the
  existing calls, which previously surfaced it as a bare `APIError`
- Packaging: development files no longer ship in the gem. `.rubocop.yml`,
  `.undercover`, `AGENTS.md`, `Gemfile`, `Guardfile`, `Rakefile` and the
  gemspec itself are excluded, leaving `lib/`, `README.md`, `LICENSE.txt` and
  `CHANGELOG.md`

## 0.1.1 - 2026-11-22

Initial release. No 0.1.0 was ever published; the version was bumped before the
first push to RubyGems.

- `Buttondown::Client#subscribe`, covering `POST /v1/subscribers`
- Token from the constructor, defaulting to `ENV["BUTTONDOWN_API_KEY"]`; a blank
  token raises `Buttondown::ConfigurationError` at construction
- `type:` defaults to `"regular"`, skipping Buttondown's double opt-in for the
  subscriber. Pass `nil` to let Buttondown's own default apply
- `collision_behavior:` defaults to `"add"`, merging a duplicate instead of
  failing. Pass `nil` to make a duplicate raise
- Returns a `Buttondown::Subscriber`
- Full error hierarchy under `Buttondown::Error`, including
  `EmailAlreadyExistsError` and `SubscriberBlockedError`, mapped from the
  `email_already_exists` and `subscriber_blocked` codes
- No runtime dependencies; Net::HTTP from stdlib
