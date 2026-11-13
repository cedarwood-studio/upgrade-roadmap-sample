#!/bin/sh
# Fifth review, S3.
#  1. the lock against the S2 branch
#  2. a server-style boot with each optional feature switched on, one at a time and all together,
#     with eager loading and the 39 files the suite never loads
#  3. the stage's new specs on 7.2.4, and the Rails log spec against the 7.1.6 lock
#  4. what reaches Sentry, on both versions
#  5. the console banner and prompt, on both versions
# Usage: sh /out/r5-ops.sh
S2=upgrade/s2-remove-the-annotate-blocker
S3=$(git rev-parse --abbrev-ref HEAD)
echo "==== 1. lock against S2"
git diff -U0 $S2 HEAD -- Gemfile.lock | grep -E "^[+-] " | grep -vE "^[+-]      " | sort -k2 | tr -s ' ' | tr '\n' ';'
echo
echo "spec lines moved: $(git diff -U0 $S2 HEAD -- Gemfile.lock | grep -cE '^[+-]    [a-z]')  files changed since the fourth review's commit: $(git diff --stat 4ab36822c4e72c46f6a2eddefa441f45674c5ad3 HEAD | tail -1)"
git diff $S2 HEAD -- Gemfile | grep -E "^[+-][^+-]"

bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"

echo "==== 2. boots"
OIDC="OIDC_ENABLED=true OIDC_ISSUER=http://127.0.0.1:9 OIDC_IDENTIFIER=x OIDC_SECRET=y"
NODISC="$OIDC OIDC_DISCOVERY=false OIDC_AUTHORIZATION_ENDPOINT=http://127.0.0.1:9/a OIDC_TOKEN_ENDPOINT=http://127.0.0.1:9/t OIDC_USERINFO_ENDPOINT=http://127.0.0.1:9/u OIDC_JWKS_URI=http://127.0.0.1:9/j"
boot() {
  name=$1; shift
  out=$(env "$@" bundle exec ruby -e '
    require "./config/environment"
    Rails.application.deprecators.behavior = :raise
    Rails.application.eager_load!
    Zeitwerk::Loader.eager_load_all
    files = File.read("/out/r4-never-loaded.txt").split
    missing = files.reject { |f| $LOADED_FEATURES.include?(Rails.root.join(f).to_s) }
    c = Postal::Config
    puts "boot-ok rails=#{Rails.version} env=#{Rails.env} never-loaded=#{files.size - missing.size}/#{files.size} oidc=#{c.oidc.enabled?} local=#{c.oidc.local_authentication_enabled?} waiter=#{c.migration_waiter.enabled?} railslog=#{c.logging.rails_log_enabled?} sentry=#{!c.logging.sentry_dsn.nil?} rspamd=#{c.rspamd.enabled?} clamav=#{c.clamav.enabled?} spamd=#{c.spamd.enabled?} tls=#{c.smtp_server.tls_enabled?} static=#{Rails.application.config.public_file_server.enabled.inspect} inspectors=#{Postal::MessageInspector.inspectors.size}"
  ' 2>&1 | grep -vE "^No configuration|^Only using" | tail -2 | cut -c1-420)
  echo "$name: exit=$? $out"
}
boot default A=1
boot production RAILS_ENVIRONMENT=production
boot development RAILS_ENVIRONMENT=development
boot oidc $OIDC
boot oidc-no-discovery $NODISC
boot oidc-local-off $NODISC OIDC_LOCAL_AUTHENTICATION_ENABLED=false
boot migration-waiter MIGRATION_WAITER_ENABLED=true
boot rails-log LOGGING_RAILS_LOG_ENABLED=true
boot sentry LOGGING_SENTRY_DSN=http://k@127.0.0.1:9/1
boot rspamd RSPAMD_ENABLED=true
boot clamav CLAMAV_ENABLED=true
boot spamd SPAMD_ENABLED=true
boot smtp-tls SMTP_SERVER_TLS_ENABLED=true
boot everything-production RAILS_ENVIRONMENT=production $NODISC OIDC_LOCAL_AUTHENTICATION_ENABLED=false MIGRATION_WAITER_ENABLED=true LOGGING_RAILS_LOG_ENABLED=true LOGGING_SENTRY_DSN=http://k@127.0.0.1:9/1 RSPAMD_ENABLED=true CLAMAV_ENABLED=true SPAMD_ENABLED=true SMTP_SERVER_TLS_ENABLED=true

echo "==== 3. specs"
RAILS_ENVIRONMENT=test bundle exec rake db:create db:schema:load > /dev/null 2>&1
bundle exec rspec spec/lib/migration_waiter_spec.rb spec/lib/secret_key_spec.rb spec/requests/error_pages_spec.rb spec/requests/rails_log_spec.rb spec/requests/session_continuity_spec.rb 2>&1 | grep -E "examples,|Failure|rb:[0-9]+ #" | head -8
echo "-- Rails log spec in three random orders with the other request specs"
for seed in 1 22 333; do bundle exec rspec spec/requests --seed $seed 2>&1 | grep -E "examples," ; done
echo "-- against the 7.1.6 lock"
cp Gemfile /tmp/Gemfile.s3; cp Gemfile.lock /tmp/Gemfile.lock.s3
git show $S2:Gemfile > Gemfile; git show $S2:Gemfile.lock > Gemfile.lock
bundle exec rspec spec/requests/rails_log_spec.rb spec/requests/error_pages_spec.rb spec/lib/secret_key_spec.rb spec/lib/migration_waiter_spec.rb 2>&1 | grep -E "examples,|^rspec " | cut -c1-200 | head -12
cp /tmp/Gemfile.s3 Gemfile; cp /tmp/Gemfile.lock.s3 Gemfile.lock

echo "==== 4 and 5. Sentry and the console, per version"
one() {
  echo "######## $1: $(bundle exec ruby -e 'puts Gem.loaded_specs["rails"].version' 2>/dev/null)"
  RAILS_ENVIRONMENT=production LOGGING_SENTRY_DSN=http://k@127.0.0.1:9/1 bundle exec ruby /out/r5-sentry.rb 2>&1 | grep -vE "^No configuration|^Only using|warning:" | cut -c1-600 | tee "/tmp/sentry-$1.txt" | head -30
  echo "-- console"
  printf 'puts "users=#{User.count}"\nUser.new(first_name: "A")\nexit\n' | RAILS_ENVIRONMENT=production bin/rails console 2>&1 | grep -vE "^No configuration|^Only using" | cut -c1-300 | tee "/tmp/console-$1.txt" | head -14
}
one s3
git checkout -q $S2
one s2
git checkout -q "$S3"
echo "######## differences, 7.1.6 < > 7.2.4"
echo "== sentry"; diff /tmp/sentry-s2.txt /tmp/sentry-s3.txt | cut -c1-600 && echo identical
echo "== console"; diff /tmp/console-s2.txt /tmp/console-s3.txt | cut -c1-300 && echo identical
echo "==== end"
