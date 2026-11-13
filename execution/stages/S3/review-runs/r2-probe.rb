# frozen_string_literal: true

# Second review probe for S3. Run from the application root in the throwaway copy:
#   bundle exec ruby /out/r2-probe.rb
# Calls each at-risk line found in the review and prints one line per check.

require "./config/environment"

def check(name)
  result = yield
  puts "OK    #{name}: #{result.inspect[0, 220]}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "FAIL  #{name}: #{e.class}: #{e.message.lines.first.to_s.strip[0, 220]}"
end

puts "rails #{Rails.version} env #{Rails.env} ruby #{RUBY_VERSION}"

# Any Rails deprecation raised from here on fails the check that triggers it.
check("deprecators set to raise") do
  Rails.application.deprecators.behavior = :raise
  Rails.application.deprecators.each.map { |d| d.gem_name }.size
end

# lib/migration_waiter.rb:18 and :47
check("migration_waiter.rb:18 as committed") do
  ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations.size
end
check("MigrationWaiter.wait") do
  require "migration_waiter"
  MigrationWaiter.wait
  :returned
end
check("migration_waiter.rb:47 console?/rake_task?/rails_command?") do
  [MigrationWaiter.console?, MigrationWaiter.rake_task?, MigrationWaiter.rails_command?]
end

# config/initializers/secret_key.rb
check("secret key: app == credentials, length, local_secret file, ENV set") do
  [Rails.application.secret_key_base == Rails.application.credentials.secret_key_base,
   Rails.application.secret_key_base.to_s.size,
   File.exist?(Rails.root.join("tmp/local_secret.txt")),
   ENV.key?("SECRET_KEY_BASE"),
   Postal::Config.rails.secret_key.to_s.size]
end

# lib/postal/message_db/database.rb:333
check("database.rb:333 ExplainPrettyPrinter#pp(result, time)") do
  fake = Struct.new(:columns, :rows).new(%w[id select_type], [[1, "SIMPLE"]])
  ActiveRecord::ConnectionAdapters::MySQL::ExplainPrettyPrinter.new.pp(fake, 0.12).split("\n").size
end

# app/lib/worker/process.rb:105,159,203,217,233 and lib/postal/config.rb:150
check("worker/process.rb:105 connection_pool.size") { ActiveRecord::Base.connection_pool.size }
check("worker/process.rb:159 with_connection + query") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.count }
end
check("worker/process.rb:217 WorkerRole.acquire in with_connection") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.acquire(:r2_probe) }
end
check("worker/process.rb:203 WorkerRole.release in with_connection") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:r2_probe) }
end
check("with_connection in a second thread returns the connection to the pool") do
  before = ActiveRecord::Base.connection_pool.stat[:busy]
  Thread.new { ActiveRecord::Base.connection_pool.with_connection { WorkerRole.count } }.join
  [before, ActiveRecord::Base.connection_pool.stat[:busy]]
end
check("config.rb:150 change_database_connection_pool_size(9)") do
  Postal.change_database_connection_pool_size(9)
  [ActiveRecord::Base.connection_pool.size, WorkerRole.count]
end
check("Worker::Process: pool check, one work tick, one tasks tick") do
  Prometheus::Client.define_singleton_method(:registry) { Prometheus::Client::Registry.new }
  process = Worker::Process.new(thread_count: 10)
  process.send(:ensure_connection_pool_size_is_suitable)
  process.define_singleton_method(:capture_errors) { |&block| block.call }
  process.define_singleton_method(:run_task) { |task| (@probe_tasks ||= []) << task }
  worked = process.send(:work, 0)
  process.send(:run_tasks)
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:tasks) }
  [ActiveRecord::Base.connection_pool.size, worked, process.instance_variable_get(:@probe_tasks).size]
end

# lib/tasks/postal.rake:31
check("postal.rake:31 Base.connection.table_exists? / select_all") do
  mysql = ActiveRecord::Base.connection
  [mysql.table_exists?("schema_migrations"), mysql.select_all("select * from schema_migrations").any?]
end

# app/models/route.rb:119-122, app/controllers/ip_pools_controller.rb:36
check("route.rb:122 raise ActiveRecord::RecordInvalid with no record") do
  begin
    raise ActiveRecord::RecordInvalid
  rescue ActiveRecord::RecordInvalid => e
    e.message
  end
end
check("ip_pools_controller.rb:36 DeleteRestrictionError is defined") do
  ActiveRecord::DeleteRestrictionError.ancestors.include?(ActiveRecord::ActiveRecordError)
end

# user_invite.rb:45, the one transaction block
check("UserInvite#accept transaction commits") do
  invite = UserInvite.create!(email_address: "r2-probe-#{SecureRandom.hex(4)}@example.com")
  invite.accept(User.new)
  UserInvite.exists?(invite.id)
end

# Changelog entries that touch code this application calls
check("Astana zone") { [ActiveSupport::TimeZone["Astana"].tzinfo.name, ActiveSupport::TimeZone["Astana"].formatted_offset] }
check("to_json through Active Support") { [JSON::VERSION, { "a" => [1, nil, Time.at(0).utc] }.to_json] }
check("number helpers with the value types the views pass") do
  h = ApplicationController.helpers
  [h.number_with_precision(1.0e-05, precision: 2), h.number_with_precision(12.3456, precision: 2),
   h.number_with_delimiter(1_234_567), h.number_to_human_size(2048 * 1024 * 1024),
   h.number_to_percentage(0.0, precision: 1), h.number_to_human_size(0)]
end
check("to_fs(:long) and humanize") { [Time.utc(2026, 1, 2, 3, 4).to_fs(:long), Date.new(2026, 1, 2).to_fs(:long), "hard_fail".humanize] }
check("serialize coders and YAML round trip") do
  c = Credential.type_for_attribute(:options).coder
  w = WebhookRequest.type_for_attribute(:payload).coder
  dumped = c.dump({ "a" => 1 })
  [c.class.name, w.class.name, dumped, c.load(dumped), Credential.new.options, Psych::VERSION]
end
check("has_secure_password with validations: false") do
  u = User.new(password: "   ", password_confirmation: "x")
  u.valid?
  u.errors.attribute_names
end
check("show_exceptions, load_defaults, default_column_serializer") do
  [Rails.application.config.action_dispatch.show_exceptions, Rails.application.config.loaded_config_version,
   ActiveRecord::Base.default_column_serializer.inspect]
end
check("gems the hop moved") do
  %w[connection_pool minitest useragent psych stringio mail nokogiri rack json].to_h { |g| [g, Gem.loaded_specs[g]&.version.to_s] }
end
check("the message database pool uses connection_pool 2.x") do
  [ConnectionPool::VERSION, Postal::MessageDB::ConnectionPool.instance_methods(false).sort.first(6)]
end

# every file, eager loaded, with deprecations raising
check("Rails.application.eager_load!") do
  Rails.application.eager_load!
  :loaded
end
check("Zeitwerk::Loader.eager_load_all") do
  Zeitwerk::Loader.eager_load_all
  :loaded
end
check("files the suite never loads are now loaded") do
  names = %w[Worker::Process SMTPServer::Server ReplySeparator IncomingMessagePrototype ScheduledTask UserInvite
             HealthServer UserCreator Postal::HelmConfigExporter Postal::YamlConfigExporter Postal::SpamCheck
             Postal::MessageInspectors::Clamav Postal::MessageInspectors::Rspamd Postal::MessageInspectors::SpamAssassin
             ActionDeletionsScheduledTask CheckAllDNSScheduledTask CleanupAuthieSessionsScheduledTask
             ExpireHeldMessagesScheduledTask ProcessMessageRetentionScheduledTask PruneSuppressionListsScheduledTask
             PruneWebhookRequestsScheduledTask SendNotificationsScheduledTask]
  missing = names.reject { |n| Object.const_defined?(n) }
  [names.size, missing, ApplicationController.descendants.size, ApplicationRecord.descendants.size]
end
check("routes build and every route's controller resolves") do
  routes = Rails.application.routes.routes.map { |r| r.defaults[:controller] }.compact.uniq
  missing = routes.reject { |c| "#{c.camelize}Controller".safe_constantize || c.start_with?("rails/") }
  [routes.size, missing]
end
check("dynamic_form helpers present") do
  [ActionView::Base.instance_methods.include?(:error_messages_for), ActionView::Helpers::FormBuilder.instance_methods.include?(:error_messages)]
end
