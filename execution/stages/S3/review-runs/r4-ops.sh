#!/bin/sh
# Fourth review, S3. Operator paths on both versions, in production:
#  1. the 500 page for GET and HEAD
#  2. the migration waiter in a real worker process, with a migration pending and with none
#  3. the route table, the rake task list, the console, the runner, the config exporters
#  4. a database built from nothing by running every migration, compared with db/schema.rb
# Usage: sh /out/r4-ops.sh
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

  echo "==== 2. migration waiter in script/worker.rb, one migration pending (expect two log lines and exit 1)"
  printf 'class R4Pending < ActiveRecord::Migration[7.0]\n  def change; end\nend\n' > db/migrate/20991231000000_r4_pending.rb
  MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1 LOGGING_ENABLED=true \
    timeout -s TERM -k 5 40 bundle exec ruby script/worker.rb > "/tmp/wait-pending-$v.txt" 2>&1
  echo "exit=$?"
  grep -E "migration|Error|error" "/tmp/wait-pending-$v.txt" | sed -E 's/^[0-9-]+ [0-9:]+ \+0000 //' | cut -c1-220 | head -6
  rm -f db/migrate/20991231000000_r4_pending.rb
  echo "==== 2b. none pending (expect 'no pending migrations, continuing', then the worker runs until we stop it)"
  MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1 LOGGING_ENABLED=true \
    timeout -s TERM -k 5 14 bundle exec ruby script/worker.rb > "/tmp/wait-none-$v.txt" 2>&1
  echo "exit=$?"
  grep -E "migration|starting|stopp|Error|error" "/tmp/wait-none-$v.txt" | sed -E 's/^[0-9-]+ [0-9:]+ \+0000 //' | cut -c1-160 | head -8
  echo "==== 2c. the same in the web server (puma loads config.ru), none pending"
  MIGRATION_WAITER_ENABLED=true LOGGING_ENABLED=true PORT=5056 timeout -s TERM -k 5 12 bundle exec puma -C config/puma.rb > "/tmp/wait-puma-$v.txt" 2>&1
  echo "exit=$?"
  grep -E "migration|Listening|Error|error" "/tmp/wait-puma-$v.txt" | sed -E 's/^[0-9-]+ [0-9:]+ \+0000 //' | cut -c1-160 | head -5

  echo "==== 3. routes, tasks, console, runner, exporters"
  bin/rails routes > "/tmp/routes-$v.txt" 2>/dev/null; echo "routes: exit=$? lines=$(wc -l < /tmp/routes-$v.txt)"
  bundle exec rake -T 2>/dev/null | sed 's/ *#.*//' > "/tmp/tasks-$v.txt"; echo "rake -T: $(wc -l < /tmp/tasks-$v.txt) tasks"
  bundle exec rake -AT 2>/dev/null | sed 's/ *#.*//' > "/tmp/alltasks-$v.txt"; echo "rake -AT: $(wc -l < /tmp/alltasks-$v.txt) tasks"
  echo 'puts "console-ok users=#{User.count} console?=#{MigrationWaiter.console?}"' | MIGRATION_WAITER_ENABLED=true bin/rails console 2>&1 | grep -E "console-ok|Error" | head -3
  bin/rails runner 'puts "runner-ok #{Rails.version} #{Rails.env} #{Organization.count}"' 2>&1 | grep -E "runner-ok|Error" | head -3
  bundle exec rake postal:generate_helm_env_vars 2>/dev/null | md5sum | sed 's/^/helm exporter md5: /'
  bundle exec rake postal:generate_config_docs > /dev/null 2>&1; echo "config docs exit=$? changed files: $(git status --short doc | wc -l)"
  git checkout -q -- doc 2>/dev/null
  bundle exec ruby script/version.rb 2>&1 | tail -1 | cut -c1-80

  echo "==== 4. every migration from nothing, in a new database, then the schema it leaves"
  MAIN_DB_DATABASE="postal_r4_$v" RAILS_ENVIRONMENT=test bundle exec rake db:drop db:create > /dev/null 2>&1
  MAIN_DB_DATABASE="postal_r4_$v" RAILS_ENVIRONMENT=test bundle exec rake db:migrate > "/tmp/migrate-$v.txt" 2>&1
  echo "db:migrate exit=$? migrations run: $(grep -c ': migrated' /tmp/migrate-$v.txt) errors: $(grep -ciE 'error|abort' /tmp/migrate-$v.txt)"
  grep -iE "error|abort" "/tmp/migrate-$v.txt" | head -3 | cut -c1-200
  cp db/schema.rb "/tmp/schema-$v.rb"
  echo "db/schema.rb after migrating, against the committed file:"
  git diff --stat -- db/schema.rb | tail -1
  git diff -U0 -- db/schema.rb | grep -E "^[+-][^+-]" | head -12 | cut -c1-200
  git checkout -q -- db/schema.rb
  MAIN_DB_DATABASE="postal_r4_$v" RAILS_ENVIRONMENT=test bundle exec rake postal:update 2>&1 | grep -E "already loaded|No schema|Error" | head -2
}

one s3
git checkout -q upgrade/s2-remove-the-annotate-blocker
one s2
git checkout -q "$S3"

echo "######## differences, 7.1.6 < > 7.2.4"
echo "== 500 page"; diff /tmp/500-s2.txt /tmp/500-s3.txt && echo identical
echo "== routes"; diff /tmp/routes-s2.txt /tmp/routes-s3.txt > /tmp/routes.diff && echo identical || { wc -l < /tmp/routes.diff; head -12 /tmp/routes.diff | cut -c1-200; }
echo "== rake -T"; diff /tmp/tasks-s2.txt /tmp/tasks-s3.txt && echo identical
echo "== rake -AT"; diff /tmp/alltasks-s2.txt /tmp/alltasks-s3.txt && echo identical
echo "== schema after migrating from nothing"; diff /tmp/schema-s2.rb /tmp/schema-s3.rb && echo identical
echo "==== end"
