# Changelog

All notable changes to this gem are documented here. The error classes are part
of the public API -- callers rescue them by name -- so every change to the error
hierarchy is listed.

## Unreleased

- Added `Buttondown::EmailAlreadyExistsError` and
  `Buttondown::SubscriberBlockedError`, both subclasses of
  `Buttondown::BadRequestError`, mapped from the `email_already_exists` and
  `subscriber_blocked` codes. Previously both surfaced as plain
  `BadRequestError`; existing rescues keep working.

## 0.1.0 - 2026-11-21

Initial release.

- `Buttondown::Client#subscribe`, covering `POST /v1/subscribers`
- Token from the constructor, defaulting to `ENV["BUTTONDOWN_API_KEY"]`; a blank
  token raises `Buttondown::ConfigurationError` at construction
- `type:` defaults to `"regular"`, skipping Buttondown's double opt-in for the
  subscriber. Pass `nil` to let Buttondown's own default apply
- `collision_behavior:` defaults to `"add"`, merging a duplicate instead of
  failing. Pass `nil` to make a duplicate raise
- Returns a `Buttondown::Subscriber`
- Full error hierarchy under `Buttondown::Error`
- No runtime dependencies; Net::HTTP from stdlib
