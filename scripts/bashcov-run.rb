# typed: strict
# frozen_string_literal: true

require "bashcov"

Bashcov.parse_options!(ARGV)

require "bashcov/runner"

Thread.report_on_exception = false
runner = Bashcov::Runner.new(Bashcov.command)
status = runner.run
coverage = File.open(File::NULL, "w") do |quiet|
  original_stderr = $stderr
  $stderr = quiet
  runner.result
ensure
  $stderr = original_stderr
end

require "simplecov"

SimpleCov.print_error_status = false
SimpleCov.start
SimpleCov.command_name(Bashcov.command_name)
SimpleCov.root(Bashcov.root_directory)
SimpleCov::ResultMerger.store_result(SimpleCov::Result.new(coverage))
SimpleCov.at_exit { :quiet }

exit(status.exitstatus)
