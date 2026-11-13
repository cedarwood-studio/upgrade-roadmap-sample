# Upgrade Roadmap: Postal from Rails 7.1.6 to 8.1.4.1

- **Repository:** postalserver/postal, commit `d96eddb` (October 1, 2026)
- **Prepared:** November 13, 2026, by Cedarwood Studio
- **Access used:** read-only checkout. Nothing was pushed, opened or changed in the repository.

## Review findings

This is the second report we produced for this commit. The first was generated on November 13, 2026 without the changelog rules, the removed-gem search, the unexecuted-call list, the start-up checks or the look at the project's own work, and it had no review before its stages began. A review afterward found four breaking lines it had missed, one of them already a defect in a finished stage. The first report, as corrected by that review, is in [`first-pass/ROADMAP.md`](first-pass/ROADMAP.md). Everything below this section is the second report as generated and then put through an independent review pass, a step of our own process that had no part in writing the report. No person has reviewed it yet. The estimate and the driver table are as generated.

**The first run's eight lines, in this report.** The first report's search confirmed four lines and its review added four. This report's search found all eight before its own review began. It reads one of them differently.

| Line | First report | This report |
|---|---|---|
| `config/environments/test.rb:28` | Found | Found |
| `app/models/credential.rb:34`, `app/models/webhook_request.rb:37` | Found | Found |
| `db/schema.rb:13` | Found, called a break on 8.1 | Found, and not a break at 8.1.4.1. Rails 8.1.4 reverted the column sorting, and both earlier passes missed that |
| `lib/migration_waiter.rb:18` | Missed | Found, by a rule, by the unexecuted-call list and in the project's own branch |
| `app/models/concerns/has_authentication.rb:8` | Missed | Found, by a rule from the Active Model changelog |
| `app/lib/worker/process.rb:164`, `app/lib/worker/process.rb:256` | Missed | Found, by the removed-gem search and by a rule |
| `Gemfile.lock:167`, the `json` pin | Missed | Found, by a rule on the lock file |

The rules behind the last four rows were written after the first review named those lines. Finding them again shows the rules work on a known answer. It doesn't show this search would find the next unknown one. The password reset line rests on its rule alone.

**What this report's own review added.** 11 items, listed under "Independent review" near the end and marked where they were corrected. Six are things no check in the plan would have shown. One was a defect in the plan as written.

**What carrying out the plan has shown since.** Stages S3 and S4 have run with a review after each, and [`EXECUTION.md`](EXECUTION.md) has the record. Three things there bear on this report:

- One item in it is wrong. S3's seventh change says development and test take their secret key from a different place from Rails 7.2.3 on. A stage review measured it on 7.1.6 and on 7.2.4, and in this application nothing changes. The item came from this report's own review, which read a changelog entry and didn't run it.
- This report didn't predict three small differences on the 7.2 hop that the stage reviews found by measuring: response headers for HEAD requests that end in an error page, the format of the Rails log's request and error lines, and the console prompt. None is in the release notes. Two are in a component changelog.
- The breaks it ranked highest for 7.2 and 8.0 were real when run. The migration waiter stopped the application from starting on 7.2.4. On 8.0.5.2, with the password reset fix taken out, 4 of the 6 new reset examples fail.

## Summary

Postal runs Rails 7.1.6, which passed end of life 408 days ago, on Ruby 3.4.6, which has 504 days left. The target is 8.1.4.1, three series away, and both series in between (7.2 and 8.0) are already past end of life too, so there's no reason to rest on either. The dependency resolver found a working set of gems for every hop; the one blocker is `annotate`, a development tool that caps Active Record below 8.0. Of 78 lines matched by documented breaking changes we confirmed 28 by reading, and the suite executes 4 of those 28. The suite's measured state is: "834 of 851 examples pass with the network off; 17 more pass with the network on; 5 fail in that run." The plan has 10 stages and comes to 30.35 to 263.25 hours. The largest unknown is the code no test runs. The worker process, the password reset flow and the migration waiter each break on this path by our reading, and the suite executes none of the lines involved. The project has its own upgrade to 8.1.4.1 open; it doesn't touch the password reset break we describe under Rails 8.0.

| Driver | Value |
|---|---|
| Series hops | 3 (7.2, 8.0, 8.1) |
| Dependencies (direct / total) | 50 / 162 |
| Dependencies that block a hop | 1 (`annotate`, from 8.0) |
| Lines matched by documented breaking changes (confirmed by reading) | 78 matched, 28 confirmed, 49 false matches, 1 undecided |
| Of those, executed by the test suite | 43.1 percent of the 78; 4 of the 28 confirmed |
| Tests (passing / total) | 834 / 851 with the network off |
| Deprecation warnings today | 0 |
| Effort range | 30.35 to 263.25 hours |

## What was measured and what was inferred

Environment: container image `docker.io/library/ruby:3.4.6-slim-bookworm` with Bundler 2.7.2 and a MariaDB service, Ruby 3.4.6, network on for the dependency install and off for the test run and the boot checks.

**Measured** (a command ran in the sandbox):

- Dependency install: `bundle install`, exit 0, 113.9 seconds.
- Resolution per hop, in a scratch copy: pin Rails to the hop version, then `bundle lock --update rails --conservative` (the first and most careful attempt worked for all three hops), 24.9 seconds.
- Test suite: `bundle exec rake db:create db:schema:load`, then `bundle exec rspec`, network off, with line coverage and warnings collected from outside the checkout. 231.0 seconds of wall time.
- Recheck of the offline failures with the network on: `bundle exec rspec ./spec/lib/dns_resolver_spec.rb ./spec/senders/smtp_sender_spec.rb`, 26.4 seconds.
- Boot: the application loaded the way a server process loads it, once per variant, 7 variants, 54.1 seconds.
- Pattern search of the checkout against 349 curated rules, 7.2 seconds.

**Read** (files and public registries, nothing executed):

- Versions, lockfile, CI and deploy configuration from the checkout.
- End-of-life dates from endoflife.date.
- Declared constraints of each locked gem from the RubyGems registry.
- The 36 Rails component changelogs for 7.2.4, 8.0.5.2 and 8.1.4.1.
- The project's own branches, open pull requests and open issues.
- Every cited line in this report, opened in the checkout.

**Inferred** (our reading of the above):

- Which search hits are real and which are false matches.
- Which unexecuted lines are at risk on which hop.
- That each hop's resolution started from the current lock (each lock diff runs from 7.1.6), so resolving 8.0 from a 7.2 lock isn't yet measured.
- The stage order, the risk ratings and the effort range.

## Inventory

**Read.** Nothing in this section was executed.

- **Framework:** Rails 7.1.6, pinned exactly at `Gemfile:32` and in `Gemfile.lock`. The application requires six railties one by one starting at `config/application.rb:5` and doesn't load Active Job, Active Storage, Action Cable, Action Text or Action Mailbox as railties.
- **Runtime:** Ruby 3.4.6, declared in `.ruby-version` and at `Dockerfile:1`. The two agree. Two documents lag: `CONTRIBUTING.md:9` says Ruby 3.2.2 and `.rubocop.yml:2` targets Ruby 3.0. Neither affects the build.
- **Runtime floors on the path:** Rails 7.2 needs Ruby 3.1 or newer and Rails 8.0 and 8.1 need Ruby 3.2 or newer ([Rails upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html#ruby-versions)). Ruby 3.4.6 clears all three, so the plan has no runtime stage.
- **Lockfile:** present, Bundler 2.7.2, 162 gems, 50 direct, four platforms, every gem from the public registry. Gemfile and lock agree.
- **Database and services:** MariaDB through the `mysql2` adapter (`config/database.yml:2`). Each mail server also gets its own message database, reached through the application's own pool class at `lib/postal/message_db/connection_pool.rb:5`.
- **CI:** GitHub Actions. It builds the `ci` image target and runs the suite inside it with `docker compose run postal sh -c 'bundle exec rspec'` (`.github/workflows/ci.yml:58`). There's no Ruby version matrix; the version comes from the Dockerfile.
- **Deploy:** one Dockerfile on `ruby:3.4.6-slim-bookworm` (Debian 12). The `full` target precompiles assets at `Dockerfile:67`; the `ci` target skips that step, so CI never compiles assets. The compose file's MariaDB image has no tag (`docker-compose.yml:23`), so the database version CI tests against is whatever is current that day.
- **Framework configuration:** `config.load_defaults 7.0` at `config/application.rb:22`, one release behind the installed framework. `config/initializers/new_framework_defaults_7_0.rb` exists and every setting in it is commented out. The autoloader is Zeitwerk. Assets go through Sprockets with `sass-rails`, `coffee-rails` and `uglifier`, all in the `:development, :assets` group at `Gemfile:46`, which the test environment doesn't load.
- **Code size:** 296 Ruby files and 23,818 lines (8,471 in `app`, 4,221 in `lib`, 8,988 in `spec`), plus 103 HAML templates. 25 controllers, 34 models, 109 views, 19 migrations, 25 initializers, 2 mailers.
- **Tests:** RSpec, 55 spec files, WebMock for HTTP. 32 of the 55 are under `spec/lib`; 3 are request specs and 2 are view specs.
- **Findings from recon:** `docker-compose.yml:17` sets `RAILS_LOG_ENABLED`, which no configuration key reads, so it has no effect. `Gemfile:12` holds `execjs` below 2.8; the locked [2.7.0](https://rubygems.org/gems/execjs/versions/2.7.0) dates from 2016.
- **Instructions addressed to tools:** we found no file or text in the checkout written as instructions to whoever or whatever reads the repository. The inventory's list of such files is empty.

## Upgrade work already in flight

**Read**, from the project's public branches, pull requests and issues. We checked all three kinds. Three items move the framework.

- **Branch `chore/rails-7-2-and-dependency-upgrades`**, last touched September 15, 2026. Reaches Rails 7.2.3.2 across 23 files. It replaces the `dynamic_form` gem with an in-app helper, pins `json` below 3, adds `coder: YAML` to two `serialize` calls, moves `migration_context` to the connection pool, changes `show_exceptions` to `:none`, swaps the 7.0 defaults file for 7.1 and 7.2 ones, moves Ruby to 3.4.10 and adds characterization specs for rendering, security headers, serialized columns, JSON encoding and the migration waiter. It also adds the test group to the asset gems and drops the `execjs` pin.
- **Branch `upgrade-rails-8.1.4`**, last touched October 6, 2026. Reaches Rails 8.1.4 across 12 files. It adds `benchmark` and `cgi` to the Gemfile, replaces `annotate` with `annotaterb`, makes the same `migration_context` and `show_exceptions` changes, restamps `db/schema.rb`, and adds specs for the migration waiter and the worker process.
- **The project's open pull request for Rails 8.1**, opened November 4, 2026 and updated November 6. It carries the same 12 files to 8.1.4.1 in a single jump from 7.1.6 and loosens the Rails constraint to the 8.1.4 patch line. Its description says `load_defaults` stays at 7.0.

How we used it. Across the three items the project's work makes 20 changes to application files, which come to 13 distinct files. For 5 of the 13 our own measurements had a signal on the same file. We read the patches for the other 8:

| Their change | Files | Our reading |
|---|---|---|
| Replace `dynamic_form` with an in-app helper | 3 | A choice of theirs. Their note says the gem can't be installed on Ruby 3.4; in our sandbox [dynamic_form 1.2.0](https://rubygems.org/gems/dynamic_form/versions/1.2.0) installed on 3.4.6 and the suite ran. The gem declares nothing about Rails, so how it behaves on each hop is unknown until the forms render there. |
| Remove the 7.0 defaults file, add 7.1 and 7.2 ones | 3 | Output of the framework's update task. We plan the same step in each hop and adopt the defaults in stages S6 to S9. |
| Replace the `annotate` rake file with the `annotaterb` one | 2 | A break we found by another route: the registry marks `annotate` blocked from 8.0 and the resolver downgraded it. |

So the count of breaks in their application changes that none of our nets caught is 0. In their Gemfile changes, the `json` pin matches our lock-level rule and the `benchmark` and `cgi` additions match our removed-gem measurement.

One Gemfile change of theirs the plan had missed. Found by the independent review: the 7.2 branch adds `:test` to the asset gem group at `Gemfile:46`, and its new rendering spec says it exists to exercise the layout and the asset pipeline. The checkout says why that's needed, in a comment at `spec/requests/messages_controller_spec.rb:50`: the full layout depends on the asset pipeline, which isn't configured in the test environment. S1 plans to record full pages, so S1 needs the same change. It's in S1 now.

Their work and ours differ in two places.

- Our search and reading found a break their Rails 8.1 work doesn't address: the password reset flow on Rails 8.0 (see S4). None of the 12 files in that work touches `app/models/concerns/has_authentication.rb:8`.
- The two sources disagree on one fact. Their 7.2 branch says Active Support 7.2 still passes `quirks_mode` to the `json` gem. Our rule, written from the [8.0 source](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/lib/active_support/json/encoding.rb), says 7.1 and 8.0 pass it and 7.2 doesn't. The 7.2 changelog is silent. We plan the pin across every hop below 8.1, which is safe under either reading.

## End-of-life dates

**Read.** Dates come from endoflife.date, fetched November 13, 2026.

| Component | Version in use | End of life | Days from report date | Source |
|---|---|---|---|---|
| Rails (current) | 7.1.6 | 2025-10-01 | 408 days past | [endoflife.date/rails](https://endoflife.date/rails) |
| Rails (hop) | 7.2.4 | 2026-08-09 | 96 days past | [endoflife.date/rails](https://endoflife.date/rails) |
| Rails (hop) | 8.0.5.2 | 2026-11-07 | 6 days past | [endoflife.date/rails](https://endoflife.date/rails) |
| Rails (target) | 8.1.4.1 | 2027-10-10 | 331 days ahead | [endoflife.date/rails](https://endoflife.date/rails) |
| Ruby (`.ruby-version`, Dockerfile) | 3.4.6 | 2028-03-31 | 504 days ahead | [endoflife.date/ruby](https://endoflife.date/ruby) |
| Debian (base image) | 12 | 2028-06-30 | 595 days ahead | [endoflife.date/debian](https://endoflife.date/debian) |

8.1 is the only Rails series the source lists as supported. The MariaDB image in `docker-compose.yml:23` has no tag, so it has no version to look up.

## Compatibility matrix

**Measured.** The resolver found a solution for all three hops on its most careful attempt (`--conservative`). Each hop was resolved from today's lock.

- **7.2.4:** resolves. Adds `useragent`. Downgrades [connection_pool](https://rubygems.org/gems/connection_pool/versions/3.0.2) from 3.0.2 to 2.5.5 and [minitest](https://rubygems.org/gems/minitest/versions/6.0.6) from 6.0.6 to 5.27.0. Removes nothing.
- **8.0.5.2:** resolves. Adds `useragent`. Downgrades `annotate` from 3.2.0 to 2.6.5. Moves `rails-html-sanitizer` to 1.7.2, `loofah` to 2.25.3 and `nokogiri` to 1.19.7. Removes `cgi`.
- **8.1.4.1:** resolves. 17 gems change, with no major jump outside the framework and 1 downgrade (`annotate` again). Adds `useragent` and `action_text-trix`. Removes `cgi` and `benchmark`.

Dependencies that need attention:

| Dependency | Locked | Problem | Evidence | What to do |
|---|---|---|---|---|
| `annotate` | 3.2.0 | Declares `activerecord < 8.0`. Blocked on 8.0 and 8.1. The resolver "solved" it by downgrading a major version to 2.6.5. Latest release is the locked one, from February 2022. | [registry](https://rubygems.org/gems/annotate/versions/3.2.0), resolver lock diff for 8.0 and 8.1 | Replace it in S2, before any hop. The project's own 8.1 work chose `annotaterb`. It's a development-only tool, required at `lib/tasks/auto_annotate_models.rake:5`. |
| `connection_pool`, `minitest` | 3.0.2, 6.0.6 | Downgraded one major each on the 7.2 hop only. On 8.0 and 8.1 the resolver left both alone. | resolver lock diff for 7.2 | Accept the downgrades in S3 and lift them in S4. The application doesn't call the `connection_pool` gem itself: `ConnectionPool` at `lib/postal/message_db/database.rb:10` is its own class. |
| `json` | 2.7.1 | Nothing pins it below 3, and `json` 3 rejects an option Active Support passes on 7.1 and 8.0. One `bundle update` away from every `to_json` raising. | `Gemfile.lock:167`, [Active Support source at 8.0.5.2](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/lib/active_support/json/encoding.rb) | Pin `json` below 3 in S2. Remove the pin in S10. |
| `rails-html-sanitizer`, `loofah`, `nokogiri` | 1.7.0, 2.25.1, 1.19.3 | Action View at 8.0.5.2 and 8.1.4.1 needs sanitizer 1.7.2, which needs newer versions of the other two. | `Gemfile.lock:312`, `Gemfile.lock:196`, `Gemfile.lock:228`, [Action View changelog](https://github.com/rails/rails/blob/v8.0.5.2/actionview/CHANGELOG.md) | Let the 8.0 hop move all three, as the resolver did. The sanitizer shapes the output of helpers such as `sanitize`, `strip_tags`, `simple_format` and `highlight`. The independent review searched `app`, `lib` and `config` and found no call to any of them, so we don't expect this application's HTML to change. S1's recorded pages are the check. |
| `cgi`, `benchmark` | 0.5.1, 0.5.0 | Rails stops depending on them (8.0 and 8.1), so they leave the lock while the application still uses their constants. | removed-gem measurement, under "Code the test suite never runs" | Add each to the Gemfile on the hop that drops it. |

The rest, by what each locked version declares:

- **Declared compatible:** 26 gems. 25 of those declare an open-ended range, a floor written before the hop versions existed. That says nothing about 8.1 either way.
- **No declared constraint:** 122 gems. They don't depend on Rails, so their gemspecs say nothing. Unknown until the suite runs on each hop.
- **Direct dependencies with no release since 2022:** `annotate`, `chronic`, `coffee-rails`, `gelf`, `nifty-utils`, `sass-rails`, `turbolinks`. Five of the seven also declare nothing: [chronic](https://rubygems.org/gems/chronic/versions/0.10.2) (last release 2013), [nifty-utils](https://rubygems.org/gems/nifty-utils/versions/1.1.7) (2015), [gelf](https://rubygems.org/gems/gelf/versions/3.1.0) (2018), [sass-rails](https://rubygems.org/gems/sass-rails/versions/6.0.0) (2019) and [turbolinks](https://rubygems.org/gems/turbolinks/versions/5.2.1) (2019). Nothing warns about these, and two of them sit in the asset pipeline that neither CI nor the suite runs.

## Breaking changes in this codebase

**Measured** by search, then **read**. We opened every on-path hit. 275 of the 349 rules are on this path and 20 of them matched, at 78 lines. "Confirmed" below means the line is what the rule describes. Nothing here was run on a newer Rails.

### Rails 7.2

| Change | Upstream source | Where | Count | Confirmed by reading? |
|---|---|---|---|---|
| `migration_context` moved from the connection to the connection pool | [connection pool source at 7.2.4](https://github.com/rails/rails/blob/v7.2.4/activerecord/lib/active_record/connection_adapters/abstract/connection_pool.rb) | `lib/migration_waiter.rb:18` | 1 | Yes. The call raises `NoMethodError` on 7.2. The suite never executes the line. |
| `show_exceptions = true/false` removed | [7.2 release notes](https://guides.rubyonrails.org/7_2_release_notes.html#action-pack-removals) | `config/environments/test.rb:28` | 1 | Yes. Needs `:none`. |
| `ActiveRecord::Base.connection` soft-deprecated | [Active Record changelog](https://github.com/rails/rails/blob/v7.2.4/activerecord/CHANGELOG.md) | `lib/migration_waiter.rb:18`, `lib/tasks/postal.rake:31` | 2 | Yes, and no change is required. It prints nothing by default. |
| Time zone "Astana" maps to a different zone | [Active Support changelog](https://github.com/rails/rails/blob/v7.2.4/activesupport/CHANGELOG.md) | `app/views/organizations/edit.html.haml:22`, `app/views/user/edit.html.haml:40` | 2 | Yes. Both forms offer the zone, and the chosen name is stored (`db/schema.rb:327`) and applied at `app/controllers/application_controller.rb:55`. A user who stored "Astana" sees times one hour different. Whether anyone did is a production data question. |

Found by the independent review, from the changelog and not from a search rule, so it's outside the 78 lines:

- **The secret key in development and test.** From 7.2.3 those two environments take `secret_key_base` from credentials when it's set ([railties changelog](https://github.com/rails/rails/blob/v7.2.4/railties/CHANGELOG.md)). By our reading of the entry, they used a local secret file before and ignored credentials. `config/initializers/secret_key.rb:7` sets a random value per process when no secret is configured, and the suite runs that line. So from S3 a development server with no configured secret signs sessions with a key that changes on every restart, as production already does. A difference to declare in S3.

### Rails 8.0

| Change | Upstream source | Where | Count | Confirmed by reading? |
|---|---|---|---|---|
| `has_secure_password` now defines `password_reset_token` | [Active Model changelog](https://github.com/rails/rails/blob/v8.0.5.2/activemodel/CHANGELOG.md) | `app/models/concerns/has_authentication.rb:42`, `app/models/concerns/has_authentication.rb:53`, `app/controllers/sessions_controller.rb:46`, `app/views/app_mailer/password_reset.text.erb:5`, `db/schema.rb:332` | 5 | Yes. See below. |
| Action View requires `rails-html-sanitizer` 1.7.2 | [Action View changelog](https://github.com/rails/rails/blob/v8.0.5.2/actionview/CHANGELOG.md) | `Gemfile.lock:196`, `Gemfile.lock:228`, `Gemfile.lock:312` and three more platform lines | 6 | Yes. The resolver moves all three gems on this hop. |
| `json` 3 rejects `quirks_mode` | [Active Support source](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/lib/active_support/json/encoding.rb) | `Gemfile.lock:167` | 1 | Yes. A pin to add, in S2. |
| `db:migrate` on a fresh database loads the schema first | [8.0 release notes](https://guides.rubyonrails.org/8_0_release_notes.html#active-record-notable-changes) | `bin/update:24` | 1 | Yes, for a developer script on an empty database. The production path at `lib/tasks/postal.rake:35` only calls `db:migrate` when migrations already exist, so it's unchanged. |
| MySQL 5.5 dropped | [Active Record changelog](https://github.com/rails/rails/blob/v8.0.5.2/activerecord/CHANGELOG.md) | `config/database.yml:2` | 1 | Undecided. The adapter matches; the server versions in production aren't in the repository. |
| `stringify_keys` on an indifferent hash converts every key | [Active Support changelog](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/CHANGELOG.md) | `lib/postal/message_db/delivery.rb:8`, `lib/postal/message_db/delivery.rb:26`, `lib/postal/message_db/message.rb:217` | 3 | No. Two call the application's own method at `lib/postal/message_db/database.rb:298`. The third receives a plain Hash as far as we can read; S4 checks that when it runs. |
| Inflections with overlapping acronyms | [Active Support changelog](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/CHANGELOG.md) | `config/initializers/inflections.rb:17` and 12 more lines | 13 | No. None of the 13 acronyms is a prefix of another. |
| CSP sources with spaces or semicolons raise | [Action Pack changelog](https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md) | `app/controllers/application_controller.rb:37` and 14 more lines | 15 | No. All 15 are flash messages in `redirect_to` calls. Rails' own policy is commented out (`config/initializers/content_security_policy.rb:9`); the application sets its policy through `secure_headers` (`app/controllers/messages_controller.rb:92`). |

The password reset break, in full. `has_secure_password` is called at `app/models/concerns/has_authentication.rb:8` on the `User` model (`app/models/user.rb:33`), which has its own `password_reset_token` column (`db/schema.rb:332`). On 8.0 the framework defines a reader of the same name that returns a signed, 15-minute token and shadows the column. The application writes a random value to the column at `app/models/concerns/has_authentication.rb:42`, the mailer template prints `@user.password_reset_token` at `app/views/app_mailer/password_reset.text.erb:5`, and the controller looks the emailed value up in the column at `app/controllers/sessions_controller.rb:46`. By our reading the email would carry the signed token, the lookup would find nothing, and every reset link would land on "This link has expired". The suite executes neither line 42 nor line 46, so every check would pass. The fix is one option, `reset_token: false`, on line 8.

Found by the independent review, from the changelog, outside the 78 lines:

- **The `Vary` response header.** From 8.0.5.2 a rendered response varies on `Accept` and `X-Requested-With` whenever the URL doesn't fix the format ([Action Pack changelog](https://github.com/rails/rails/blob/v8.0.5.2/actionpack/CHANGELOG.md)). The application negotiates formats in `respond_to` blocks such as `app/controllers/application_controller.rb:85`, and by the entry's wording ordinary pages are covered too. The response headers S1 records will differ on S4 for that reason. Declared in S4.

### Rails 8.1

| Change | Upstream source | Where | Count | Confirmed by reading? |
|---|---|---|---|---|
| Active Support no longer requires `benchmark` | [Active Support gemspec](https://github.com/rails/rails/blob/v8.1.4.1/activesupport/activesupport.gemspec) | `app/lib/worker/process.rb:164`, `app/lib/worker/process.rb:256` | 2 | Yes. See the next section. |
| Action View requires `rails-html-sanitizer` 1.7.2 | [Action View changelog](https://github.com/rails/rails/blob/v8.1.4.1/actionview/CHANGELOG.md) | `Gemfile.lock:312`, `Gemfile.lock:228` and three more platform lines | 5 | Yes, and already satisfied once S4 ships. |
| `remote_ip` reads forwarded addresses that carry a port | [Action Pack changelog](https://github.com/rails/rails/blob/v8.1.4.1/actionpack/CHANGELOG.md) | `config/initializers/trusted_proxies.rb:4` | 1 | No at that line, which sets Rack's filter. The application does read `request.remote_ip`, at `app/controllers/sessions_controller.rb:67`. What it returns behind the production proxy can't be read from the code. |
| `IPAddr#as_json` includes the prefix | [Active Support changelog](https://github.com/rails/rails/blob/v8.1.4.1/activesupport/CHANGELOG.md) | `app/models/credential.rb:74`, `lib/postal/http/address_guard.rb:39` and 12 more lines | 14 | No. The 14 lines build or rescue addresses. We found none that serializes one to JSON. |
| `schema.rb` columns sorted alphabetically | [upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html#the-table-columns-inside-schema-rb-are-now-sorted-alphabetically) | `db/schema.rb:13` | 1 | No. The rule's own note says 8.1.4 reverted the change, and the target is 8.1.4.1. The version stamp on that line still changes on the first dump. |

Found by the independent review, from the changelogs, outside the 78 lines:

- **`to_time` changes on this hop, whatever `load_defaults` says.** 8.1 removes the older `to_time` behavior outright and deprecates the setting that chose it ([Active Support changelog](https://github.com/rails/rails/blob/v8.1.4.1/activesupport/CHANGELOG.md)). Our rules carry this as an 8.1 change with no hits, because that rule searches for the setting and the application never sets it. The report as written tested the one `to_time` caller, `lib/postal/message_db/provisioner.rb:133`, in S8. By then S5 would already have shipped the change. Our reading of the line stands (the receiver is a `Date`, so the result shouldn't move), but the test now sits in S5, ahead of the hop.
- **Conflicting forwarded headers raise.** From 8.1.4.1, a request whose `Forwarded` and `X-Forwarded-For` headers name different clients raises `ActionDispatch::RemoteIp::IpSpoofAttackError` when the remote address is read ([Action Pack changelog](https://github.com/rails/rails/blob/v8.1.4.1/actionpack/CHANGELOG.md)). The application reads `request.remote_ip` at `app/controllers/sessions_controller.rb:67`, in a diagnostic action that needs no login. Everything else we found reads `request.ip`, which goes through Rack and the filter at `config/initializers/trusted_proxies.rb:3`. So the effect is an error on that one action for such requests. Declared in S5.
- **The connection pool setting is renamed.** 8.1 renames the database setting `pool` to `max_connections` and says default behavior doesn't change ([Active Record changelog](https://github.com/rails/rails/blob/v8.1.4.1/activerecord/CHANGELOG.md)). The application sets `pool` at `config/database.yml:5`, `lib/postal/config.rb:158` passes `pool:` when the worker resizes its pool, and `app/lib/worker/process.rb:105` reads the pool's `size`. `spec/lib/postal_spec.rb:15` runs the resize and asserts on the size, so the suite decides this one on S5.

### Framework defaults (pending because `load_defaults` is 7.0)

28 on-path rules are defaults. Three matched.

| Change | Upstream source | Where | Count | Confirmed by reading? |
|---|---|---|---|---|
| `serialize` has no default coder (7.1 defaults) | [configuring guide](https://guides.rubyonrails.org/configuring.html#config-active-record-default-column-serializer) | `app/models/credential.rb:34`, `app/models/webhook_request.rb:37` | 2 | Yes. Both need `coder: YAML` before the 7.1 defaults go on. The project's 7.2 branch makes the same change. |
| `after_commit` callbacks run in the order defined (7.1 defaults) | [configuring guide](https://guides.rubyonrails.org/configuring.html#config-active-record-run-after-transaction-callbacks-in-order-defined) | `app/models/server.rb:92` | 1 | No. It's the only `after_commit` in `app/models`, so there's no order to change. |
| `to_time` keeps the receiver's zone (8.0 defaults) | [Active Support changelog](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/CHANGELOG.md) | `lib/postal/message_db/provisioner.rb:133` | 1 | No by our reading, because the receiver is a `Date`. The line decides which messages retention deletes and the suite never executes it, so we test it anyway. The independent review moved that test from S8 to S5 (see Rails 8.1 above). |

Found by the independent review. Each of these is an on-path default with no search hit, and the report as written passed over all three:

- **`Regexp.timeout` of one second (8.0 defaults).** [8.0 release notes](https://guides.rubyonrails.org/8_0_release_notes.html#railties-notable-changes). The rule can only find an application that sets its own timeout, and this one doesn't. But the application runs a URL pattern over the body of every message it tracks, at `lib/postal/message_parser.rb:101` and `lib/postal/message_parser.rb:118`. A timeout there raises inside `generate`, and the rescue at `lib/postal/message_parser.rb:56` hands back the original message with tracking switched off. So a slow match on a large or hostile message would quietly send that message untracked, and nothing would fail. The setting is process-wide, so it reaches the worker and the SMTP server too. S8 reads for it.
- **JSON escaping (8.1 defaults).** [configuring guide](https://guides.rubyonrails.org/configuring.html#config-action-controller-escape-json-responses). The setting governs `render json:`. S9 as written pointed at `app/views/servers/show.html.haml:27`, which is a `to_json` into an HTML attribute and isn't a JSON response at all. The default lands on the API, at `app/controllers/legacy_api/base_controller.rb:103` and the other `render json:` calls. API clients would receive `<`, `>` and `&` as themselves where they received escape sequences. That's the same JSON value in different bytes, and a client that compares or signs raw bodies would notice. S9 is corrected, and S1 records an API response so the difference shows.
- **Hidden inputs lose `autocomplete="off"` (8.1 defaults).** [configuring guide](https://guides.rubyonrails.org/configuring.html#config-action-view-remove-hidden-field-autocomplete). The rule searched the specs for exact HTML and found none. The forms themselves change, starting with the login form at `app/views/sessions/new.html.haml:7`, so every recorded page with a form differs on S9. Declared in S9.

255 on-path rules had no hits. 18 of them can't be found by search at all; they're listed in the last section. 8 rules that aren't on this path also matched and aren't counted.

## Code the test suite never runs

**Derived** from the resolver's lock diffs and the suite's line coverage, then **read**.

**Gems each hop drops, and where the application uses their constants.**

- **`cgi`, dropped on 8.0.** `CGI.parse` at `lib/postal/config_schema.rb:80` (executed by the suite) and `CGI.unescapeHTML` at `lib/postal/message_parser.rb:121` (never executed). Neither file requires the library. Line 121 rewrites tracked links in outgoing HTML mail. Plan: add `cgi` to the Gemfile in S4. Found by the independent review: a missing constant on line 121 wouldn't surface as an error. The rescue at `lib/postal/message_parser.rb:56` catches it outside development and returns the original message with tracking off. So the S1 test for this path has to assert that the link was rewritten. A test that only checks nothing raised would pass with tracking dead.
- **`benchmark`, dropped on 8.1.** `Benchmark.realtime` at `app/lib/worker/process.rb:164` and `app/lib/worker/process.rb:256`. The file doesn't require the library, and the suite never loads the file at all. Line 164 wraps every job the worker runs. The project's own new spec for this class notes that the worker logs and swallows errors, so a `NameError` there would likely stop mail processing without stopping the process. The independent review read the code and agrees: `Benchmark.realtime` wraps `job.call` on line 164, so the job never starts, and `capture_errors` at `app/lib/worker/process.rb:284` rescues the error, logs it and carries on to the next tick. Plan: add `benchmark` to the Gemfile in S5, and put the worker under test in S1.

**Framework call sites the suite never runs.** 58 lines name the framework's surface. Of the ones marked for reading, the suite loads and never executes 5, and 11 more sit in files it never loads. We read all 16 against the changelogs for each hop. At risk:

- `lib/migration_waiter.rb:18`: breaks on 7.2 (see above).
- `lib/postal/message_db/database.rb:333`: calls `ActiveRecord::ConnectionAdapters::MySQL::ExplainPrettyPrinter`, an internal class no changelog covers, and only when a message database query takes longer than 0.05 seconds. If its interface moves on any hop, slow queries raise where they used to return.
- `config/initializers/secret_key.rb:4`: assigns the configured secret to `Rails.application.credentials`. The suite and every boot variant take the other branch (line 7) because no secret is set. The railties changelogs for [7.2](https://github.com/rails/rails/blob/v7.2.4/railties/CHANGELOG.md), [8.0](https://github.com/rails/rails/blob/v8.0.5.2/railties/CHANGELOG.md) and [8.1](https://github.com/rails/rails/blob/v8.1.4.1/railties/CHANGELOG.md) each touch how `secret_key_base` is resolved, and it signs every session.
- `app/lib/worker/process.rb:105`, `app/lib/worker/process.rb:159` and three more `connection_pool` calls in that file: 7.2 reworked connection leasing ([Active Record changelog](https://github.com/rails/rails/blob/v7.2.4/activerecord/CHANGELOG.md)). The calls still exist by our reading. Nothing executes them. The independent review adds 8.1 for line 105, where the pool setting is renamed (see Rails 8.1 above).

The independent review also read the 6 call sites the measurement marks as stable surface, which this report hadn't listed as read: `app/controllers/application_controller.rb:41`, `config/initializers/omniauth.rb:16`, `lib/postal/message_parser.rb:57`, `config/environments/development.rb:18`, `lib/tasks/auto_annotate_models.rake:4` and `script/insert-bounce.rb:19`. None calls anything that moves on this path. Reading around line 57 is how the swallowed errors above were found.

Read and judged not at risk: `app/models/route.rb:122`, `lib/migration_waiter.rb:47`, `Rakefile:8`, `config.ru:6`, `app/controllers/ip_pools_controller.rb:36`, `lib/tasks/postal.rake:31`, `config/environments/development.rb:3` and `config/environments/production.rb:3` (the production variant booted).

**Optional features nothing exercised.** Six flags:

- `Postal::Config.rspamd.enabled?`, `Postal::Config.spamd.enabled?` and `Postal::Config.clamav.enabled?`, at `lib/postal/message_inspector.rb:27`, `lib/postal/message_inspector.rb:29` and `lib/postal/message_inspector.rb:33`. They need those daemons on the network.
- `Postal::Config.oidc.local_authentication_enabled?` at `app/controllers/sessions_controller.rb:94`.
- `config.enabled?` at `config/initializers/omniauth.rb:4`. The measurement lists it as not exercised. It reads the same OIDC setting through a local variable, and both OIDC boot variants started, so we think this one ran.
- `config.public_file_server.enabled` at `config/environments/production.rb:21`, which is an assignment and not a feature.

**Boot variants.** Seven ran on Rails 7.1.6 and the application started under each: `default`, `oidc`, `oidc-no-discovery`, `migration-waiter`, `rails-log`, `sentry` and `production`. A boot proves the process starts and nothing about requests. The record doesn't show whether `lib/migration_waiter.rb:18` ran in its variant. The worker and SMTP server are separate entry points that no variant loads.

## Test suite health

**Measured.**

> 834 of 851 examples pass with the network off; 17 more pass with the network on; 5 fail in that run.

- **Runs in a clean sandbox:** yes, with `bundle exec rake db:create db:schema:load` then `bundle exec rspec`.
- **Duration:** 221.7 seconds for 851 examples.
- **Failures before any change:** 17 with the network off, 16 in `spec/lib/dns_resolver_spec.rb` and 1 in `spec/senders/smtp_sender_spec.rb`. Each of the 17 makes a real DNS lookup. In the network-on run of the two files (75 examples), those 17 examples passed and 5 other examples in `spec/lib/dns_resolver_spec.rb` failed. So no single run of those two files passes whole, and the parity check has to compare them example by example under both conditions.
- **Deprecation warnings:** 0 from Rails. That's a fact about 7.1.6 only; the count on each hop is unknown until that hop runs. Ruby itself prints 2 deprecation-category warnings, from `webmock` and `domain_name`.
- **Coverage:** 83.7 percent of lines in the files the run loaded. 39 of 154 source files in `app` and `lib` were never loaded, including 17 controllers, 8 scheduled tasks, `app/lib/worker/process.rb` and `app/lib/smtp_server/server.rb`.
- **Coverage of the affected lines:** 31 of the 78 matched lines executed, 43.1 percent. 17 are in loaded files and never executed, 24 are in files the suite doesn't load.

What this means for parity. The suite is strong on the library code under `lib` and thin on the web interface, the worker loop and anything behind a flag. It can't hold "same behavior" for this upgrade as it stands, because the three breaks we rank highest all sit in lines it doesn't run. S1 adds characterization tests for nine paths and a recorded set of HTTP responses before any version moves. The project's own two branches added specs for five of the same paths, which we take as agreement on where the net is thin.

## Plan

Each stage ends with an independent review pass that had no part in the work, following a fixed method: read the hop's changelogs, read the unexecuted call sites, compare with the project's own upgrade work, try to break the stage. The review is in each estimate. Every stage's check compares against the S1 recording, and the promise is no undeclared behavior change, each difference sourced.

### S1: Baseline and characterization

- **Goal:** Record today's behavior on Rails 7.1.6 and put tests around the nine paths the upgrade touches and the suite doesn't run.
- **Changes:**
  - Record the suite per example under both network conditions (baseline measurement).
  - Record a request set: login page, an authenticated page, a form that fails validation, response headers and cookies (`spec/requests/sessions_controller_spec.rb` is one of only 3 request specs). Added by the independent review: include one API response whose data contains `<`, `>` and `&` (`app/controllers/legacy_api/base_controller.rb:103`), so S9's escaping change shows up in the recording.
  - Added by the independent review: make full pages renderable in the test environment first. Today they aren't, by the checkout's own account (`spec/requests/messages_controller_spec.rb:50`), because the asset gems sit outside the test group (`Gemfile:46`). The project's 7.2 branch added `:test` to that group for the same purpose. Do the same, declare it as S1's one Gemfile change, and confirm the lock doesn't move. Without this the request set and the form test below can't be recorded.
  - Characterization tests for: the password reset flow end to end (`app/models/concerns/has_authentication.rb:42`, `app/controllers/sessions_controller.rb:46`); `MigrationWaiter.wait` (`lib/migration_waiter.rb:18`); `Worker::Process` work and task runs (`app/lib/worker/process.rb:164`, `app/lib/worker/process.rb:256`); tracked links in HTML parts (`lib/postal/message_parser.rb:121`), asserting the rewritten link since errors there are swallowed (`lib/postal/message_parser.rb:56`); the slow-query explain path (`lib/postal/message_db/database.rb:333`); the two YAML columns, round trip and stored format (`app/models/credential.rb:34`, `app/models/webhook_request.rb:37`); forms rendering validation errors through `dynamic_form` (`app/views/user/edit.html.haml:7`, one of 18 templates that call it); security headers and session cookies; and the asset precompile (`Dockerfile:67`), recorded as a list of output files.
  - Add a boot variant with a configured secret so `config/initializers/secret_key.rb:4` runs.
- **Check:** `tests`, `parity`, `boot`. The new examples pass on 7.1.6; every example's recorded state under each network condition is unchanged; all boot variants start.
- **Risk:** low. No version changes. The risk is that characterizing the worker turns out harder than a path's allowance. The independent review adds a second: loading the asset gems in the test environment is new, and whether the layout then renders in the sandbox hasn't been measured.
- **Effort:** 8.0 to 36.75 hours.
- **Ships separately:** yes. Depends on nothing.

### S2: Dependencies that can move on 7.1

- **Goal:** Remove the one blocker and add the one pin while still on Rails 7.1.6.
- **Changes:**
  - Replace `annotate` (`Gemfile:54`, `lib/tasks/auto_annotate_models.rake:5`) with a maintained equivalent. `annotaterb` is what the project's 8.1 branch chose; its constraints aren't in our measurements, so the resolve check decides.
  - Pin `json` below 3 in the Gemfile (`Gemfile.lock:167`), with a comment naming Rails 8.1 as the point it comes out.
- **Check:** `resolve`, `tests`, `parity`, `boot`. The lock changes only `annotate`, its replacement and their own dependencies; recorded behavior unchanged.
- **Risk:** low. One development-only gem and one pin at the version already locked.
- **Effort:** 2.75 to 15.75 hours.
- **Ships separately:** yes. Depends on S1.

### S3: Rails 7.1 to 7.2

- **Goal:** Move to Rails 7.2.4. Runtime floor is Ruby 3.1; the application is on 3.4.6.
- **Changes:**
  - Run `bin/rails app:update` and review each file it touches. Keep `load_defaults` at 7.0.
  - `lib/migration_waiter.rb:18`: read `migration_context` from `connection_pool`.
  - `config/environments/test.rb:28`: `:none` in place of `false`.
  - Accept the resolver's lock: `connection_pool` 2.5.5 and `minitest` 5.27.0 for this hop.
  - Declare the "Astana" change (`app/views/user/edit.html.haml:40`, `app/views/organizations/edit.html.haml:22`) and hand the client a query for stored values.
  - Leave `lib/tasks/postal.rake:31` as it is; `connection` still works.
  - Added by the independent review: declare that development and test now take the secret key from `config/initializers/secret_key.rb:7`.
  - Read the four unsearchable 7.2 rules against the code (listed in the last section).
- **Check:** `resolve`, `tests`, `parity`, `boot`, `deprecations`. No example that passed in the S1 recording fails or is missing; recorded responses differ only where declared; all boot variants start, the migration waiter's included; the deprecation count is recorded and each new warning is listed.
- **Risk:** medium. One confirmed break on a line the suite never ran before S1, two downgrades, four rules search can't see.
- **Effort:** 3.7 to 52.5 hours.
- **Ships separately:** yes. Depends on S1 and S2.

### S4: Rails 7.2 to 8.0

- **Goal:** Move to Rails 8.0.5.2. Runtime floor is Ruby 3.2.
- **Changes:**
  - Run `bin/rails app:update` and review each file.
  - `app/models/concerns/has_authentication.rb:8`: add `reset_token: false` so the application's own reset token keeps working.
  - Add `cgi` to the Gemfile (`lib/postal/config_schema.rb:80`, `lib/postal/message_parser.rb:121`).
  - Let `rails-html-sanitizer`, `loofah` and `nokogiri` move as resolved, and lift `connection_pool` and `minitest` back up. This resolution from a 7.2 lock is new; ours started from 7.1.6.
  - Confirm `lib/postal/message_db/delivery.rb:26` receives a plain Hash.
  - Declare the `db:migrate` change for `bin/update:24`.
  - Added by the independent review: declare the `Vary` header change on rendered responses (`app/controllers/application_controller.rb:85`).
  - Ask the client for the MySQL or MariaDB server versions in production (`config/database.yml:2`).
  - Read the two unsearchable 8.0 rules against the code.
- **Check:** `resolve`, `tests`, `parity`, `boot`, `deprecations`. As S3, and the S1 password reset test passes unchanged.
- **Risk:** high. Authentication breaks without the fix, a library the code uses leaves the lock and its absence would fail silently in mail tracking, response headers change, and four of the five reset-token lines aren't executed by today's suite. The independent review took the sanitizer out of this list: the three gems move, but we found no caller of the sanitizer helpers in the application.
- **Effort:** 4.85 to 53.25 hours.
- **Ships separately:** yes. Depends on S3.

### S5: Rails 8.0 to 8.1

- **Goal:** Move to Rails 8.1.4.1, the supported series. Runtime floor is Ruby 3.2.
- **Changes:**
  - Run `bin/rails app:update` and review each file.
  - Add `benchmark` to the Gemfile (`app/lib/worker/process.rb:164`, `app/lib/worker/process.rb:256`).
  - Commit the restamped `db/schema.rb:13` as its own change and confirm column order is untouched.
  - Compare `request.remote_ip` (`app/controllers/sessions_controller.rb:67`) before and after behind the client's proxy chain; this needs the client. Added by the independent review: declare that the same action now raises when `Forwarded` and `X-Forwarded-For` disagree.
  - Moved here from S8 by the independent review: before the hop, add a test for the retention cutoff at `lib/postal/message_db/provisioner.rb:133`. 8.1 is where `to_time` changes.
  - Added by the independent review: confirm the pool size setting and the worker's pool resize still work under the renamed setting (`config/database.yml:5`, `lib/postal/config.rb:158`, `app/lib/worker/process.rb:105`). `spec/lib/postal_spec.rb:15` is the check.
  - Read the seven unsearchable 8.1 rules against the code.
- **Check:** `resolve`, `tests`, `parity`, `boot`, `deprecations`. As S3, and the S1 worker tests and the retention cutoff test pass unchanged.
- **Risk:** high. The worker loop depends on a library that leaves the lock, in a file the suite never loaded before S1; seven rules can't be searched, two of them about cookies and request parsing.
- **Effort:** 3.85 to 57.75 hours.
- **Ships separately:** yes. Depends on S4.

### S6: Adopt the 7.1 defaults

- **Goal:** Move `load_defaults` from 7.0 to 7.1 (`config/application.rb:22`).
- **Changes:**
  - First, add `coder: YAML` at `app/models/credential.rb:34` and `app/models/webhook_request.rb:37`. Existing rows are YAML and must stay readable.
  - Turn on the 7.1 defaults one at a time from the generated file. The message serializer and message metadata settings change the session cookie format; adopt the fallback-capable serializer and plan the deploy so old sessions still read.
  - Check the one unsearchable 7.1 default (cache expiry) against the code.
- **Check:** `tests`, `parity`, `boot`. The S1 serialized-column and cookie tests pass; header and cookie differences are listed one by one against their setting.
- **Risk:** high. It touches serialization and session cookies.
- **Effort:** 1.7 to 11.25 hours.
- **Ships separately:** yes. Depends on S5.

### S7: Adopt the 7.2 defaults

- **Goal:** Move `load_defaults` to 7.2.
- **Changes:** Turn on each 7.2 default. Check the 19 migration timestamps against the new validation.
- **Check:** `tests`, `parity`, `boot`.
- **Risk:** low. The 7.2 defaults file in the project's own branch lists five settings, and three of them concern Active Job, Active Storage or PostgreSQL, which this application doesn't use.
- **Effort:** 1.5 to 10.5 hours.
- **Ships separately:** yes. Depends on S6.

### S8: Adopt the 8.0 defaults

- **Goal:** Move `load_defaults` to 8.0.
- **Changes:** Turn on each 8.0 default. Corrected by the independent review: the retention cutoff test moved to S5, because by this stage `to_time` has already changed. In its place, read the patterns the application runs over message bodies (`lib/postal/message_parser.rb:101`, `lib/postal/message_parser.rb:118`) before accepting the one-second `Regexp.timeout`, and decide with the client whether to keep it, raise it or leave it off for the worker.
- **Check:** `tests`, `parity`, `boot`. The S1 tracked-link test passes unchanged.
- **Risk:** medium. A pattern that times out on a real message fails silently (`lib/postal/message_parser.rb:56`), and no test or recording uses production-sized mail.
- **Effort:** 1.5 to 9.0 hours.
- **Ships separately:** yes. Depends on S7.

### S9: Adopt the 8.1 defaults

- **Goal:** Move `load_defaults` to 8.1.
- **Changes:** Turn on each 8.1 default. Corrected by the independent review: JSON responses stop escaping HTML entities, and that lands on the `render json:` calls, the API's first (`app/controllers/legacy_api/base_controller.rb:103`). Decide with the client whether API consumers depend on the escaped form; if they do, keep the old setting. `app/views/servers/show.html.haml:27`, where this stage first pointed, is a `to_json` in a view and the escaping setting doesn't govern it. Also declare that hidden form inputs lose `autocomplete="off"` (`app/views/sessions/new.html.haml:7`).
- **Check:** `tests`, `parity`, `boot`. The API response and the pages recorded in S1 differ only in those two ways.
- **Risk:** medium. The escaping default can't be found by search, and it changes what API clients receive.
- **Effort:** 1.5 to 10.5 hours.
- **Ships separately:** yes. Depends on S8.

### S10: Cleanup

- **Goal:** Remove what the upgrade no longer needs.
- **Changes:** Remove the `json` pin from S2. Delete `config/initializers/new_framework_defaults_7_0.rb` and the later defaults files. Optionally correct `CONTRIBUTING.md:9`, `.rubocop.yml:2` and `docker-compose.yml:17`.
- **Check:** `resolve`, `tests`, `parity`, `boot`.
- **Risk:** low.
- **Effort:** 1.0 to 6.0 hours.
- **Ships separately:** yes. Depends on S9.

## Estimate

| Stage | Low (hours) | High (hours) |
|---|---|---|
| S1 Baseline and characterization | 8.0 | 36.75 |
| S2 Dependencies on 7.1 | 2.75 | 15.75 |
| S3 Rails 7.2 | 3.7 | 52.5 |
| S4 Rails 8.0 | 4.85 | 53.25 |
| S5 Rails 8.1 | 3.85 | 57.75 |
| S6 7.1 defaults | 1.7 | 11.25 |
| S7 7.2 defaults | 1.5 | 10.5 |
| S8 8.0 defaults | 1.5 | 9.0 |
| S9 8.1 defaults | 1.5 | 10.5 |
| S10 Cleanup | 1.0 | 6.0 |
| **Total** | **30.35** | **263.25** |

The high end is 8.7 to 1 against the low. The range comes from a rubric of uncalibrated priors: every number in it was set by judgment, and 0 executed upgrades have corrected it so far. The low end is "everything behaves as declared." The high end is "each unknown named in this report costs its listed allowance." Neither includes work outside the plan.

The range is that wide for two reasons the measurements give. The five stale, undeclared gems carry an allowance on every hop, and that alone is 90 of the 263.25 high hours. And only 43.1 percent of the affected lines are executed by the suite, which raises every stage's high end by half.

Assumptions:

- The suite plus the S1 recording is the acceptance test.
- No production-only code paths exist beyond the ones named here.
- Dependencies behave as their declared constraints say.
- Reviews turn around within a day.
- We didn't apply the allowance for a suite that can't run offline. The suite runs offline; 17 examples need DNS and are tracked on their own. The independent review read it the same way. If the allowance applied, each high figure would rise by a quarter.
- The independent review moved one judgment hit, the retention cutoff line, from S8 to S5 along with its test. S5 rose and S8 fell by the same amount, so the total is unchanged.
- Hits we read and judged false matches carry no hours. The two `Benchmark` lines are counted both as rule hits and as a removed-gem use, as the rubric defines them.
- One 7.2 rule and one 8.0 rule are left out of the unsearchable allowance: the Active Job time zone rule (the application doesn't load Active Job, `config/application.rb:5`) and the unregistered database adapter rule (`mysql2` is a built-in adapter, `config/database.yml:2`).

What would move the number:

- A gem that fails at runtime despite resolving. The five stale gems are where we'd expect it.
- Deprecation warnings that appear only on 7.2 or 8.0.
- A recorded response that differs and needs a product decision. The header defaults in S6 and the JSON escaping in S9 are the likely sources. (The independent review replaced the sanitizer change in S4 here; see the compatibility matrix.)
- Full pages that still won't render in the test environment after S1's Gemfile change. S1's request set would then need another way to run, and that isn't in the estimate.
- A review finding that reopens a stage.
- The client taking the project's own pull request first. That would replace parts of S2 to S5 with a review of work already done, and S1, the password reset fix and S6 to S9 would still stand.

## Independent review

Done on November 13, 2026, by a reviewer who didn't write the report. It was a reading pass with no shell, so nothing below was run. The full record is in `roadmap/tech-review.json`. The pass was timed from outside, so the figure is filed with the job record and isn't restated here.

**Method, with counts:**

- **Changelogs.** We read 21 of the 36 fetched changelog files end to end, 1,236 of 1,507 entries: railties, Active Support, Active Record, Active Model, Action Pack, Action View and Action Mailer for 7.2, 8.0 and 8.1. Those are the components `config/application.rb:5` loads. We didn't read the 15 files for Active Job, Active Storage, Action Cable, Action Text and Action Mailbox, which it doesn't load. For each entry that removes, renames, moves or newly defines something, we searched the checkout for a use.
- **Unexecuted call sites.** The measurement lists 22. We read all 22: the 16 the report covered, and the 6 marked stable surface that it hadn't listed.
- **Flags.** We opened the code behind each of the 6 flags listed as not exercised. The three scanners at `lib/postal/message_inspector.rb:27` reach their daemons over sockets and call nothing in Rails that moves. We agree with the report's reading of `config/initializers/omniauth.rb:4`.
- **The project's own work.** We read every patch the measurement holds for all three items against the report's account. Two of them, the 7.0 and 7.1 defaults files, are cut short there. The file counts (20 changes, 13 files, 5 with a signal of ours, 8 without) match the measurement, and the report's reading of the 8 holds.
- **Estimate.** We recomputed every stage from the rubric and the total; they matched. We agree the offline-suite allowance doesn't apply. We didn't re-derive each stage's hit counts line by line.
- **Planned changes.** We opened the file behind each change the plan names.

**What the review found.** 11 items. One is a defect in the plan as written, 4 are risks, 6 are notes. Each is corrected in place above and marked there. Because one is a defect, the review's recorded verdict on the report as written is "defect"; the corrected report is what you're reading.

1. **Defect, corrected. S9 aimed the JSON escaping check at the wrong code.** It named `app/views/servers/show.html.haml:27`, which the setting doesn't govern, and didn't name the API responses it does (`app/controllers/legacy_api/base_controller.rb:103`). Followed as written, S9 could have changed what API clients receive without declaring it, and no recording covered the API. Found from the Action Pack changelog.
2. **Risk. S1 couldn't record full pages as planned.** The test environment can't render the layout (`spec/requests/messages_controller_spec.rb:50`, `Gemfile:46`). Found by comparing with the project's 7.2 branch, which changes the Gemfile group for this reason.
3. **Risk. The retention test was scheduled after the change it guards against.** `to_time` changes on the 8.1 hop. Moved from S8 to S5. Found from the Active Support changelog.
4. **Risk. The one-second `Regexp.timeout` in the 8.0 defaults went unmentioned**, in an application that runs patterns over untrusted mail (`lib/postal/message_parser.rb:101`). Found from the railties changelog.
5. **Risk. Two failures on this path are silent.** A missing `CGI` on 8.0 or a pattern timeout under the 8.0 defaults is rescued at `lib/postal/message_parser.rb:56`, and the message goes out untracked. Found by reading an unexecuted call site.
6. **Note.** The `Vary` header changes on S4. The parity check would show it; it's now declared in advance.
7. **Note.** Hidden form inputs change under the 8.1 defaults. Same.
8. **Note.** Conflicting forwarded headers raise on 8.1.4.1 at `app/controllers/sessions_controller.rb:67`.
9. **Note.** The pool setting is renamed in 8.1. An existing spec covers the application's use.
10. **Note.** The sanitizer risk in S4 was overstated. We found no caller of the sanitizer helpers.
11. **Note.** Development and test change where their secret key comes from on 7.2.

Of the 11, 6 are things no check in the plan would have shown: items 1, 3, 4, 5, 8 and 11.

**What the review confirmed.** The password reset break reads as the report says, and the project's open pull request doesn't touch it. The worker failure mode is as described: `app/lib/worker/process.rb:284` rescues the error and the job never runs. The baseline sentence is quoted word for word in both places.

**What the review didn't do.** It ran nothing: no boot, no probe, no eager load on any newer version. It didn't read the framework's source, which isn't in the job directory, so each reading of a changelog entry above is a reading of the entry's text. It didn't re-read the 49 search hits the report judged false matches, beyond the ones on lines it opened for other reasons.

## What cannot be known without running it

- **The deprecation count on each hop.** Today's count of 0 was measured on 7.1.6 only. S3, S4 and S5 each record their own.
- **How 122 gems with no declared constraint behave.** Their gemspecs say nothing about Rails. Each hop's suite run and parity check settles what the suite exercises; S1's asset precompile recording covers `sass-rails` and `turbolinks`, which the suite doesn't load.
- **Whether `dynamic_form` works on 7.2 and later.** It declares nothing and 18 templates call it. The S1 form-rendering test settles it on each hop.
- **Rails 7.2 rules search can't find** ([7.2 release notes](https://guides.rubyonrails.org/7_2_release_notes.html#active-record-removals), [Active Support changelog](https://github.com/rails/rails/blob/v7.2.4/activesupport/CHANGELOG.md), [Active Job changelog](https://github.com/rails/rails/blob/v7.2.4/activejob/CHANGELOG.md)): a singular association queried by its plural name; a duration passed as an SQL bind value; a transaction block left with `return`, `break` or `throw`, which now commits; tests without assertions warning; and a time-with-zone job argument keeping its zone. Each depends on run-time values or on pairing lines a search can't pair. The last doesn't apply here, since the application doesn't load Active Job. S3 reads for the first four.
- **Rails 8.0 rules search can't find** ([8.0 release notes](https://guides.rubyonrails.org/8_0_release_notes.html#active-record-removals), [Active Record changelog](https://github.com/rails/rails/blob/v8.0.5.2/activerecord/CHANGELOG.md), [Active Support changelog](https://github.com/rails/rails/blob/v8.0.5.2/activesupport/CHANGELOG.md)): unregistered database adapters; nested association inference for namespaced models; and non-symbol keys in encrypted configuration. The first doesn't apply here, since `mysql2` is an adapter Rails ships. S4 reads for the other two.
- **Rails 8.1 rules search can't find** ([8.1 release notes](https://guides.rubyonrails.org/8_1_release_notes.html#action-pack-removals), [Action Pack changelog](https://github.com/rails/rails/blob/v8.1.4.1/actionpack/CHANGELOG.md), [Active Model changelog](https://github.com/rails/rails/blob/v8.1.4.1/activemodel/CHANGELOG.md)): semicolons in query strings; adding a `Time` to a time with zone; order-dependent finders with no order; `insert_all` through an association with unsaved records; a route to a missing controller returning 500; the cookie size limit counting the cookie's name; and integer casting of very long strings. Several depend on what clients send. S5.
- **Defaults search can't find** ([configuring guide](https://guides.rubyonrails.org/configuring.html#config-active-support-raise-on-invalid-cache-expiration-time)): invalid cache expiry raising (S6), migration timestamp validation (S7), and JSON escaping (S9).
- **Production-only configuration.** Whether a secret key is set (`config/initializers/secret_key.rb:4`), which proxies sit in front and whether they forward ports (`config/initializers/trusted_proxies.rb:4`), and the three spam and virus scanners. S1's extra boot variant covers the first. The others need the client's environment, in S5 and at deploy.
- **Database server versions.** Rails 8.0 drops MySQL 5.5. The repository names no server version and the CI image is untagged (`docker-compose.yml:23`). The client answers this before S4.
- **Production data.** Whether any user or organization stored the "Astana" time zone (S3), and whether every stored `options` and `payload` value reads back under an explicit YAML coder (S6). The migrations here are small; how the per-server message databases behave at production size isn't something a sandbox shows.
- **The 39 files the suite never loads.** They include 17 controllers, 8 scheduled tasks and the SMTP server process. S1 brings the worker under test. For the rest, the review's eager-load pass on each hop proves they load and nothing about what they do.
- **Whether the migration waiter's boot variant reaches line 18.** The boot record shows the process started. S1's test makes the question moot.
- **Whether full pages render in the test environment once the asset gems load there.** The checkout says they don't today (`spec/requests/messages_controller_spec.rb:50`), and the project's 7.2 branch changed the Gemfile group to fix it. We didn't run that change. S1 settles it, and S1's request set depends on the answer. Added by the independent review.
- **Which real messages are slow to match.** The 8.0 defaults give every pattern one second. Whether any message in production takes longer in `lib/postal/message_parser.rb:101` depends on the mail, and a timeout there is swallowed. Reading the patterns in S8 narrows it; only production mail settles it. Added by the independent review.
- **Whether API consumers depend on escaped JSON.** The 8.1 defaults change the bytes of every API response that contains `<`, `>` or `&` (`app/controllers/legacy_api/base_controller.rb:103`). Who parses those bodies, and how, isn't in the repository. The client answers this before S9. Added by the independent review.
- **Resolving hop by hop.** Each hop was resolved from today's lock. S4 and S5 resolve from the previous stage's lock, which may pick different versions. The `resolve` check on each settles it.
- **The `quirks_mode` disagreement** between our rule and the project's 7.2 branch. S3's suite run with `json` pinned settles nothing by itself; the pin makes the answer unnecessary until S10, which runs on 8.1 where both sources agree.
