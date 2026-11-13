# frozen_string_literal: true

# Third review probe for S3. Run from the application root in the throwaway copy:
#   bundle exec ruby /out/r3-probe.rb
# Calls each framework call site the suite loads and never runs, or never loads,
# and the lines the changelog read pointed at. One line per check.

require "./config/environment"

def check(name)
  result = yield
  puts "OK    #{name}: #{result.inspect[0, 260]}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "FAIL  #{name}: #{e.class}: #{e.message.lines.first.to_s.strip[0, 260]}"
end

puts "rails #{Rails.version} env #{Rails.env} ruby #{RUBY_VERSION}"

check("deprecators set to raise") do
  Rails.application.deprecators.behavior = :raise
  Rails.application.deprecators.each.count
end

# lib/migration_waiter.rb:18, :47
check("migration_waiter.rb:18 pending migrations through the pool") do
  ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations.size
end
check("MigrationWaiter.wait, then console?/rake_task?/rails_command?") do
  require "migration_waiter"
  MigrationWaiter.wait
  [MigrationWaiter.console?, MigrationWaiter.rake_task?, MigrationWaiter.rails_command?, defined?(Rails::Console).inspect]
end
check("the old call is gone from the connection (why line 18 had to change)") do
  ActiveRecord::Base.connection.respond_to?(:migration_context)
end

# config/initializers/secret_key.rb:4
check("secret_key.rb: app key == credentials, no local secret file") do
  [Rails.application.secret_key_base == Rails.application.credentials.secret_key_base,
   File.exist?(Rails.root.join("tmp/local_secret.txt"))]
end

# lib/postal/message_db/database.rb:333, through the real slow-query path
check("database.rb:333 a slow message database query prints its EXPLAIN") do
  lines = []
  logger = Logger.new(nil)
  logger.define_singleton_method(:info) { |msg = nil, &blk| lines << (msg || blk&.call).to_s }
  logger.define_singleton_method(:debug) { |*| nil }
  db = Postal::MessageDB::Database.new(1, 1)
  db.define_singleton_method(:logger) { logger }
  db.query("SELECT SLEEP(0.08)")
  [lines.size, lines.grep(/EXPLAIN/).size, lines.last.to_s[0, 60]]
end

# app/lib/worker/process.rb:105,159,203,217,233 and lib/postal/config.rb:150
check("worker/process.rb:105 pool size") { ActiveRecord::Base.connection_pool.size }
check("worker/process.rb:159 with_connection in a thread hands the connection back") do
  before = ActiveRecord::Base.connection_pool.stat[:busy]
  value = Thread.new { ActiveRecord::Base.connection_pool.with_connection { WorkerRole.count } }.value
  [before, ActiveRecord::Base.connection_pool.stat[:busy], value]
end
check("worker/process.rb:217/203 acquire and release a role") do
  a = ActiveRecord::Base.connection_pool.with_connection { WorkerRole.acquire(:r3_probe) }
  r = ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:r3_probe) }
  [a, r]
end
check("Worker::Process: resize the pool, one work tick, one real tasks tick with every task due") do
  Prometheus::Client.define_singleton_method(:registry) { @r3 ||= Prometheus::Client::Registry.new }
  process = Worker::Process.new(thread_count: 8)
  process.send(:ensure_connection_pool_size_is_suitable)
  errors = []
  process.define_singleton_method(:capture_errors) do |&block|
    block.call
  rescue StandardError => e
    errors << "#{e.class}: #{e.message.lines.first.to_s.strip[0, 120]}"
  end
  worked = process.send(:work, 0)
  Worker::Process::TASKS.each do |task|
    ScheduledTask.where(name: task.to_s).first_or_create!(next_run_after: 1.minute.ago).update!(next_run_after: 1.minute.ago)
  end
  process.send(:run_tasks)
  ran = ScheduledTask.where("next_run_after > ?", Time.current).count
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:tasks) }
  [ActiveRecord::Base.connection_pool.size, worked, Worker::Process::TASKS.size, ran, errors]
end

# lib/tasks/postal.rake:31
check("postal.rake:31 Base.connection.table_exists? and select_all") do
  mysql = ActiveRecord::Base.connection
  [mysql.table_exists?("schema_migrations"), mysql.select_all("select * from schema_migrations").any?]
end

# app/models/route.rb:119-122 and app/controllers/ip_pools_controller.rb:36
check("route.rb:119-122 errors.each with a two-argument block, then RecordInvalid with no record") do
  u = User.new
  u.valid?
  seen = []
  u.errors.each { |a, message| seen << [a.class.name, message.inspect] }
  raised = begin
    raise ActiveRecord::RecordInvalid
  rescue ActiveRecord::RecordInvalid => e
    e.message
  end
  [seen.first, raised]
end
check("ip_pools_controller.rb:36 destroying a pool that is in use raises DeleteRestrictionError") do
  pool = IPPool.create!(name: "r3-probe-#{SecureRandom.hex(3)}")
  pool.ip_addresses.create!(ipv4: "10.9.#{rand(250)}.#{rand(250)}", hostname: "r3.example.com")
  begin
    pool.destroy
    :destroyed
  rescue ActiveRecord::DeleteRestrictionError => e
    e.class.name
  ensure
    pool.ip_addresses.destroy_all
    pool.reload.destroy
  end
end

# changelog entries that touch code this application calls
check("Astana zone and a time rendered in it") do
  z = ActiveSupport::TimeZone["Astana"]
  [z.tzinfo.name, z.formatted_offset, Time.use_zone("Astana") { Time.zone.at(0).to_fs(:long) }]
end
check("to_json through Active Support") { [JSON::VERSION, { "a" => [1, nil, Time.at(0).utc] }.to_json] }
check("number helpers with the values the views pass") do
  h = ApplicationController.helpers
  [h.number_to_percentage(9.99999900000001e-06, precision: 1), h.number_to_percentage(12.345, precision: 1),
   h.number_to_human_size(2048 * 1024 * 1024), h.number_to_human_size(BigDecimal("123456.0")), h.number_to_human_size(0)]
end
check("serialize coders, YAML round trip, loaded psych") do
  c = Credential.type_for_attribute(:options).coder
  w = WebhookRequest.type_for_attribute(:payload).coder
  dumped = c.dump({ "a" => 1 })
  [c.class.name, w.class.name, dumped, c.load(dumped), Psych::VERSION]
end
check("has_secure_password validations: false, blank password with a confirmation") do
  u = User.new(password: "   ", password_confirmation: "x")
  u.valid?
  u.errors.attribute_names
end
check("kaminari previous and next page tags (they call a removed deprecation API when given params)") do
  c = ApplicationController.new
  c.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/org/acme/servers/mail/queue?page=2"))
  c.response = ActionDispatch::Response.new
  view = c.view_context
  [Kaminari::Helpers::PrevPage.new(view, current_page: 2).page, Kaminari::Helpers::NextPage.new(view, current_page: 2).page]
end
check("dom_id override in record_key_for_dom.rb") do
  [ApplicationController.helpers.dom_id(User.new), ActionView::RecordIdentifier.instance_method(:dom_id).source_location&.first.to_s.split("/").last(2).join("/")]
end
check("sprockets-rails unknown asset fallback is off (its fallback path calls a removed deprecation API)") do
  ActionView::Base.respond_to?(:unknown_asset_fallback) ? ActionView::Base.unknown_asset_fallback : Rails.application.config.assets.unknown_asset_fallback
end
check("AppMailer delivery through the deliver.action_mailer subscriber in logging.rb") do
  ActionMailer::Base.delivery_method = :test
  user = User.new(first_name: "R", last_name: "Three", email_address: "r3@example.com", password_reset_token: "tok")
  AppMailer.password_reset(user, nil).deliver
  [ActionMailer::Base.deliveries.size, ActionMailer::Base.deliveries.last&.subject]
end
check("UserInvite#accept, the one transaction block") do
  invite = UserInvite.create!(email_address: "r3-probe-#{SecureRandom.hex(4)}@example.com")
  invite.accept(User.new)
  UserInvite.exists?(invite.id)
end
check("settings the hop could have moved") do
  cfg = Rails.application.config
  [cfg.action_dispatch.show_exceptions, cfg.loaded_config_version, ActiveRecord::Base.default_column_serializer.inspect,
   cfg.active_support.cache_format_version, cfg.action_dispatch.cookies_serializer, ActiveRecord::Base.attributes_for_inspect]
end
check("gems the hop moved or must not move") do
  %w[rails connection_pool minitest useragent psych stringio mail nokogiri rack json mutex_m].to_h { |g| [g, Gem.loaded_specs[g]&.version.to_s] }
end

# every file, eager loaded, deprecations raising
check("Rails.application.eager_load! and Zeitwerk::Loader.eager_load_all") do
  Rails.application.eager_load!
  Zeitwerk::Loader.eager_load_all
  [ApplicationController.descendants.size, ApplicationRecord.descendants.size]
end
check("the 39 files the suite never loads: their constants resolve") do
  files = %w[app/controllers/address_endpoints_controller.rb app/controllers/credentials_controller.rb app/controllers/help_controller.rb
             app/controllers/http_endpoints_controller.rb app/controllers/ip_addresses_controller.rb app/controllers/ip_pool_rules_controller.rb
             app/controllers/ip_pools_controller.rb app/controllers/organization_ip_pools_controller.rb app/controllers/organizations_controller.rb
             app/controllers/routes_controller.rb app/controllers/servers_controller.rb app/controllers/smtp_endpoints_controller.rb
             app/controllers/track_domains_controller.rb app/controllers/user_controller.rb app/controllers/users_controller.rb
             app/controllers/webhooks_controller.rb app/controllers/well_known_controller.rb app/lib/reply_separator.rb app/lib/smtp_server/server.rb
             app/lib/worker/process.rb app/models/incoming_message_prototype.rb app/models/scheduled_task.rb app/models/user_invite.rb
             app/scheduled_tasks/action_deletions_scheduled_task.rb app/scheduled_tasks/check_all_dns_scheduled_task.rb
             app/scheduled_tasks/cleanup_authie_sessions_scheduled_task.rb app/scheduled_tasks/expire_held_messages_scheduled_task.rb
             app/scheduled_tasks/process_message_retention_scheduled_task.rb app/scheduled_tasks/prune_suppression_lists_scheduled_task.rb
             app/scheduled_tasks/prune_webhook_requests_scheduled_task.rb app/scheduled_tasks/send_notifications_scheduled_task.rb
             app/util/health_server.rb app/util/user_creator.rb lib/postal/helm_config_exporter.rb lib/postal/message_inspectors/clamav.rb
             lib/postal/message_inspectors/rspamd.rb lib/postal/message_inspectors/spam_assassin.rb lib/postal/spam_check.rb
             lib/postal/yaml_config_exporter.rb]
  loaded = $LOADED_FEATURES
  missing = files.reject { |f| loaded.include?(Rails.root.join(f).to_s) }
  [files.size, missing]
end
