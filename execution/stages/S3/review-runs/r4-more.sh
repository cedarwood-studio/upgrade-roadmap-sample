#!/bin/sh
# Fourth review, S3. On both versions, in production unless said otherwise:
#  1. the 500 page for GET and HEAD (second try, see r4-500.rb)
#  2. the versioned migrations, undone and applied again in a scratch database
#  3. on 7.2.4 only: a boot with every optional feature we can switch by
#     environment, eager loading on, and the 39 files the suite never loads
# Usage: sh /out/r4-more.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
S3=$(git rev-parse --abbrev-ref HEAD)

one() {
  v=$1
  echo "######## $v: $(bundle exec ruby -e 'puts Gem.loaded_specs["rails"].version' 2>/dev/null)"
  echo "==== 1. the 500 page"
  bundle exec ruby /out/r4-500.rb 2>/dev/null | grep -E "^(GET|HEAD)" | tee "/tmp/500-$v.txt"
  echo "==== 2. versioned migrations: schema load, then down and up again one at a time, newest first"
  export MAIN_DB_DATABASE="postal_r4m_$v"
  RAILS_ENVIRONMENT=test bundle exec rake db:drop db:create db:schema:load > /dev/null 2>&1
  n=0
  for f in $(ls db/migrate | sort -r); do
    grep -q "ActiveRecord::Migration\[" "db/migrate/$f" || continue
    ver=${f%%_*}
    if RAILS_ENVIRONMENT=test bundle exec rake db:migrate:redo VERSION="$ver" > "/tmp/redo-$v-$ver.txt" 2>&1; then
      n=$((n + 1))
    else
      echo "redo $f: FAILED: $(grep -m1 -iE 'error|irreversible|abort' /tmp/redo-$v-$ver.txt | cut -c1-160)"
    fi
  done
  echo "redone cleanly: $n"
  cp db/schema.rb "/tmp/schema-$v.rb"
  git diff -U0 -- db/schema.rb | grep -E "^[+-][^+-]" | head -12 | cut -c1-200
  git checkout -q -- db/schema.rb
  unset MAIN_DB_DATABASE
}

one s3
echo "==== 3. every flag on, production, eager load, the never-loaded files"
RAILS_ENVIRONMENT=production LOGGING_SENTRY_DSN=http://k@127.0.0.1:9/1 LOGGING_RAILS_LOG_ENABLED=true OIDC_ENABLED=true OIDC_LOCAL_AUTHENTICATION_ENABLED=false \
  OIDC_ISSUER=http://127.0.0.1:9 OIDC_IDENTIFIER=x OIDC_SECRET=y OIDC_DISCOVERY=false OIDC_AUTHORIZATION_ENDPOINT=http://127.0.0.1:9/a \
  OIDC_TOKEN_ENDPOINT=http://127.0.0.1:9/t OIDC_USERINFO_ENDPOINT=http://127.0.0.1:9/u OIDC_JWKS_URI=http://127.0.0.1:9/j \
  MIGRATION_WAITER_ENABLED=true RSPAMD_ENABLED=true CLAMAV_ENABLED=true SPAMD_ENABLED=true SMTP_SERVER_TLS_ENABLED=false LOGGING_HIGHLIGHTING_ENABLED=true \
  bundle exec ruby -e '
    require "./config/environment"
    Rails.application.deprecators.behavior = :raise
    Rails.application.eager_load!
    Zeitwerk::Loader.eager_load_all
    c = Postal::Config
    puts "boot-ok rails=#{Rails.version} env=#{Rails.env} eager=#{Rails.application.config.eager_load}"
    puts "flags: oidc=#{c.oidc.enabled?} local_auth=#{c.oidc.local_authentication_enabled?} waiter=#{c.migration_waiter.enabled?} rails_log=#{c.logging.rails_log_enabled?} sentry=#{c.logging.sentry_dsn.inspect[0, 12]} rspamd=#{c.rspamd.enabled?} clamav=#{c.clamav.enabled?} spamd=#{c.spamd.enabled?} static=#{Rails.application.config.public_file_server.enabled}"
    files = File.read("/out/r4-never-loaded.txt").split
    missing = files.reject { |f| $LOADED_FEATURES.include?(Rails.root.join(f).to_s) }
    puts "never-loaded files now loaded: #{files.size - missing.size} of #{files.size}; missing: #{missing.inspect}"
    puts "omniauth in stack: #{Rails.application.middleware.map { |m| m.name.to_s }.grep(/OmniAuth|Sentry/).inspect}"
    puts "oidc route: #{Rails.application.routes.routes.any? { |r| r.path.spec.to_s.include?("auth/oidc/callback") }}"
    puts "inspectors: #{Postal::MessageInspector.inspectors.map { |i| i.class.name }.inspect}"
  ' 2>&1 | grep -vE "^No configuration|^Only using" | cut -c1-400 | tail -12

git checkout -q upgrade/s2-remove-the-annotate-blocker
one s2
git checkout -q "$S3"
echo "######## differences, 7.1.6 < > 7.2.4"
echo "== 500 page"; diff /tmp/500-s2.txt /tmp/500-s3.txt && echo identical
echo "== schema after redoing the versioned migrations"; diff /tmp/schema-s2.rb /tmp/schema-s3.rb && echo identical
echo "==== end"
