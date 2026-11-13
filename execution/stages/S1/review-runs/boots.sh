#!/bin/bash
# Review probe for S1: start the application the way a server process does,
# once per optional feature that an environment variable can switch on, then
# load every file with eager loading on.
boot() {
  name="$1"; shift
  out=$(env "$@" bundle exec ruby -e 'require "./config/environment"; puts "BOOT OK #{Rails.version} #{Rails.env}"' 2>&1 | tail -2 | tr "\n" " ")
  echo "$name: $out"
}
boot default
boot oidc OIDC_ENABLED=true OIDC_IDENTIFIER=postal-sandbox OIDC_ISSUER=https://oidc.example.com
boot oidc-no-discovery OIDC_ENABLED=true OIDC_DISCOVERY=false OIDC_IDENTIFIER=postal-sandbox OIDC_ISSUER=https://oidc.example.com OIDC_AUTHORIZATION_ENDPOINT=https://oidc.example.com/authorize OIDC_JWKS_URI=https://oidc.example.com/jwks OIDC_TOKEN_ENDPOINT=https://oidc.example.com/token OIDC_USERINFO_ENDPOINT=https://oidc.example.com/userinfo
boot oidc-local-auth-off OIDC_ENABLED=true OIDC_LOCAL_AUTHENTICATION_ENABLED=false OIDC_IDENTIFIER=postal-sandbox OIDC_ISSUER=https://oidc.example.com
boot migration-waiter MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1
boot rails-log LOGGING_RAILS_LOG_ENABLED=true
boot sentry LOGGING_SENTRY_DSN=http://placeholder@127.0.0.1:9/1
boot production RAILS_ENVIRONMENT=production RAILS_ENV=production
boot secret-key RAILS_SECRET_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
boot clamav CLAMAV_ENABLED=true
boot rspamd RSPAMD_ENABLED=true
boot spamd SPAMD_ENABLED=true
boot smtp-tls SMTP_SERVER_TLS_ENABLED=true

echo "### eager load, test environment"
bundle exec ruby -e 'require "./config/environment"; Rails.application.eager_load!; n = %w[UserController Worker::Process SMTPServer::Server ScheduledTask UserInvite HealthServer UserCreator Postal::HelmConfigExporter Postal::MessageInspectors::Clamav Postal::MessageInspectors::Rspamd Postal::MessageInspectors::SpamAssassin Postal::SpamCheck Postal::YamlConfigExporter ReplySeparator IncomingMessagePrototype WellKnownController].map { |c| Object.const_get(c) }.size; puts "EAGER OK, #{n} of the never loaded constants resolved"' 2>&1 | tail -3
echo "### eager load, production environment"
RAILS_ENVIRONMENT=production RAILS_ENV=production bundle exec ruby -e 'require "./config/environment"; Rails.application.eager_load!; puts "EAGER OK #{Rails.env}"' 2>&1 | tail -3

echo "### rows the worker boot check leaves behind"
bundle exec rspec spec/lib/worker/process_spec.rb 2>&1 | grep "examples,"
bundle exec ruby -e 'require "./config/environment"; puts "scheduled_tasks=#{ScheduledTask.count} worker_roles=#{WorkerRole.count}"' 2>&1 | tail -1

echo "### new specs, random order, twice"
for seed in 1 4242; do bundle exec rspec --order random --seed $seed spec/lib/worker/process_spec.rb spec/lib/smtp_server/server_spec.rb spec/requests spec/models/credential_spec.rb spec/models/webhook_request_spec.rb spec/scheduled_tasks 2>&1 | grep -E "examples,|rspec \./"; done

echo "### lock and manifest against the base"
git diff --stat upgrade/baseline HEAD -- Gemfile Gemfile.lock app lib config db script bin | tail -1
echo "files changed outside spec/: $(git diff --name-only upgrade/baseline HEAD | grep -v '^spec/' | wc -l)"
