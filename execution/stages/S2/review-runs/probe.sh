#!/bin/bash
# Review probe for S2: the lock, the boots, the rake task list before and after,
# eager loading, and the linter configuration the stage edited.
BASE=upgrade/s1-record-the-baseline-on-rails-7-1-6

echo "### 1. lock against the base"
git diff --numstat $BASE HEAD
git diff $BASE HEAD -- Gemfile.lock | grep '^[+-]' | grep -v '^+++\|^---'
echo "json in lock: $(grep -n '^    json ' Gemfile.lock)"
echo "json in Gemfile: $(grep -n 'json' Gemfile || echo none)"
echo "rake in lock: $(grep -n '^    rake ' Gemfile.lock)"
echo "-- bundle check"
bundle check 2>&1 | tail -2
echo "-- frozen bundle"
BUNDLE_FROZEN=true bundle exec ruby -e 'puts "FROZEN OK json=#{require "json"; JSON::VERSION}"' 2>&1 | tail -2
echo "-- bundle lock --local leaves the lock as committed?"
bundle lock --local 2>&1 | tail -2
git status --short Gemfile.lock
git checkout -q -- Gemfile.lock

echo "### 2. schema, then boots"
bundle exec rake db:create db:schema:load 2>&1 | tail -2
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
boot development RAILS_ENVIRONMENT=development RAILS_ENV=development
boot secret-key RAILS_SECRET_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
boot clamav CLAMAV_ENABLED=true
boot rspamd RSPAMD_ENABLED=true
boot spamd SPAMD_ENABLED=true
boot smtp-tls SMTP_SERVER_TLS_ENABLED=true

echo "### 3. eager load"
bundle exec ruby -e 'require "./config/environment"; Rails.application.eager_load!; n = %w[UserController Worker::Process SMTPServer::Server ScheduledTask UserInvite HealthServer UserCreator Postal::HelmConfigExporter Postal::MessageInspectors::Clamav Postal::MessageInspectors::Rspamd Postal::MessageInspectors::SpamAssassin Postal::SpamCheck Postal::YamlConfigExporter ReplySeparator IncomingMessagePrototype WellKnownController].map { |c| Object.const_get(c) }.size; puts "EAGER OK test, #{n} of the never loaded constants resolved"' 2>&1 | tail -2
RAILS_ENVIRONMENT=production RAILS_ENV=production bundle exec ruby -e 'require "./config/environment"; Rails.application.eager_load!; puts "EAGER OK #{Rails.env}"' 2>&1 | tail -2
RAILS_ENVIRONMENT=development RAILS_ENV=development bundle exec ruby -e 'require "./config/environment"; Rails.application.eager_load!; puts "EAGER OK #{Rails.env}"' 2>&1 | tail -2

echo "### 4. rake tasks, after (this stage)"
for e in test development production; do
  RAILS_ENVIRONMENT=$e RAILS_ENV=$e bundle exec rake -P > /tmp/after-$e.txt 2>/tmp/after-$e.err
  echo "$e: exit $? tasks $(grep -c '^rake ' /tmp/after-$e.txt) annotate mentions $(grep -ci annot /tmp/after-$e.txt) stderr lines $(wc -l < /tmp/after-$e.err)"
done
echo "-- does anything left call the annotate tasks or constant?"
grep -rnE "annotate_models|annotate_routes|set_annotation_options|Annotate\b|require ['\"]annotate" --include='*.rb' --include='*.rake' --include='*.yml' --include='*.yaml' --include='*.sh' --include='Rakefile' --include='Dockerfile' --include='Procfile*' --include='*.md' . 2>/dev/null | grep -v '^./CHANGELOG.md' | grep -v '^./vendor' | head
grep -rn -i annot bin script docker .github 2>/dev/null | head

echo "### 5. linter configuration"
bundle exec rubocop Gemfile Rakefile lib/tasks 2>&1 | tail -3

echo "### 6. rake tasks, before (base files put back in the throwaway copy)"
git checkout -q $BASE -- Gemfile Gemfile.lock lib/tasks/auto_annotate_models.rake .rubocop.yml
if bundle check >/tmp/bc.txt 2>&1; then
  for e in test development; do
    RAILS_ENVIRONMENT=$e RAILS_ENV=$e bundle exec rake -P > /tmp/before-$e.txt 2>/tmp/before-$e.err
    echo "$e: exit $? tasks $(grep -c '^rake ' /tmp/before-$e.txt) annotate mentions $(grep -ci annot /tmp/before-$e.txt)"
    echo "-- $e: task list difference, before to after"
    diff /tmp/before-$e.txt /tmp/after-$e.txt
  done
else
  echo "the base bundle is not installed here, so no before list: $(tail -2 /tmp/bc.txt | tr '\n' ' ')"
fi
git checkout -q HEAD -- Gemfile Gemfile.lock .rubocop.yml
git rm -q --cached lib/tasks/auto_annotate_models.rake 2>/dev/null; rm -f lib/tasks/auto_annotate_models.rake
git status --short | head
