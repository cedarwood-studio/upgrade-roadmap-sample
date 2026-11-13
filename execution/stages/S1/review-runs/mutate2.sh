#!/bin/bash
# Review probe for S1: change one application line at a time in the throwaway
# copy and see whether the tests S1 added notice. Nothing here is kept.
# Each run has a time limit; "TIMED OUT" means the spec hung instead of failing.
LOG=/out/mutate2.log
: > $LOG
say() { echo "$@" | tee -a $LOG; }
run() {
  timeout -k 5 "${LIMIT:-120}" bundle exec rspec "$@" > /tmp/run.out 2>&1
  code=$?
  [ $code -ge 124 ] && say "TIMED OUT after ${LIMIT:-120}s (exit $code)"
  grep -E "examples?,|rspec \./|Error|timed out" /tmp/run.out | head -10 | tee -a $LOG
  pkill -f script/smtp_server.rb; pkill -f script/worker.rb
}
reset() { git checkout -q -- app lib config; }

say "### A: worker job run and task run call a constant that does not exist (stands in for Benchmark going away)"
sed -i '164s/Benchmark.realtime/NoSuchBenchmark.realtime/; 256s/Benchmark.realtime/NoSuchBenchmark.realtime/' app/lib/worker/process.rb
sed -n '164p;256p' app/lib/worker/process.rb | tee -a $LOG
run spec/lib/worker/process_spec.rb spec/scheduled_tasks
reset

say "### B: migration waiter calls a method that does not exist"
sed -i '18s/migration_context/no_such_migration_context/' lib/migration_waiter.rb
run spec/lib/worker/process_spec.rb spec/lib/smtp_server/server_spec.rb spec/requests/session_continuity_spec.rb spec/scheduled_tasks spec/models
say "boot with the waiter on, mutated:"
MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1 timeout 60 bundle exec ruby -e 'require "./config/environment"; puts "BOOT OK"' 2>&1 | grep -E "BOOT OK|Error" | head -2 | tee -a $LOG
reset
say "boot with the waiter on, unmodified (schema loaded by the spec run above): "
MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1 timeout 60 bundle exec ruby -e 'require "./config/environment"; puts "BOOT OK"' 2>&1 | grep -E "BOOT OK|Error" | head -2 | tee -a $LOG
say "exit ${PIPESTATUS[0]}"

say "### C: YAML columns switched to JSON"
sed -i 's/serialize :options, type: Hash/serialize :options, type: Hash, coder: JSON/' app/models/credential.rb
sed -i 's/serialize :payload, type: Hash/serialize :payload, type: Hash, coder: JSON/' app/models/webhook_request.rb
run spec/models/credential_spec.rb spec/models/webhook_request_spec.rb
reset

say "### D: key generator digest switched to SHA256"
echo 'Rails.application.config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA256' > config/initializers/zz_probe.rb
run spec/requests/session_continuity_spec.rb
rm config/initializers/zz_probe.rb

say "### D2: cookies serializer switched to marshal"
grep -v '^#' config/initializers/cookies_serializer.rb | tee -a $LOG
sed -i 's/cookies_serializer = :[a-z_]*/cookies_serializer = :marshal/' config/initializers/cookies_serializer.rb
run spec/requests/session_continuity_spec.rb
reset

say "### F: explain path and tracked link rewrite broken"
sed -i '333s/ExplainPrettyPrinter/NoSuchPrinter/' lib/postal/message_db/database.rb
sed -i "s|\"href='#{domain}/#{@message.server.token}/#{token}'\"|raise \"probe\"|" lib/postal/message_parser.rb
git diff --stat | tee -a $LOG
run spec/lib/postal/message_parser_spec.rb spec/lib/postal/message_db/database_spec.rb
reset

say "### E: SMTP server no longer sets the output record separator"
sed -i '46d' app/lib/smtp_server/server.rb
LIMIT=100 run spec/lib/smtp_server/server_spec.rb
reset
say "### done"
