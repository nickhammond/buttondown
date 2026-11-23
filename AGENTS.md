# Working on this gem

A dependency-free Ruby client for the Buttondown newsletter API, extracted from
[Shipyrd](https://shipyrd.io). Four methods, Net::HTTP from stdlib, no runtime
dependencies. Keep it that way: a dependency needs a reason that outweighs
being installable anywhere.

## Scope

`Buttondown::Client` covers four calls:

| Method | Endpoint |
|---|---|
| `subscribe` | `POST /v1/subscribers` |
| `subscriber` | `GET /v1/subscribers/{id_or_email}` |
| `update_subscriber` | `PATCH /v1/subscribers/{id_or_email}` |
| `unsubscribe` | `PATCH` with `type: "unsubscribed"` |

There is deliberately **no delete**. Deleting takes the subscriber's history
and stats with it, and leaves Buttondown with no record of the opt-out, so a
later `subscribe` recreates them as `regular` with no error. Unsubscribing
keeps the record, which is what almost every caller wants. Delete may come
back as its own clearly-labelled method; it is not a priority.

Methods are named for the domain action, not the HTTP verb: `subscribe`, not
`create_subscriber`. `subscriber(id)` follows Octokit's noun convention.

## Facts about the API that the docs don't tell you

Buttondown's prose docs are a few hundred characters per endpoint. The
**OpenAPI spec at `https://docs.buttondown.com/openapi.json`** (3.1.0, 77
paths, 133 operations, 234 schemas) is the real reference — check it before
guessing or probing, and see "Adding an endpoint" below.

Things verified against the live API, each of which cost a round trip:

- **IDs are TypeIDs** (`sub_0dys87p9a08v1ttfy6ascstnpx`) on the pinned
  `2026-04-01` version, not bare UUIDs. Error messages sometimes quote the
  legacy UUID instead.
- **Error bodies are `{code, detail, metadata}`.** `metadata` may carry a
  `documentation_url`. The client reads `code` then `detail`.
- **A create returns 201 with ~47 fields.** `Subscriber` has readers for three
  of them; the rest go through `#[]` and `#to_h`, so a new API field needs no
  gem release.
- **`@example.com` is rejected by Buttondown's firewall** with 400
  `subscriber_blocked`. Undocumented, and it means you cannot smoke-test with a
  reserved domain.
- **An invalid `X-API-Version` returns `invalid_input`**, not the
  `invalid_api_version` the docs claim.
- **409 is documented on every subscriber endpoint** and is the one 4xx worth
  retrying.
- **The whole API has three header parameters**:
  `X-Buttondown-Collision-Behavior` (on `/subscribers` and `/tags`) and
  `X-Buttondown-Bypass-Firewall`. Don't generalise `collision_behavior:` into a
  headers hash for a third header that doesn't exist. The collision header's
  documented default when absent is `no_op`, which is what the gem relies on:
  it sets no default of its own so Buttondown's stands.
- **`ip_address`, `referring_subscriber_id` and the `utm_*` fields are
  create-only.** `SubscriberUpdateInput` does not accept them, so a value
  missed at creation cannot be backfilled. `ip_address` is the one to care
  about: Buttondown uses it for location and to judge whether a signup is
  legitimate. A malformed one is refused with 422 `invalid_input`
  (`ip_any_address`), and `country` comes back nil on the create response
  because location resolves asynchronously.
- **An `unactivated` subscriber cannot be unsubscribed.** `PATCH` with
  `type: "unsubscribed"` returns 400 `subscriber_type_invalid` and directs you
  to delete the record instead -- which this gem can't do. Unsubscribing an
  already-unsubscribed subscriber, by contrast, is a harmless no-op.
- **Rate limit is 100 creates/day**, growing with newsletter reputation. The
  loose local email check exists to keep junk from spending it.

### The reactivation footguns

Both are real, both are documented in the README, and both will silently mail
someone who asked you to stop:

- `collision_behavior: "add"` **reactivates an unsubscribed subscriber**, and
  `Subscriber#regular?` then reports `true` because of it. So `regular?` is the
  wrong guard after a subscribe. Check `terminal?` first, or pass
  `collision_behavior: "overwrite"` and rescue `SubscriberSuppressedError`.
  The gem sends no collision header unless asked, so the default path raises
  `EmailAlreadyExistsError` instead -- safe, but one override away.
- `update_subscriber(type: "regular")` reactivates one too, bypassing
  suppression entirely — no error at all.

Counterintuitively, `"overwrite"` is the *safest* collision behavior for
honoring opt-outs; `"add"` is the one that resurrects people.

## Adding an endpoint: read the spec first

**Check `https://docs.buttondown.com/openapi.json` before writing anything.**
The prose docs run a few hundred characters per endpoint and omit response
shapes, status codes and error codes; the spec has all of them.

It is deliberately **not** vendored here. It is 589KB, it changes on
Buttondown's schedule rather than ours, and a stored copy goes stale without
anyone noticing — which is worse than no copy. Fetch it when you need it.

For the endpoint you are adding, pull out:

- **Path and verb.** `{id_or_email}` in the path means an email address works
  in place of an id, which is worth exposing rather than making callers store
  ids.
- **The request schema.** `additionalProperties: false` means the API rejects
  unknown attributes itself, so the client does not need to filter them — see
  `update_subscriber`, which passes attributes straight through.
- **Every documented response status**, and whether `STATUS_ERRORS` already
  maps it. An unmapped status surfaces as a bare `APIError`, which tells a
  caller nothing. 409 arrived this way.
- **The error code enums for that operation** — they are per-operation, e.g.
  `SubscriberInputValidationErrorCode`, `UpdateSubscriberErrorCode`,
  `TagErrorCode` — and whether any deserves a class in `ERROR_CODES`.
- **Header parameters.** Only three exist in the whole API; see below.

Some useful shapes, no dependencies needed:

```sh
curl -s https://docs.buttondown.com/openapi.json -o /tmp/bd.json

# verbs and documented statuses for one path
ruby -rjson -e 'spec = JSON.parse(File.read("/tmp/bd.json"))
  spec["paths"]["/subscribers/{id_or_email}"].each { |verb, op|
    puts "#{verb.upcase}: #{op["responses"].keys.sort.join(", ")}" }'

# every error code enum, to compare against ERROR_CODES
ruby -rjson -e 'JSON.parse(File.read("/tmp/bd.json"))["components"]["schemas"]
  .select { |name, s| name.end_with?("ErrorCode") && s["enum"] }
  .each { |name, s| puts "#{name}: #{s["enum"].join(", ")}" }'
```

Then confirm against the live API anyway. The spec documents 409 on every
subscriber endpoint without describing it, omits codes the API really returns
(`subscriber_blocked` on create), and states allowed values for the collision
header only in prose. The spec tells you what to look for; the API tells you
what happens.

## Testing

`bin/ci` is the gate: tests, RuboCop, undercover, bundler-audit. Run it before
committing, and **check its exit code** — piping it into `grep` masks the
failure, which has already shipped one broken push.

- WebMock blocks all outbound connections. A forgotten stub fails loudly, and
  `NetConnectNotAllowedError` descends from `Exception`, so the client's
  `rescue *CONNECTION_ERRORS` can't swallow it into a passing test.
- **No live data in fixtures.** Every address is `nick@example.com`; the create
  fixture is three hand-written fields, not a captured 47-field body. Real IDs,
  addresses and the API token have never been committed — keep it that way.
- Undercover enforces coverage on changed lines against `origin/main`. If it
  flags comment lines as uncovered, the lcov report is stale — usually because a
  one-off script wrote its own. `rm -rf coverage` and re-run.

## Verifying against the live API

Worth doing when adding an endpoint, because the docs don't describe responses.
`BUTTONDOWN_API_KEY` lives in `.env` (gitignored; never commit it, never send
it anywhere but Buttondown).

- Use plus-addressed `nick+something@fromthekeyboard.com`. `@example.com` is
  firewall-blocked, and a domain you don't control mails a stranger.
- `type: "regular"` subscribes immediately and may send a welcome email.
- **Clean up.** The gem can't delete, so use a raw `DELETE /v1/subscribers/{id}`.
- Keep the throwaway scripts out of the repo.

## Conventions

- **The client routes, the caller doesn't.** A caller passes attributes and the
  client decides what Buttondown wants in a header rather than the body --
  `collision_behavior` is an ordinary attribute to `subscribe` and becomes
  `X-Buttondown-Collision-Behavior`. Nothing above the request plumbing names
  Net::HTTP or a header.
- **The error hierarchy is public API** — callers rescue by name, so every
  change to it goes in the CHANGELOG. Codes are checked before statuses,
  because a code is more specific than the status carrying it.
- **Keep comments few.** They explain why, not what, and the bar is "a reader
  cannot get this from the code or the README". Usage belongs in the README;
  repeating it above a method means two copies to keep true, and the method
  comments were cut back once already for exactly that. A comment that stops
  someone unpicking a deliberate choice is worth keeping -- why the timeout
  constants are rescued in that order, why the URL is interpolated rather than
  joined. `Style/Documentation` is off because a cop demanding one above every
  class produces filler.
- **Don't let a comment outlive its truth.** Two have already had to be walked
  back: one promised the gem keeps addresses out of error messages (it passes
  Buttondown's `detail` through verbatim), another described an `inspect`
  override that had been removed.
- **RuboCop is vanilla** with narrow, commented exceptions in `.rubocop.yml`.
  `Metrics/ClassLength` has been raised three times as endpoints were added; the
  next step is extracting the request layer into its own class, not a fourth
  bump.
- Releasing is documented in the README under "Releasing a new version". The
  CHANGELOG heading was the step to get wrong -- 0.2.1 shipped filed under
  "Unreleased" -- so `bin/release` now aborts unless the version has a
  `## <version>` section. That guard reads the worktree, so a heading written
  but not committed clears it and then trips `gem bump`'s dirty-tree check
  after `bin/ci` has run: commit it first.
- The gemspec ships `lib/`, the README, LICENSE and CHANGELOG only. Add new
  dev-only files at the repo root to its reject list.

## Git

- Work on a branch and open a PR; `main` is pushed to directly only for
  trivial fixes.
- **Write PR bodies and commit messages for the next reader, not for yourself.**
  No `claude.ai/code/session_...` links or other internal references: they 403
  for everyone else, so they tell a reviewer nothing and just add noise to a
  public repo. Put the reasoning in the message instead. This holds even when
  tooling defaults ask for an attribution line.
- **Never delete a PR's base branch while that PR is open.** It closes the PR,
  and GitHub won't let you reopen it once the base is gone — that cost a
  renumbered PR already. Retarget first.
- Prefer a small stack over duplicating a shared helper across two PRs, and say
  the merge order in the PR body.
