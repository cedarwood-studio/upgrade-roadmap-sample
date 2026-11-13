## Independent review of S1: Record the baseline on Rails 7.1.6

**Verdict: pass.** The stage changes no application code, no version and no lock entry, and we found nothing in it that breaks. We did find gaps between what the plan asked this stage to pin and what it pinned. Those are recorded as risks for later hops, not as defects in this one.

### What we checked

- **The diff.** 14 files, all under `spec/`, 914 lines added, none removed. Nothing outside `spec/` moved against the baseline branch. The Gemfile and the lock are identical to the base.
- **The numbers in the notes.** The 14 new spec files hold 65 examples and all pass here. Run in random order with two different seeds, alongside the existing request specs, 86 examples passed both times. The worker boot check leaves no rows behind in `scheduled_tasks` or `worker_roles`.
- **Start-up.** We booted the application 13 ways on Rails 7.1.6: default, OIDC (three forms), migration waiter, Rails log, Sentry, production, a configured secret key, ClamAV, rspamd, SpamAssassin and SMTP TLS. All start. The migration waiter variant only starts once the schema is loaded, which is expected. Eager loading every file succeeds in both the test and the production environment.
- **Whether the new tests can fail.** We changed one application line at a time in a throwaway copy and reran the tests.
  - Stored YAML columns: switching to JSON fails both new model specs. Good.
  - Session cookie: changing the key generator digest fails the example that reads the encrypted cookie. Good.
  - Worker: making every job run and task run raise leaves all 51 worker and scheduled task examples green. Not good; see below.
  - SMTP server: removing the line ending setting makes the boot check hang instead of fail. See below.
- **The project's own upgrade branches.** Their application changes are all for version moves, so none applies to a stage that moves nothing. We compared their tests with ours instead.
- **The framework changelogs** do not apply to this stage. No version changed.

### What we found

1. **Risk: the worker test does not prove a job or a task can run.** The plan asked for tests of the worker's job and task runs with errors raised instead of swallowed, because Rails 8.1 stops loading the `benchmark` gem those two lines call (`app/lib/worker/process.rb:164` and `:256`). The stage added a boot check, which is useful, but the worker swallows errors and logging is off in tests, so the check stays green when both lines raise. This has to be closed before the 8.1 hop is trusted. No automated check shows it today.
2. **Risk: five plan items were not delivered and the notes do not say so.** The slow query explain path (`lib/postal/message_db/database.rb:333`), the assertion on the rewritten tracked link (`lib/postal/message_parser.rb:121`), the password reset flow to its end, the asset precompile file list, and a boot variant with a configured secret key. With the explain line and the link rewrite both broken, the existing specs still pass. Each belongs to a later hop.
3. **Note: the migration waiter is protected by a boot variant, not by a test.** No example runs its real call. The boot variant the checks now run does catch a break there, and it was added after this stage was committed.
4. **Note: the SMTP boot check can hang.** It reads the greeting with no time limit. Without the line ending, it waited until we killed it after 84 seconds, and RSpec then reported 0 failures. The notes flag that same line ending as a change to handle with care, so the test should fail there, not stall.
5. **Note: one session example guards the cookie format, not three.** The two "signed in" examples pass through the sign-in cookie, which Rails does not encrypt.

Three of the five findings would not have been shown by any automated check.

### What we did not do

- We opened 14 of the 16 call sites listed for reading. The two we did not open are the first line of the development and production environment files; we ran the production one and did not touch the development one.
- We read the first 305 of 434 lines of the record of the project's upgrade work in full and the rest by its headings.
- We did not run the 17 examples that need the network. The sandbox has none.
- We did not replay the 170 recorded requests ourselves; we relied on the check's result of 170 identical.
- Adding `load_defaults 7.1` on top of 7.0 stops the application from loading. We saw it and did not chase the cause. It belongs to the stage that moves the defaults.
- Our first probe script had no time limit, hung on the SMTP case and was stopped by the harness with no output. We reran every part of it with limits.

We stopped when the method was done. The promise for this stage stands as: no undeclared behavior change, each difference sourced. The one difference the stage declares, a third Ruby deprecation warning from booting the SMTP server, is in its notes.
