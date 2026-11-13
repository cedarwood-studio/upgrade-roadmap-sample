#!/bin/sh
# Review of S4.
#  1. the lock and the Gemfile against the S3 branch
#  2. a server-style boot with each optional feature switched on, one at a time and all together,
#     with eager loading, deprecations set to raise, routes drawn, and the 39 files the suite never loads
#  3. rake tasks load; the Rakefile and config.ru lines
#  4. the stage's specs on 8.0.5.2; the password reset spec without the option on both versions
#  5. db:migrate on an empty database, on both versions
# Usage: sh /out/s4-ops.sh
S3=upgrade/s3-rails-7-1-6-to-7-2-4
S4=$(git rev-parse --abbrev-ref HEAD)
echo "==== 1. lock against S3"
git diff -U0 $S3 HEAD -- Gemfile.lock | grep -E "^[+-]    [a-z]" | sort -k2 | tr -s ' ' | tr '\n' ';'
echo
echo "spec lines moved: $(git diff -U0 $S3 HEAD -- Gemfile.lock | grep -cE '^[+-]    [a-z]')"
echo "-- other lock lines (dependencies, platforms, bundler)"
git diff -U0 $S3 HEAD -- Gemfile.lock | grep -E "^[+-]" | grep -vE "^[+-]    [a-z]|^[+-]      |^(\+\+\+|---)" | tr -s ' ' | tr '\n' ';'
echo
git diff $S3 HEAD -- Gemfile | grep -E "^[+-][^+-]"
echo "-- application files changed"
git diff --stat $S3 HEAD -- app lib config db bin script public Rakefile config.ru | tail -3

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
    Rails.application.reload_routes!
    routes = Rails.application.routes.routes.size
    oidc_route = Rails.application.routes.routes.any? { |r| r.path.spec.to_s.include?("auth/oidc/callback") }
    helpers = Rails.application.routes.url_helpers.login_path
    files = File.read("/out/s4-never-loaded.txt").split
    missing = files.reject { |f| $LOADED_FEATURES.include?(Rails.root.join(f).to_s) }
    c = Postal::Config
    mw = Rails.application.middleware.map { |m| m.name.to_s.split("::").last }.join(",")
    puts "boot-ok rails=#{Rails.version} env=#{Rails.env} never-loaded=#{files.size - missing.size}/#{files.size} routes=#{routes} oidc-route=#{oidc_route} #{helpers} oidc=#{c.oidc.enabled?} local=#{c.oidc.local_authentication_enabled?} waiter=#{c.migration_waiter.enabled?} railslog=#{c.logging.rails_log_enabled?} sentry=#{!c.logging.sentry_dsn.nil?} rspamd=#{c.rspamd.enabled?} clamav=#{c.clamav.enabled?} spamd=#{c.spamd.enabled?} tls=#{c.smtp_server.tls_enabled?} regexp-timeout=#{Regexp.timeout.inspect} to_time=#{ActiveSupport.to_time_preserves_timezone.inspect} mw=#{Digest::MD5.hexdigest(mw)[0, 8]}/#{Rails.application.middleware.size}"
  ' 2>&1 | grep -vE "^No configuration|^Only using" | tail -2 | cut -c1-520)
  echo "$name: $out"
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
echo "-- the same boot line on 7.2.4, default and production, for the middleware stack and the two settings"
git checkout -q $S3
boot s3-default A=1
boot s3-production RAILS_ENVIRONMENT=production
git checkout -q "$S4"

echo "==== 3. rake and rack"
bundle exec rake -T 2>&1 | grep -vE "^No configuration|^Only using" | grep -cE "^rake "
bundle exec rake -T postal 2>&1 | grep -E "^rake " | cut -c1-80
RAILS_ENVIRONMENT=production bundle exec rake postal:update 2>&1 | grep -vE "^No configuration|^Only using" | tail -3 | cut -c1-200
echo "postal:update exit=$?"

echo "==== 4. specs"
RAILS_ENVIRONMENT=test bundle exec rake db:create db:schema:load > /dev/null 2>&1
bundle exec rspec spec/requests/password_reset_spec.rb spec/requests/vary_header_spec.rb spec/lib/postal/config_schema_spec.rb spec/lib/postal/message_parser_spec.rb spec/lib/migration_waiter_spec.rb spec/lib/secret_key_spec.rb 2>&1 | grep -E "examples,|Failure|rb:[0-9]+ #" | head -8
echo "-- request specs in three random orders"
for seed in 1 22 333; do bundle exec rspec spec/requests --seed $seed 2>&1 | grep -E "examples," ; done
echo "-- password reset spec on 8.0.5.2 with the option removed"
cp app/models/concerns/has_authentication.rb /tmp/has_authentication.rb
sed -i 's/, reset_token: false//' app/models/concerns/has_authentication.rb
grep -n has_secure_password app/models/concerns/has_authentication.rb
bundle exec rspec spec/requests/password_reset_spec.rb 2>&1 | grep -E "examples,|^rspec " | cut -c1-200 | head -10
echo "-- the same file, option removed, against the 7.2.4 lock"
cp Gemfile /tmp/Gemfile.s4; cp Gemfile.lock /tmp/Gemfile.lock.s4
git show $S3:Gemfile > Gemfile; git show $S3:Gemfile.lock > Gemfile.lock
bundle exec rspec spec/requests/password_reset_spec.rb spec/lib/postal/config_schema_spec.rb spec/lib/postal/message_parser_spec.rb 2>&1 | grep -E "examples,|^rspec " | cut -c1-200 | head -10
echo "-- vary spec against the 7.2.4 lock (expected to fail there)"
bundle exec rspec spec/requests/vary_header_spec.rb 2>&1 | grep -E "examples,|^rspec " | cut -c1-200 | head -4
cp /tmp/Gemfile.s4 Gemfile; cp /tmp/Gemfile.lock.s4 Gemfile.lock
cp /tmp/has_authentication.rb app/models/concerns/has_authentication.rb
git status --short | head -5

echo "==== 5. db:migrate on an empty database"
empty() {
  export MAIN_DB_DATABASE=postal_s4_review_empty
  bundle exec rake db:drop > /dev/null 2>&1
  bundle exec rake db:create > /tmp/empty-create.txt 2>&1
  bin/rails db:migrate > "/tmp/empty-$1.txt" 2>&1
  code=$?
  echo "$1: rails $(bundle exec ruby -e 'puts Gem.loaded_specs["rails"].version' 2>/dev/null) db:migrate exit=$code"
  grep -vE "^No configuration|^Only using" "/tmp/empty-$1.txt" | grep -E "Error|error|migrating|migrated|rake aborted|Caused|schema" | head -6 | cut -c1-220
  bundle exec ruby -e 'require "./config/environment"; c = ActiveRecord::Base.connection; puts "tables=#{c.tables.size} versions=#{(c.select_value("select count(*) from schema_migrations") rescue "none")}"' 2>&1 | tail -1
  git status --short | head -3
  git checkout -q -- db/schema.rb 2>/dev/null
  bundle exec rake db:drop > /dev/null 2>&1
  unset MAIN_DB_DATABASE
}
empty s4
git checkout -q $S3
empty s3
git checkout -q "$S4"
echo "==== end"
