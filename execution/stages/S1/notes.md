### S1: Record the baseline on Rails 7.1.6

No version changed in this stage and no application code changed. We added 65 test examples in 14 new spec files and one spec helper. No existing test was edited.

### Numbers from the check

- **Attempts used:** 1 of 4. The check was green.
- **Tests:** 851 examples before, 916 after. 834 passed before, 899 pass after. 65 added, 0 added failing, 0 regressed, 0 missing.
- **Recorded requests:** 170 replayed, 170 identical, 0 different. 2 are masked as noise, the same 2 as in the baseline notes.
- **Rails deprecation warnings:** 0 before, 0 after.
- **Ruby warnings in the deprecated category:** 2 before, 3 after. The new one is described under "Where the roadmap was wrong or silent".

### What was added, in the order a reviewer would read the diff

**Scheduled tasks (50 examples, 8 files in `spec/scheduled_tasks/`).** One file for each of the eight task classes the suite did not load. Each pins what `#call` does and what `.next_run_after` returns at a fixed time.

- `ActionDeletionsScheduledTask`: soft deleted organizations and servers are destroyed, the servers of a deleted organization go with it, and each destroyed server has its message database dropped. The drop itself is replaced with a recorder in this spec, because the suite shares one message database.
- `CheckAllDNSScheduledTask`: which domains and track domains are selected, and that domains are checked with `:auto`. The DNS lookups are replaced with a recorder; the sandbox has no network.
- `CleanupAuthieSessionsScheduledTask`: sessions inactive for more than 12 hours and persistent sessions past their expiry are marked inactive, and no row is deleted.
- `ExpireHeldMessagesScheduledTask`: runs against the real test message database. An expired hold becomes status `HoldCancelled` with a delivery row.
- `ProcessMessageRetentionScheduledTask`: runs against the real test message database. Messages older than 60 days and raw tables older than 30 days are removed under the default settings, and nothing is removed when the three settings are empty.
- `PruneSuppressionListsScheduledTask` and `PruneWebhookRequestsScheduledTask`: run against the real test message database.
- `SendNotificationsScheduledTask`: the email, the `notified_at` timestamp, the `SendLimitExceeded` webhook request and its payload, and that a second run does not notify again.

**Stored YAML columns (11 examples, `spec/models/credential_spec.rb` and `spec/models/webhook_request_spec.rb`).** For `Credential#options` and `WebhookRequest#payload` we pin the exact text that 7.1.6 writes for string keyed and symbol keyed hashes, and we read rows whose column was set to that text with plain SQL, bypassing the model. An empty hash is stored as NULL and NULL reads as an empty hash. The webhook payload example uses the payload the application itself builds for a send limit event, which has symbol keys.

**Session cookie (5 examples, `spec/requests/session_continuity_spec.rb`).** We signed in once on 7.1.6 with a fixed secret key and copied the three cookies the application issued (`browser_id`, `user_session`, `_postal_session`) into the spec. The spec sends them back with the same secret and checks that the request is treated as signed in, that the stored session row is updated, and that the session id and flash inside the encrypted `_postal_session` cookie are read. Two control cases show the test is sensitive: with a different secret the session cookie is not read, and without the sign-in cookies the request is redirected to the login page.

**Boot checks (2 examples, `spec/lib/smtp_server/server_spec.rb`, `spec/lib/worker/process_spec.rb`, helper in `spec/helpers/process_helpers.rb`).** Each starts the real script (`script/smtp_server.rb`, `script/worker.rb`) as a child process on free local ports.

- SMTP server: we connect, read the `220` greeting, send `QUIT`, read `221`, call the health endpoint, send TERM and expect exit status 0.
- Worker: we call the health endpoint, wait until all nine scheduled task rows exist with a future run time and the `tasks` role is held, send TERM, and expect exit status 0 and the role released.

### What needed judgment

- **The 17 DNS examples.** The plan asks for these to run with the network on so they count as passing. The check runs the suite with the network off and we cannot change that from inside a stage. They remain failing in the reference, as the baseline notes say, and later stages are held to the 899 that pass. Someone with network access should run `spec/lib/dns_resolver_spec.rb` and `spec/senders/smtp_sender_spec.rb` once per hop.
- **The request set.** It was assembled and recorded in the baseline phase (170 requests). We did not change it in this stage.
- **Session cookie and the secret key.** The application has no fixed secret in the test environment, so the spec substitutes one for the duration of each request by replacing the key generator the application hands to its middleware. The key generator is still built by the application (`Rails.application.key_generator`), so digest and serializer settings come from the real configuration. This holds continuity for the cookie format. It does not prove anything about the production secret, which the plan lists as an unknown for S6.
- **The worker boot check writes outside a test transaction.** The worker is a separate process, so its rows in `scheduled_tasks` and `worker_roles` are committed. The spec turns transactions off for that one group and deletes those rows before and after.
- **Mocks in two task specs.** Where a task would reach the network (DNS) or destroy shared state (dropping the message database), we record the call and its arguments in place of running it. Everything else runs for real.

### Behavior we pinned that looks wrong

- `PruneWebhookRequestsScheduledTask` deletes every row with an id up to the newest row older than 10 days. A recent row recorded before an old one is deleted with it. This can only happen if timestamps are out of order with ids, so it is unlikely in practice.
- `CheckAllDNSScheduledTask` never checks a domain that has never been checked (`dns_checked_at` empty), while it does check track domains in that state. This may be intended.
- `SendNotificationsScheduledTask` records the notification time even when the organization has no users to email.

### Where the roadmap was wrong or silent

- **A Ruby deprecation the roadmap did not list.** Booting the SMTP server prints "`$\` is deprecated" from `app/lib/smtp_server/server.rb:46` on Ruby 3.4.6. The roadmap counted 2 Ruby warnings in the deprecated category; with the SMTP server booted it is 3. It is a Ruby matter, not a Rails one, and Ruby is out of scope for this plan. The server relies on that variable for line endings on `print`, so removing it is a behavior change that needs care.
- **YAML columns hold symbol keys.** The roadmap names the two columns but not their contents. Real webhook payloads are written with symbol keys (`:server:`, `:volume:`). Any serializer change in S6 has to keep reading symbols; the new tests will fail if it does not. `Time` values are refused on write today (`Psych::DisallowedClass`), which we observed but did not pin.
- **Message database drop on destroy.** A server loaded from the database and destroyed drops its message database from an `after_commit` callback (`app/models/server.rb:92`). The plan reads that callback in S6 for ordering only. It is also the one place where a scheduled task destroys data outside the main database, and it is now covered.

### Deprecation warnings that remain

- **Rails, in the suite:** 0.
- **Rails, in the request recorder only:** the `show_exceptions = false` warning described in the baseline notes. It belongs to S3.
- **Ruby, deprecated category:** 3. Two come from gems (`webmock`, `domain_name`), one from `app/lib/smtp_server/server.rb:46`.

### Follow-ups, not done here

- Run the 17 DNS examples with the network on.
- Decide what to do about `$\` in the SMTP server before a Ruby upgrade.
- The web process boot is covered by the recorded request set, not by a separate process check. A check that starts Puma the way `bin/postal web-server` does would close that gap.
- The boot checks add about 15 seconds to the suite.
