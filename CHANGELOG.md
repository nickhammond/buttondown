# Changelog

All notable changes to this gem are documented here. The error classes are part
of the public API -- callers rescue them by name -- so every change to the error
hierarchy is listed.

## Unreleased

- Added `Buttondown::Client#unsubscribe`, covering
  `PATCH /v1/subscribers/{id_or_email}` with `type: "unsubscribed"`. Takes a
  Buttondown id or an email address and an optional `reason:`, and returns the
  updated `Buttondown::Subscriber`
- Added `Buttondown::ConflictError`, mapped from 409. The OpenAPI spec
  documents 409 on every subscriber endpoint, so it also applies to the
  existing calls, which previously surfaced it as a bare `APIError`
- Added `Buttondown::Client#delete_subscriber`, covering
  `DELETE /v1/subscribers/{id_or_email}`. Takes a Buttondown id or an email
  address and returns `nil`; raises `Buttondown::NotFoundError` when no
  subscriber matches. Deletion is not unsubscribing and does not cancel a
  backing Stripe subscription
- Added `Buttondown::Client#subscriber`, covering
  `GET /v1/subscribers/{id_or_email}`. Takes a Buttondown id or an email
  address, returns a `Buttondown::Subscriber`, and raises
  `Buttondown::NotFoundError` when no subscriber matches
- Packaging: development files no longer ship in the gem. `.rubocop.yml`,
  `.undercover`, `Gemfile`, `Guardfile`, `Rakefile` and the gemspec itself are
  excluded, leaving `lib/`, `README.md`, `LICENSE.txt` and `CHANGELOG.md`.

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
