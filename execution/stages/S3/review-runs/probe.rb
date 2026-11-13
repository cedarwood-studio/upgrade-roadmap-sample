# frozen_string_literal: true

# Review probe for S3. Run from the application root in the throwaway copy:
#   bundle exec ruby /out/probe.rb
# Calls each at-risk line found in the review and prints one line per check.

require "./config/environment"

def check(name)
  result = yield
  puts "OK    #{name}: #{result.inspect[0, 200]}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "FAIL  #{name}: #{e.class}: #{e.message.lines.first.to_s.strip[0, 200]}"
end

puts "rails #{Rails.version} env #{Rails.env} ruby #{RUBY_VERSION}"

# lib/migration_waiter.rb:18, as written
check("migration_waiter.rb:18 as written (Base.connection.migration_context)") do
  ActiveRecord::Base.connection.migration_context.open.pending_migrations.size
end
check("migration_waiter.rb:18 through the pool (Base.connection_pool.migration_context)") do
  ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations.size
end
check("MigrationWaiter.wait") do
  require "migration_waiter"
  MigrationWaiter.wait
  :returned
end
check("migration_waiter.rb:47 Rails.const_defined?(Console)") { Rails.const_defined?("Console") }

# lib/postal/message_db/database.rb:333
check("database.rb:333 MySQL::ExplainPrettyPrinter#pp(result, time)") do
  fake = Struct.new(:columns, :rows).new(%w[id select_type], [[1, "SIMPLE"]])
  ActiveRecord::ConnectionAdapters::MySQL::ExplainPrettyPrinter.new.pp(fake, 0.12).lines.size
end

# config/initializers/secret_key.rb
check("secret_key_base comes from credentials") do
  [Rails.application.secret_key_base == Rails.application.credentials.secret_key_base,
   Rails.application.secret_key_base.to_s.size,
   File.exist?(Rails.root.join("tmp/local_secret.txt"))]
end

# app/lib/worker/process.rb:105,159,203,217,233 and lib/postal/config.rb:150
check("worker/process.rb:105 connection_pool.size") { ActiveRecord::Base.connection_pool.size }
check("worker/process.rb:159 connection_pool.with_connection + query") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.count }
end
check("worker/process.rb:217 WorkerRole.acquire inside with_connection") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.acquire(:review_probe) }
end
check("worker/process.rb:204 WorkerRole.release inside with_connection") do
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:review_probe) }
end
check("config.rb:150 change_database_connection_pool_size") do
  Postal.change_database_connection_pool_size(9)
  ActiveRecord::Base.connection_pool.size
end
check("Worker::Process.new + ensure_connection_pool_size_is_suitable") do
  # each Worker::Process registers its metrics, so each one gets a fresh registry
  Prometheus::Client.define_singleton_method(:registry) { Prometheus::Client::Registry.new }
  process = Worker::Process.new(thread_count: 10)
  process.send(:ensure_connection_pool_size_is_suitable)
  ActiveRecord::Base.connection_pool.size
end
check("Worker::Process#work one tick") do
  process = Worker::Process.new(thread_count: 1)
  process.define_singleton_method(:capture_errors) { |&block| block.call }
  process.send(:work, 0)
end
check("Worker::Process#run_tasks one tick") do
  process = Worker::Process.new(thread_count: 1)
  process.define_singleton_method(:capture_errors) { |&block| block.call }
  process.define_singleton_method(:run_task) { |task| (@probe_tasks ||= []) << task }
  process.send(:run_tasks)
  ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:tasks) }
end

# lib/tasks/postal.rake:31
check("postal.rake:31 Base.connection.table_exists? / select_all") do
  mysql = ActiveRecord::Base.connection
  [mysql.table_exists?("schema_migrations"), mysql.select_all("select * from schema_migrations").any?]
end

# app/models/route.rb:122, app/controllers/ip_pools_controller.rb:36
check("route.rb:122 raise ActiveRecord::RecordInvalid with no record") do
  begin
    raise ActiveRecord::RecordInvalid
  rescue ActiveRecord::RecordInvalid => e
    e.class.name
  end
end
check("ip_pools_controller.rb:36 ActiveRecord::DeleteRestrictionError") do
  ActiveRecord::DeleteRestrictionError.ancestors.include?(ActiveRecord::ActiveRecordError)
end

# json, Astana, serialize
check("to_json through Active Support") { [JSON::VERSION, { "a" => [1, nil, Time.at(0).utc] }.to_json] }
check("TimeZone[Astana]") { [ActiveSupport::TimeZone["Astana"].tzinfo.name, ActiveSupport::TimeZone["Astana"].formatted_offset] }
check("serialize coder on Credential#options and WebhookRequest#payload") do
  [Credential.type_for_attribute(:options).coder.class.name, WebhookRequest.type_for_attribute(:payload).coder.class.name,
   Credential.new.options, ActiveRecord::Base.default_column_serializer.inspect]
end
check("show_exceptions") { Rails.application.config.action_dispatch.show_exceptions }
check("load_defaults") { Rails.application.config.loaded_config_version }

# every file, eager loaded
check("Rails.application.eager_load!") do
  Rails.application.eager_load!
  :loaded
end
check("Zeitwerk::Loader.eager_load_all") do
  Zeitwerk::Loader.eager_load_all
  :loaded
end
check("all controllers and models resolve") do
  [ApplicationController.descendants.size, ApplicationRecord.descendants.size]
end
check("dynamic_form helpers present") do
  [ActionView::Base.instance_methods.include?(:error_messages_for), ActionView::Helpers::FormBuilder.instance_methods.include?(:error_messages)]
end
