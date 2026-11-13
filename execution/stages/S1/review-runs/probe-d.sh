#!/bin/bash
# Review probe for S1: is the session cookie spec sensitive to the settings a
# later load_defaults step changes? The application is on load_defaults 7.0.
LOG=/out/probe-d.log
: > $LOG
run() { timeout -k 5 120 bundle exec rspec spec/requests/session_continuity_spec.rb 2>&1 | grep -E "examples?,|rspec \./" | tee -a $LOG; }
try() {
  echo "### $1" | tee -a $LOG
  sed -i "22a\\    $2" config/application.rb
  sed -n '22,23p' config/application.rb | tee -a $LOG
  run
  git checkout -q -- config
}
try "key generator digest back to SHA1" 'config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1'
try "authenticated cookie encryption off" 'config.action_dispatch.use_authenticated_cookie_encryption = false'
try "load_defaults 7.1 on top" 'config.load_defaults 7.1'
try "7.1 message metadata format" 'config.active_support.use_message_serializer_for_metadata = true'
