> This pull request lives in Cedarwood Studio's fork and stays there. It's one stage of an unsolicited sample upgrade, published so the work can be read. Nobody at the Postal project asked for it, and nothing has been sent to the project. Corrections go to hello@cedarwood.studio.

## S4: Rails 7.2 to 8.0

### What changed

- `Gemfile`: the rails pin moves from `= 7.2.4` to `= 8.0.5.2`, and `gem "cgi"` is added.
- `Gemfile.lock`: regenerated with `bundle lock --update rails connection_pool minitest --conservative`. The 12 framework gems and the `rails` gem itself move to 8.0.5.2. Outside the framework five gems move: loofah 2.25.1 to 2.25.3, nokogiri 1.19.3 to 1.19.7 and rails-html-sanitizer 1.7.0 to 1.7.2, all three forced by Action View 8.0.5.2, which requires rails-html-sanitizer 1.7.2 or later; and connection_pool 2.5.5 to 3.0.2 and minitest 5.27.0 to 6.1.0, which we asked for (see below). cgi stays in the lock at 0.5.1, now because the Gemfile names it and no longer because Rails depends on it. Nothing else moves and nothing leaves the lock. json stays at 2.7.1.
- `app/models/concerns/has_authentication.rb`: `has_secure_password validations: false` gains `reset_token: false`. From Rails 8.0 `has_secure_password` defines its own `password_reset_token` method, which returns a signed token valid for 15 minutes and hides the `password_reset_token` column this application stores its own token in. Without the option the password reset flow breaks in three places: the application's 24 character token is never saved, the e-mail carries the Rails signed token in its place, and the link in the e-mail finds no user.
- `spec/requests/password_reset_spec.rb` (new, 6 examples): requests a reset, reads the token from the database column and from the e-mail, follows the e-mailed link to set a new password, and checks the token is cleared, that the link stops working afterwards, and that it is refused after 25 hours. With the option removed, 5 of the examples fail on 8.0.5.2 (the first run had 7 examples and 5 failed; we then removed one, see "What needed judgment"). All 6 pass on 7.2.4 without the option, so they pin the behavior the application had before the hop.
- `spec/lib/postal/config_schema_spec.rb` (new, 1 example): builds the configuration with two SMTP relays, one with `?ssl_mode=TLS`, which runs the `CGI.parse` call in `lib/postal/config_schema.rb:80`. No test ran that line before.
- `spec/lib/postal/message_parser_spec.rb` (1 example added): parses an HTML message with a tracked link whose address contains `&amp;`, which runs the `CGI.unescapeHTML` call in `lib/postal/message_parser.rb:121`, and checks the stored link is the unescaped address. No test ran that line before. A failure on that line is rescued and the message goes out untracked, so the example asserts on the tracked link count as well.
- `spec/requests/vary_header_spec.rb` (new, 2 examples): pins the declared header change below on one rendered response and its absence on one redirect.
- `load_defaults` is untouched and stays at 7.0. No file from `bin/rails app:update` was adopted (see "What needed judgment").

### Declared behavior changes

- **Vary header on rendered responses.** 134 of the 170 recorded requests differ, all in the same way: the response had no `Vary` header on 7.2.4 and has `Vary: Accept, X-Requested-With` on 8.0.5.2. No status, no body and no other header differs in any request. The other 36 requests are identical. The cause is in Rails. The Action Pack 8.0 changelog lists it under 8.0.5.2 as "Set and extend the Vary header for rendered responses according to the request headers used in format negotiation" (https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md), and the code is `_set_vary_header` in `action_controller/metal/rendering.rb` of the installed Action Pack. We declared it in `expected-differences.json` for the `Vary` header only, on any request. It affects a shared cache, CDN or caching proxy in front of the web interface or the API, which will now keep separate copies of a response per `Accept` and `X-Requested-With` value. That's the safer behavior, and browsers are unaffected. It needs client sign-off because a cache hit rate can drop, and because anything that asserts on the exact set of response headers will see one more.
- **`bin/rails db:migrate` on an empty database.** From Rails 8.0, `db:migrate` on a database with no tables loads `db/schema.rb` first and then runs only the migrations that are still pending; before, it ran every migration from the first. This reaches the developer script `bin/update:24`. The production path, the `postal:update` task in `lib/tasks/postal.rake`, is unchanged: it already loads the schema when the database is empty and migrates otherwise. For this application the new behavior is an improvement, because running every migration from nothing fails on 7.1.6 and 7.2.4 alike (the fourth S3 review measured that). We didn't measure it on 8.0.5.2 in this stage. Source: the Active Record 8.0 changelog (https://github.com/rails/rails/blob/v8.0.5.2/activerecord/CHANGELOG.md). No recorded request can show it.

### Declared after review

The review passed the stage and found three differences the checks couldn't see. No code changed for this section.

- **Vary header: the "before" was incomplete.** This corrects the first bullet under "Declared behavior changes" and the matching follow-up. Our recorded requests send no `Accept` header, and for those the response had no `Vary` header on 7.2.4. A request that does send `Accept`, as browsers, curl and HTTP libraries do, already got `Vary: Accept` on 7.2.4 and gets `Vary: Accept, X-Requested-With` on 8.0.5.2. The review measured it: of 230 requests in production, 27 carried `Vary: Accept` on 7.2.4 and all 27 had sent an `Accept` header; through puma, `GET /ip` and `POST /api/v1/send/message` with `Accept: */*` change from `Accept` to `Accept, X-Requested-With`. So for real traffic the change is one added field name, `X-Requested-With`, and a shared cache in front of the application was already keeping separate copies per `Accept` value. What is new for a cache or CDN is the split on `X-Requested-With`, and for requests with no `Accept` header, the header itself. The header on 8.0.5.2 is exactly what the stage declared on every request the review made. The question for the client becomes: does a CDN, caching proxy or monitor depend on the exact value of `Vary`, or on responses to requests without an `Accept` header having no `Vary`? Source: the Action Pack changelog, under 8.0.5.2 (https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md). Measurement: `review-runs/try-1794552515.log` and `review-runs/try-1794552582.log`.
- **Error entries in the Rails log change shape.** This log is written only when `LOGGING_RAILS_LOG_ENABLED=true`. On 7.2.4 an error with a cause is logged as the error line, its trace, then a `Causes:` block naming the cause. On 8.0.5.2 the error line is followed by a `Caused by:` line, then an `Information for:` section with the trace, then an `Information for cause:` section with the cause's trace. One class name in those entries changes as well: a malformed query string is reported as `ActionDispatch::ParameterTypeError` where it was `Rack::QueryParser::ParameterTypeError`, because Action Pack 8.0 parses request parameters itself. The responses are the same on both versions (400). It affects anyone who parses, searches or alerts on this optional log; no HTTP client sees it. This is a measurement: 1241 normalized log lines on 7.2.4 against 1249 on 8.0.5.2 for the same 230 requests (`review-runs/try-1794552515.log`). The parameter parsing change is in the Action Pack 8.0 changelog (https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md); we found no changelog entry for the new layout of the error entry, so the measurement is the source for that part.
- **The message of a missing parameter error changes.** The message of `ActionController::ParameterMissing` changes from "param is missing or the value is empty: domain" to "param is missing or the value is empty or invalid: domain". No response carries it: the request answers 400 with an empty body on both versions. It appears in the `exception_message` field of Postal's own request log line (`config/initializers/logging.rb:8`), which is on by default, and in the Rails log. The review didn't capture what Sentry receives, but the same exception object goes there. It affects a log search, a Sentry rule or an alert that matches the old text. The new wording comes with `params.expect` in the Action Pack 8.0 changelog (https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md). Measurement: `review-runs/try-1794552739.log`.

The review also corrected two statements in these notes, neither a behavior change. With `reset_token: false` removed, 4 of the 6 password reset examples fail on 8.0.5.2, not 5; the 5 was the count from the first draft of 7 examples. And `bin/rails db:migrate` on an empty database, which we declared and hadn't measured, is now measured: on 8.0.5.2 it exits 0 with 28 tables and 19 migration versions recorded, and on 7.2.4 it fails on the first migration (`review-runs/try-1794551998.log`). The declaration stands.

### Checked, no change needed

- **The cgi gem.** The roadmap said two files use `CGI` without requiring it and that the tracked-link line would fail silently. We measured something narrower. `lib/postal/config.rb:6` requires `cgi` before either file is loaded. With the Gemfile entry removed in a throwaway copy, the application on Ruby 3.4.6 still boots and both calls still work, because Ruby 3.4 ships cgi 0.4.2 as a default gem. So without the entry the hop wouldn't break those lines on this Ruby; it would silently move cgi from 0.5.1 to 0.4.2, and it would break them on a Ruby that no longer ships cgi. With the entry the application keeps 0.5.1 on any Ruby. The entry is the right fix; the reason is slightly different from the one in the plan.
- **The Delivery constructor.** `Delivery.new` is called from two places: `Delivery.create`, with a Hash built by the application's own `stringify_keys` helper (`Hash#transform_keys`), and `Message#deliveries`, with row hashes from the mysql2 client. Neither is a `HashWithIndifferentAccess`, and the application has no `with_indifferent_access` call in `app`, `lib` or `config`. The stringify_keys change doesn't apply.
- **Associations in namespaced models.** The application has no namespaced model: every model is a top-level class under `app/models`, and there is no `has_one`. The nested association change doesn't apply.
- **Non-symbol keys in credentials.** The application has no encrypted credentials file. `config/initializers/secret_key.rb` assigns one key, `secret_key_base`, by method call. `spec/lib/secret_key_spec.rb` runs that path and passes on 8.0.5.2.
- **Unexecuted framework call sites.** `lib/postal/message_db/database.rb:333` calls `ActiveRecord::ConnectionAdapters::MySQL::ExplainPrettyPrinter.new.pp(result, time)` for slow queries. We ran that call on 8.0.5.2 against the test database with the application's own result wrapper and it prints the table as before. We saw that the constant is defined only once the Active Record connection pool has been created. Every path to a message database goes through a `Server` record first, so the pool exists by then; we didn't compare this with 7.2.4. `lib/migration_waiter.rb:47` (`Rails.const_defined?("Console")`) returns false in a server process on 8.0.5.2, and the migration waiter spec and boot variant pass.
- **The sanitizer, loofah and nokogiri.** They moved as the roadmap resolved. No recorded response body changed, and `app`, `lib` and `config` have no call to `sanitize`, `strip_tags` or `strip_links`.
- **Session cookie.** The application uses the cookie store, so the SameSite change for other session stores in 8.0.5.2 doesn't apply. The session continuity spec passes.

### What needed judgment

- **Lifting connection_pool and minitest.** The conservative update leaves both where 7.2 forced them (2.5.5 and 5.27.0), because Rails 8.0 accepts those versions too. The plan lists lifting them back, so we named both in the relock. connection_pool returns to 3.0.2, the version the lock held before the 7.2 hop. minitest goes to 6.1.0, not the 6.0.6 the lock held before: the resolver takes the newest, and 6.1.0 is what the roadmap's resolve predicted. Both reasons are recorded in `lock-moves.json`. The suite result is unchanged.
- **`bin/rails app:update`.** We ran it in a throwaway copy, answering no to every overwrite. It wants to overwrite the application's environment files, initializers, `bin` scripts and error pages, which follow the 7.0 layout and carry Postal's own settings, and it creates six new files: `config/initializers/new_framework_defaults_8_0.rb`, `bin/rubocop`, `public/400.html`, `public/406-unsupported-browser.html`, `public/icon.png` and `public/icon.svg`. We adopted none. The defaults file belongs to the stage that adopts the 8.0 defaults. `public/400.html` would change what a client receives for a bad request, which is a behavior change nobody asked for. The others are scaffolding the application doesn't use.
- **One example removed from the password reset spec.** Our first draft had an example that fetched the new password form with the e-mailed token. It failed on both versions for a reason unrelated to the hop: the HTML layout needs the asset pipeline, which the test environment doesn't have (the S3 notes record the same limit). We removed it before the first check. The form itself is covered by the recorded request "signed out: GET /login/reset/:token valid", which uses a stored token and is identical before and after apart from the `Vary` header.
- **The `to_time` deprecation warning.** We didn't set `to_time_preserves_timezone`. Setting it changes behavior, and the plan puts the retention cutoff test and the setting in later stages.
- **A spec for the Vary header.** The recorded requests already show the change. We added two small examples anyway so that the next hop's test run fails if the header changes again, as well as the recording.

### Results

These are from the second check (`S4-attempt-2`), green on the second of four attempts. The first attempt failed only because the `Vary` difference wasn't yet declared; tests, boot and lock were already clean.

- **Resolve:** no conflict. 5 gems moved outside the framework: 3 forced by the framework, 2 declared, 0 unexplained. No downgrade.
- **Boot:** all 7 boot variants start before and after: default, oidc, oidc-no-discovery, migration-waiter, rails-log, sentry, production. We also started the application as a server process (`require ./config/environment`) by hand: default, with OIDC, Sentry, the Rails log and the migration waiter switched on together, and in production. Each prints 8.0.5.2.
- **Tests:** 927 examples before, 937 after (10 added, all passing). 910 passing before, 920 after, 0 regressed, 0 missing. The 17 that don't pass are the same 17 as before (16 in `spec/lib/dns_resolver_spec.rb`, 1 in `spec/senders/smtp_sender_spec.rb`); they need live DNS and the sandbox runs with the network off.
- **Recorded requests:** 170 requests, 36 identical, 134 different and declared (the `Vary` header, nothing else), 2 masked as noise, 0 unexplained.
- **Deprecation warnings:** 0 before; 1 distinct warning after, 4 occurrences. Ruby deprecation warnings: 3 before, 3 after.

### Where the roadmap was wrong or silent

- The roadmap predicted the password reset break, the `Vary` change, the three forced gem moves and the cgi removal correctly.
- On cgi the mechanism was off, as described above: one of the application's own files requires it, and Ruby 3.4 still ships it, so the failure the roadmap described would appear only on a newer Ruby. The Gemfile entry is still needed.
- The roadmap said "the S1 password reset test" would gate this hop. No spec covered the reset flow before this stage. The recorded requests covered the reset pages with a token written straight to the column, which doesn't run the two lines that break. The new spec closes that gap.
- The roadmap's resolve for this hop started from the 7.1.6 lock, so it didn't show that a conservative update from the 7.2 lock leaves connection_pool and minitest at their lower versions. Lifting them needs both named in the relock.
- The five direct gems flagged as unreleased since 2022 (chronic, gelf, nifty-utils, sass-rails, turbolinks) caused no problem on 8.0.5.2.

### Deprecation warnings that remain

- 1 distinct Rails warning, 4 occurrences, all raised while the application boots (`config/environment.rb:7`): "`to_time` will always preserve the full timezone rather than offset of the receiver in Rails 8.1. To opt in to the new behavior, set `config.active_support.to_time_preserves_timezone = :zone`." It comes from the application not having adopted the 8.0 defaults, and no line of application code raises it. It's the next hop's work: the plan adds a test for the retention cutoff (`lib/postal/message_db/provisioner.rb:133`, the one `to_time` call in the application) before 8.1 removes the older behavior. A production boot prints no warning, because production doesn't report deprecations.
- 3 Ruby deprecation warnings, unchanged by this stage.

### Follow-ups we noticed and did not do

- `json` still isn't pinned below 3 in the Gemfile. The plan put the pin in S2 and it wasn't made there; the S3 reviews carried it as a risk. Active Support 8.0 passes an option that json 3 removed. The lock holds json 2.7.1 and this relock did not move it, so nothing is broken today, but any later `bundle update json` would break every `to_json` call. It's not in this stage's list, so we left it. It's one Gemfile line and should go in before the next relock or with it.
- Get the production MySQL or MariaDB server versions from the client before this stage ships. Rails 8.0 requires MySQL 5.6.4 or later (MariaDB 10.x is fine). The sandbox runs MariaDB 10.11.19 and the repository's `docker-compose.yml` names a MariaDB image; neither tells us what the client runs.
- Ask the client whether a CDN, a caching proxy or a monitor sits in front of the web interface or the API and depends on the `Vary` header or on the exact header set.
- Tell developers that `bin/update` on an empty database now loads the schema first.
- After this hop, the next migration a developer runs rewrites the first line of `db/schema.rb` from `ActiveRecord::Schema[7.1]` to `[8.0]`. Rails 8.0.5.2 loads the file as it is.
- The new password reset spec pins one thing that looks unintended: when the link in the e-mail has expired or never existed, `finish_password_reset` redirects on GET, but on POST it redirects and then carries on with a nil user. We asserted only on the GET. Worth a ticket outside the upgrade.
- From the S3 follow-ups, still open and untouched here: `app/models/route.rb:119`, the nine requests that answer 500 on every version, and the query for stored "Astana" time zones.

### Checks, before and after

| Check | Before | After |
|---|---|---|
| Examples run | 927 | 937 |
| Examples passing | 910 | 920 |
| Passing examples that now fail or are gone | | 0 |
| Rails deprecation warnings (distinct / occurrences) | 0 / 0 | 1 / 4 |
| Ruby deprecation warnings | 3 | 3 |
| Recorded HTTP behaviors identical | | 36 of 170 |

### Start-up checks

The application was loaded the way a server process loads it, once per configuration.

| Configuration | Before | After |
|---|---|---|
| default | starts | starts |
| oidc (`Postal::Config.oidc.enabled?`) | starts | starts |
| oidc-no-discovery (`Postal::Config.oidc.enabled?`, `config.discovery?`) | starts | starts |
| migration-waiter (`Postal::Config.migration_waiter.enabled?`) | starts | starts |
| rails-log (`Postal::Config.logging.rails_log_enabled?`) | starts | starts |
| sentry (`Postal::Config.logging.sentry_dsn`) | starts | starts |
| production (`Postal::Config.rails.environment`) | starts | starts |

### Which comparisons ran

In the sandbox: 927 examples compared one by one; 170 requests, with status compared on 170, bodies compared in full on 168 and not at all on 2.

On GitHub Actions (https://github.com/cedarwood-studio/postal/actions/runs/43382984773, success): 909 examples gated and 28 reported without gating; bodies compared in full on 163, through a single-value mask on 5 and not at all on 2; 6 of 6 declared differences observed there.

### Lock file

13 framework gems moved. 5 other gems moved, were added or were dropped, each for the reason given.

| Gem | From | To | Why |
|---|---|---|---|
| `connection_pool` | 2.5.5 | 3.0.2 | Restores the major version the lock held before the 7.2 hop (3.0.2). Active Support 7.2.4 required connection_pool below 3 and forced it down to 2.5.5; Active Support 8.0.5.2 has no upper limit, and the plan for this stage lists lifting it back. |
| `loofah` | 2.25.1 | 2.25.3 | rails-html-sanitizer 1.7.2 requires loofah (~> 2.25, >= 2.25.3) |
| `minitest` | 5.27.0 | 6.1.0 | Restores the major version the lock held before the 7.2 hop (6.0.6 then, 6.1.0 now, the version the roadmap's resolve for 8.0 predicted). Active Support 7.2.4 required minitest below 6 and forced it down to 5.27.0; Active Support 8.0.5.2 has no upper limit, and the plan for this stage lists lifting it back. |
| `nokogiri` | 1.19.3 | 1.19.7 | loofah 2.25.3 requires nokogiri (>= 1.19.5) |
| `rails-html-sanitizer` | 1.7.0 | 1.7.2 | actionview 8.0.5.2 requires rails-html-sanitizer (~> 1.6, >= 1.7.2) |

### Independent review

An independent review pass, which had no part in writing this stage, read the framework's component changelogs for the hop and every framework call the test suite loads and never runs, compared the change with any upgrade work the project has in flight, and tried to break it. It's a step of our process, and its time is on record below. No person has reviewed this stage yet.

- **Verdict:** pass
- **Findings:** 6, of which 6 the checks had not caught
- **Differences the review asked us to declare:** 3, all declared below
- **Rounds:** 1
- **Review time:** 18 minutes for the round that passed, 18 minutes over all rounds

### Behavior differences this stage declares

These need a person's sign-off. Each is a change in a recorded response that the stage explains.

- header:vary, in 134 recorded requests (`GET /.well-known/jwks.json`, `GET /api/v1/messages/deliveries`, `GET /api/v1/messages/message`, `GET /api/v1/send/message`, `GET /api/v1/send/raw`, `GET /ip` and 128 more): From Action Pack 8.0.5.2 a rendered response carries 'Vary: Accept, X-Requested-With' when the response format is not given by the URL; before, this application's responses carried no Vary header. Listed in the Action Pack 8.0 changelog as 'Set and extend the Vary header for rendered responses according to the request headers used in format negotiation': https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md

### Diff

```
.upgrade/accepted-differences.json        |   6 +++
 .upgrade/baseline/examples.json           |  10 +++++
 Gemfile                                   |   3 +-
 Gemfile.lock                              | 144 +++++++++++++++++++++++++++++++++++-----------------------------------
 app/models/concerns/has_authentication.rb |   2 +-
 spec/lib/postal/config_schema_spec.rb     |  23 ++++++++++++
 spec/lib/postal/message_parser_spec.rb    |  17 +++++++++
 spec/requests/password_reset_spec.rb      |  84 +++++++++++++++++++++++++++++++++++++++++
 spec/requests/vary_header_spec.rb         |  21 +++++++++++
 9 files changed, 236 insertions(+), 74 deletions(-)
```

- **Attempts:** 2
- **Versions after:** rails 8.0.5.2, ruby 3.4.6
