### Baseline on Rails 7.1.6, Ruby 3.4.6

We recorded what the application does today, before any version changes. Nothing in the checkout was edited.

### Numbers from the baseline run

- **Test suite:** 851 examples, 17 failed, 0 pending, 0 errors outside examples, 206 to 216 seconds across runs.
- **The 17 failures:** 16 in `spec/lib/dns_resolver_spec.rb` and 1 in `spec/senders/smtp_sender_spec.rb`. All need live DNS and the sandbox runs the suite with the network off. This matches the roadmap. They count as failing in the reference set, so later stages are held to the other 834.
- **Rails deprecation warnings in the suite:** 0 distinct, 0 occurrences.
- **Ruby warnings:** 5 distinct, 2 in the deprecated category, as the roadmap reported.
- **Recorded requests:** 170 per recording, recorded twice. 155 are explicit and 15 are the parameterless GET routes added automatically.
- **Requests masked as noise:** 2 of 170.

### What the request set covers

We assembled this list from `config/routes.rb`, the controllers and the request specs. In a client engagement it would come from logged production requests; here it does not.

- Signed out: the sign-in page, redirects to sign-in from protected pages, wrong password, unknown user, the password reset form, a reset with an unknown address, a valid and an unknown reset token, a reset with a blank password, `/ip`, `/.well-known/jwks.json`, and an unknown path.
- Legacy API, all four endpoints: no key, invalid key, key of a suspended server, valid key with missing parameters, a sender domain the server does not own, a successful send, a message lookup with every expansion, lookup by GET, not found, missing id, non-scalar id, and deliveries.
- Signed in as an administrator: every controller in the web interface at least once. Organizations, servers (show, edit, limits, retention, queue, spam, delete, advanced, both help pages), domains for a server and for an organization (list, new, setup, verify), credentials, routes, HTTP, SMTP and address endpoints, webhooks and webhook history, track domains, IP pool rules at both levels, organization IP pools, users, IP pools, IP addresses, and own settings.
- Messages: outgoing, incoming, held and suppression lists, a search query, a query with an unparseable time, the JSON list, and for one multipart message with an attachment the show, activity, plain, html, html_raw, attachments, attachment download, headers, raw download, spam checks and deliveries views.
- Form posts that fail validation, as HTML, for organizations, servers, domains, credentials, routes, HTTP endpoints, address endpoints, webhooks, users, IP pools and own settings, and as JSON for organizations, credentials, and also users. One successful JSON update of a credential.
- Signed in as a non-administrator member: sign-in with a safe and an unsafe `return_to`, the organization page, and four administrator-only pages that answer "Not permitted".
- Sign-out, and the redirect that follows it.

### How the recording is set up

- `exec/parity-setup.rb` creates the records with the app's own factories and models. Every id, uuid, token, API key, DKIM key and timestamp is fixed. The DKIM key is the committed CI fixture `docker/ci-config/signing.key`.
- The recorder starts from an empty database server, so the setup loads `db/schema.rb` first. It does this on a second connection because schema statements end an open transaction in MySQL.
- The setup provisions the message databases for the two servers and writes three messages (outgoing multipart with attachment, incoming, held) as hand-written raw mail, because the mail library picks random MIME boundaries.
- The setup runs `RAILS_GROUPS=assets rake assets:precompile`, as the Dockerfile does, and points the view helpers at the resulting manifest. Without this every HTML page records a Sass error instead of a page, because the test environment does not load the assets group. The existing request spec for messages has a comment about the same limitation. The benefit is that each recording builds the assets on the version under test, so `sass-rails`, `coffee-rails` and `uglifier` are exercised at every hop, and the asset digests in the pages pin the compiled output.

### The two requests masked as noise

- **"api: send/message valid":** the app generates a random message id and message token for each send, and both are in the response body.
- **"admin: POST credentials invalid":** the app generates a random key for a new credential before validation, and the re-rendered form shows it.

Both come from the application's own randomness. The setup uses fixed values. For these two the body is masked and the status and headers are still compared. The JSON variant of the failed credential post, and the credential new and edit pages, are recorded in full. The successful send is placed last in the list so the message it creates does not appear in any other recorded page.

### Requests that record an exception

The test environment sets `show_exceptions = false`, so these record the exception class and message rather than an error page. That is the app's real behavior in this environment.

- Unknown path: `ActionController::RoutingError`.
- Unknown organization and unknown server: `ActiveRecord::RecordNotFound`.
- Unknown message: `Postal::MessageDB::Message::NotFound`.
- Webhook history for an unknown request: `Postal::MessageDB::Webhooks::RequestNotFound`.
- Deleting an organization with a blank confirmation text: `ActionController::UrlGenerationError`. This one looks wrong. `OrganizationsController#destroy` redirects with `@organization` before anything has loaded it when `confirm_text` is blank, so the user gets an error instead of the alert. With a non-blank wrong text it redirects correctly, and we record that case too. We pinned the behavior as it is and did not fix it.

### What the request set does not cover

- Requests that change data on success, other than one API send and one credential update: creating and deleting organizations, servers, domains and the rest, suspending a server, retrying or releasing a message, DKIM regeneration, and the DNS check actions (which need the network).
- API parameters sent as a JSON body with `Content-Type: application/json`. The recorder sends form parameters, so the API calls use the `params` form field. The suite covers the JSON body path.
- `POST /api/v1/send/raw` with a valid message. Only the missing-parameter case is recorded.
- OIDC sign-in, which is off in this configuration.
- The click and open tracking middleware, which answers on track domains rather than the web hostname.
- Error pages as a browser sees them in production (404 and 500 HTML).
- Session cookie values. The cookie header is not compared, only the cookie names. The app also generates a new secret key per process here because none is configured, so a cookie from one recording cannot be replayed into another. The plan's S1 test for "a session cookie issued on 7.1.6 is still accepted" needs a fixed secret key and is not provided by this recording.
- Webhook history with data. It reads from the message database, and the fixture has none there.
- The clock is held at 2026-01-01 12:00 UTC by the recorder, so behavior that depends on the real date is not exercised.

### Where the roadmap was silent

- The roadmap counts 0 deprecation warnings on 7.1.6, and the suite agrees. The recorder's log shows one that the suite output does not: "Setting action_dispatch.show_exceptions to false is deprecated. Set to :none instead", 10 occurrences in the first recording, raised from `lib/tracking_middleware.rb:13`. It is the same setting the plan already changes in S3 (`config/environments/test.rb:28`), so no new work, but the count on 7.1.6 is 1 distinct, not 0, once requests go through the full middleware stack.
- The roadmap did not mention that HTML pages cannot render in the test environment without a precompiled asset build. The setup works around it as described above.

### Follow-ups, not done here

- The other S1 items in the plan are not part of this phase: characterization tests for the eight scheduled tasks, the stored-YAML test for `Credential#options` and `WebhookRequest#payload`, the session cookie test, and the boot check for the SMTP server and worker.
- The blank confirmation text error in `OrganizationsController#destroy` is worth a fix by the owner, separate from the upgrade.
