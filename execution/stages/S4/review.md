# Independent review of S4: Rails 7.2.4 to 8.0.5.2

**Verdict: pass. Three small differences for the author to declare or correct, two corrections to the notes, one risk carried forward. No application code needs to change, and the stage does not go back.**

We did not write this stage. We read it, read the Rails 8.0 changelogs against the application, opened every framework call the test suite loads and never runs, compared the work with the project's own upgrade branches, and then tried to break it by running the application on both Rails versions side by side. The one application change, `reset_token: false` on `has_secure_password`, is right and it is enough: the password reset flow behaves the same on both versions from the first form to the new password.

## What we found

### 1. The Vary declaration describes the wrong "before" for real clients (declare)

The stage declares that responses had no `Vary` header on 7.2.4 and have `Vary: Accept, X-Requested-With` on 8.0.5.2. The second half is right on every request we made. The first half is true only of a request that sends no `Accept` header, which is how the recorded requests are made.

A request that does send one already got `Vary: Accept` on 7.2.4. Browsers, curl and HTTP libraries all send one. In our walk, 27 of 230 requests carried `Vary: Accept` on 7.2.4, and those are exactly the 27 that sent an `Accept` header. Through a running puma, `GET /ip` and `POST /api/v1/send/message` with `Accept: */*` go from `Vary: Accept` to `Vary: Accept, X-Requested-With`.

So for real traffic the change is one added field name, not a new header. The paragraph written for the client says a cache "will now keep separate copies per `Accept`". For these requests it already did. What is new is `X-Requested-With`. Nothing undeclared reaches a client, so this is a correction to the declaration and to the question put to the client, not a defect.

### 2. Error entries in the Rails log change shape (declare)

This only shows with `LOGGING_RAILS_LOG_ENABLED=true`. On 7.2.4 an error that has a cause is logged as the error line, its trace and a `Causes:` block. On 8.0.5.2 the error line is followed by a `Caused by:` line, then an `Information for:` section and an `Information for cause:` section, each with a trace. One class name changes as well: a malformed query string is reported as `ActionDispatch::ParameterTypeError` where it was `Rack::QueryParser::ParameterTypeError`, because Action Pack 8.0 parses parameters itself.

We compared 1241 Rails log lines on 7.2.4 with 1249 on 8.0.5.2. The responses are the same on both versions (400).

### 3. One exception message changes in Postal's own log (declare)

`ActionController::ParameterMissing` now reads "param is missing or the value is empty or invalid: domain". It read "param is missing or the value is empty: domain". No response carries the text: the request answers 400 with an empty body on both versions. It does appear in the `exception_message` field of Postal's own request log line, which is on by default, and in the Rails log. It matters to a log search or an alert that matches the old wording.

### 4. A count in the notes is off by one (note)

The notes say that without the option, 5 of the 6 password reset examples fail on 8.0.5.2. We measured 4 of 6. The 5 belongs to the first draft, which had 7 examples. All 6 pass against the 7.2.4 lock, as the notes say.

### 5. `db:migrate` on an empty database is now measured (note)

The stage declares this change and says it did not measure it. We did. On 8.0.5.2 it exits 0 with 28 tables and 19 migration versions. On 7.2.4 it fails on the first migration. The declaration is correct and can cite the run.

### 6. json is still not pinned (risk, carried)

Carried from every S3 review and from this stage's own follow-ups. Active Support 8.0 breaks with json 3, and the Gemfile has no `json < 3`. The lock holds 2.7.1, this relock did not move it, and JSON responses are the same on both versions today. The project's own 7.2 branch has the pin. It should go in before the next relock.

## What we did

- Read 7 of the 12 component changelogs for 8.0, 333 entries. The other five components are not loaded by this application. We read the first line of every entry and the full text of each one that removes, renames, moves or newly defines something. Thirteen entries touch something the application has. Twelve were already handled, declared or measured the same on both versions; the thirteenth is behind finding 3.
- Opened all 16 framework call sites that the suite loads and never runs, or never loads. None is at risk on 8.0.5.2. Fifteen ran in this review; the sixteenth we read against the installed code of both versions.
- Compared with the project's two upgrade branches and its open pull request for Rails 8.1. They change 10 application files this stage does not. None is a break this stage needed.
- Made 9 attempts to break the stage:
  - the lock against S3: the 12 framework gems and `rails`, the five declared or forced gems, one added dependency line, and nothing else;
  - 14 server-style boots, each optional feature on by itself and all together, with eager loading, deprecations set to raise, the routes drawn and all 39 files the suite never loads: 14 start;
  - the rake tasks and the production update task;
  - the stage's specs, the request specs in three random orders, and the password reset spec with the option removed on both versions;
  - `db:migrate` on an empty database on both versions;
  - 230 production requests on each version against the same rows: 70 identical, 159 that differ only in `Vary`, 1 that differs only in a random boundary and the clock. Seven mails, identical;
  - 138 query strings, form bodies, JSON bodies and multipart bodies parsed on both versions: identical;
  - puma, the worker and the SMTP server started as the Procfile starts them, plus the console and the runner: all start;
  - a signed-in session carried from 7.2.4 to 8.0.5.2 and back: accepted both ways, CSRF token included.

## What we did not do

- We did not read the changelogs of the five components the application does not load.
- We did not run `app/models/route.rb:122`. Our bad endpoint is stopped by an earlier guard on both versions.
- We did not capture what Sentry receives. The S3 review did, and finding 3 says what we expect to differ there.
- We did not process a queued message through the worker, send mail over SMTP, run a spam or virus scan, or open a TLS session on the SMTP server. The sandbox has no network. The worker ran one tick of its jobs and all nine scheduled tasks.
- We did not run the whole suite again; the stage's check did. We ran the stage's specs and the request specs.
- Our first page walk compared badly because our own script changed the disk size shown in the page header between runs. We masked it and report the second run. One part of our parameter script, which had each version read the other's signed cookies, failed on a mistake of ours; the session test afterwards answers that question through the application.
- We did not fix anything.

## Where we stopped looking

We stopped when the method was done. A framework hop changes many small things, and we do not claim these are the last. We claim the stage makes no undeclared change to a response, to stored data or to whether a process starts in anything we ran, and that each difference we measured is sourced.

## For the author

1. Correct the Vary declaration in `expected-differences.json`, the notes and the pull request text: requests that send an `Accept` header already carried `Vary: Accept` on 7.2.4, and gain `X-Requested-With`. Reword the paragraph and the question for the client to match. Evidence: `review-runs/try-1794552515.log`, `review-runs/try-1794552582.log`.
2. Declare the Rails log change for error entries. Evidence: `review-runs/try-1794552515.log`.
3. Declare the `ParameterMissing` message in Postal's own log. Evidence: `review-runs/try-1794552739.log`.
4. Change "5 of the examples fail" to 4, and replace "We did not measure it on 8.0.5.2" with the measurement. Evidence: `review-runs/try-1794551998.log`.
