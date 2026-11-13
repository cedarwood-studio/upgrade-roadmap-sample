# Independent review of S3: Rails 7.1.6 to 7.2.4 (fifth review)

**Verdict: pass. Two small differences for the author to declare. No application code needs to change, and the stage does not go back.**

This is the fifth review of this stage. The defect from the fourth review is fixed and we confirmed the fix. This time we went where no check and no earlier review had been: the server-level pages, with a real message database behind them, on both Rails versions. They answer the same. We found two more differences of the small kind, one in an optional log and one in a developer tool. Neither changes a response, stored data or whether a process starts.

## What we found

### 1. Error entries in the Rails log gain a "Causes:" block (declare)

This belongs to the Rails log difference the stage already declares. It only shows with `LOGGING_RAILS_LOG_ENABLED=true`.

When an error was raised while handling another error, Rails 7.2.4 adds three lines to the log entry: a blank line, `Causes:`, and one line naming the original error. We measured it with a malformed JSON body sent to the API. Rails 7.1.6 logs the parse error and its trace. Rails 7.2.4 logs the same and adds `JSON::ParserError (unexpected token at '{not json')` under `Causes:`.

We compared 1060 Rails log lines per side. Beyond the `Completed` and `Rendered` difference already declared, this is the only one. It is in none of the seven changelogs we read. The source is the installed code, `action_dispatch/middleware/debug_exceptions.rb` in Action Pack 7.2.4. The response is the same on both versions (400), and Postal's own request log is the same.

The notes say that in the earlier sample no other log line differs. That is true of that sample, which had no error with a cause. One more sentence in the declaration covers it.

### 2. The console prompt changes (declare)

`postal console` starts the Rails console. On 7.1.6 the prompt is `irb(main):001>`. On 7.2.4 it is `postal(prod)>`: the application name and the environment, with no line number. The banner and the results are the same.

The Railties 7.2 changelog lists it as "Rails console now indicates application name and the current Rails environment" (https://github.com/rails/rails/blob/v7.2.4/railties/CHANGELOG.md). It matters only to a script that drives the console and waits for the old prompt.

### 3. json is still not pinned (risk, for another stage)

Carried from all four earlier reviews. Active Support 7.2 and 8.0 break with json 3, and the plan put a `json < 3` pin in S2. The Gemfile has none. The lock holds json 2.7.1 and JSON responses work today. This needs settling in S2's follow-up or before S4 relocks.

### Notes

- **The fourth review's fix holds.** The Rails log difference is declared with both sources, and the count of declared changes is three. The three new examples pass on 7.2.4 and all three fail against the 7.1.6 lock. The request specs pass in three random orders, so the new spec puts back the loggers it replaces.
- **The server-level pages answer the same on both versions.** 187 responses per side: 184 identical to the byte, 3 that differ only in the clock or a random boundary.
- **Nine requests answer 500 on both versions alike.** None is caused by this stage. They are the raw HTML view of a message with no HTML part (3), a message id that does not exist (2), the deliveries list asked for as JSON (1), a route posted with an unknown endpoint type (2), and the new message form posted with blank fields (1). Worth a ticket outside the upgrade.
- **Sentry receives the same events.** Six requests on each version produced the same 3 events, with the same exception types, cause chain and transaction names.
- **Still open, and the notes say so:** the author did not run `bin/rails app:update`, the client has column names for stored "Astana" values but no query, the seventh change under S3 in the plan still asks for the withdrawn secret key declaration, and `db/schema.rb` will be restamped by the next migration run in development.

## What we did

- Read 7 of the 12 component changelogs for 7.2 from top to bottom, 385 entries. The other five components are not loaded by this application. Nine entries touch something the application has. Eight were already handled or declared; the ninth is finding 2. We chased seven more that looked as if they might apply and measured that they do not.
- Opened all 16 framework call sites that the suite loads and never runs, or never loads. None is at risk on 7.2.4. Seven ran in this review.
- Compared with the project's two upgrade branches and its open pull request for Rails 8.1. They change 11 application files this stage does not. None is a break this stage needed.
- Made 7 attempts to break the stage:
  - the stage's diff against S2: three application lines changed;
  - 187 production requests on each version as a signed-in user, with a message database holding 4 messages: every server-level page, 27 invalid form posts, a create and a destroy, the legacy API, and 3 mails;
  - the lock against S2: the 12 framework gems and the `rails` gem, connection_pool, minitest and useragent, and nothing else;
  - 14 server-style boots on 7.2.4, each optional feature on by itself and all together, with eager loading, deprecations set to raise, and all 39 files the suite never loads: 14 start;
  - the stage's specs on 7.2.4 (16 examples, 0 failures) and against the 7.1.6 lock (11 examples, 7 failures, the 7 the notes predict);
  - what reaches Sentry, on both versions;
  - the console on a terminal, on both versions.

## What we did not do

- We read 9 of the 16 call sites without running them again: the worker's five connection pool lines, the slow query printer, the IP pool destroy guard, the route error line and the update rake task. The third and fourth reviews ran them on 7.2.4, and since then the branch has changed only one spec file and the baseline list.
- We did not repeat the fourth review's cookie replay between versions, its migration redo, or its start of the worker, SMTP server and web server as real processes. The application code has not changed since.
- We did not process a queued message through the worker, send mail over SMTP, run a spam or virus scan, or switch on TLS for a live SMTP session. The sandbox has no network. The suite covers the message processors.
- We did not render the messages that a held or bounced delivery sends to an HTTP endpoint or a webhook.
- Our first run of the page walk failed on a mistake in our own script, and the second put a changing token in the first line of each file. We fixed both and report the third run. Our first look at the console used piped input, which shows no prompt; the second used a terminal.
- We did not fix anything.

## Where we stopped looking

We stopped when the method was done. A framework hop changes many small things, and each review of this stage has found one smaller than the last: a process that would not start, headers on error pages for HEAD requests, the shape of a log line, and now an extra block in that log and a console prompt. We do not claim these are the last. We claim the stage makes no undeclared change to a response, to stored data or to whether a process starts in anything we ran, and that each difference we measured is sourced.

## For the author

1. Add one sentence to the Rails log declaration in the notes and the pull request text: error entries gain a `Causes:` block when the error has a cause. Source: `action_dispatch/middleware/debug_exceptions.rb` in Action Pack 7.2.4. Evidence: `review-runs/try-1794549866.log`.
2. Declare the console prompt with the Railties changelog entry as its source. Evidence: `review-runs/try-1794550114.log`.
