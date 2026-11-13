#!/bin/bash
# Review probe for S1: change one application line at a time in the throwaway
# copy and see whether the tests S1 added notice. Nothing here is kept.
run() { bundle exec rspec "$@" 2>&1 | grep -E "examples,|rspec \./|Failure|Error" | head -12; }
reset() { git checkout -q -- app lib config; }

echo "### A: worker job run and task run call a constant that does not exist (stands in for Benchmark going away)"
sed -i '164s/Benchmark.realtime/NoSuchBenchmark.realtime/; 256s/Benchmark.realtime/NoSuchBenchmark.realtime/' app/lib/worker/process.rb
sed -n '164p;256p' app/lib/worker/process.rb
run spec/lib/worker/process_spec.rb spec/scheduled_tasks
reset

echo "### B: migration waiter calls a method that does not exist"
sed -i '18s/migration_context/no_such_migration_context/' lib/migration_waiter.rb
sed -n '18p' lib/migration_waiter.rb
run spec/lib/worker/process_spec.rb spec/lib/smtp_server/server_spec.rb spec/requests/session_continuity_spec.rb
echo "boot with the waiter on:"
MIGRATION_WAITER_ENABLED=true MIGRATION_WAITER_ATTEMPTS=2 MIGRATION_WAITER_SLEEP_TIME=1 bundle exec ruby -e 'require "./config/environment"; puts "BOOT OK"' 2>&1 | tail -3
reset

echo "### C: YAML columns switched to JSON"
sed -i 's/serialize :options, type: Hash/serialize :options, type: Hash, coder: JSON/' app/models/credential.rb
sed -i 's/serialize :payload, type: Hash/serialize :payload, type: Hash, coder: JSON/' app/models/webhook_request.rb
run spec/models/credential_spec.rb spec/models/webhook_request_spec.rb
reset

echo "### D: key generator digest switched to SHA256 (what a newer load_defaults does)"
echo 'Rails.application.config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA256' > config/initializers/zz_probe.rb
run spec/requests/session_continuity_spec.rb
rm config/initializers/zz_probe.rb

echo "### D2: cookies serializer switched to marshal"
cat config/initializers/cookies_serializer.rb | grep -v '^#'
sed -i 's/cookies_serializer = :[a-z_]*/cookies_serializer = :marshal/' config/initializers/cookies_serializer.rb
run spec/requests/session_continuity_spec.rb
reset

echo "### E: SMTP server no longer sets the output record separator"
sed -i '46d' app/lib/smtp_server/server.rb
run spec/lib/smtp_server/server_spec.rb
reset

echo "### F: explain path and tracked link rewrite broken"
sed -i '333s/ExplainPrettyPrinter/NoSuchPrinter/' lib/postal/message_db/database.rb
sed -i 's|"href=.#{domain}/#{@message.server.token}/#{token}."|raise "probe"|' lib/postal/message_parser.rb
git diff --stat
run spec/lib/postal/message_parser_spec.rb spec/lib/postal/message_db/database_spec.rb
reset
