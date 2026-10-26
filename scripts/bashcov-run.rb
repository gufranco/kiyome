# typed: strict
# frozen_string_literal: true

require "bashcov"

Bashcov.parse_options!(ARGV)

require "bashcov/runner"

runner = Bashcov::Runner.new(Bashcov.command)
status = runner.run
coverage = runner.result

require "simplecov"

SimpleCov.print_error_status = false
SimpleCov.start
SimpleCov.command_name(Bashcov.command_name)
SimpleCov.root(Bashcov.root_directory)
SimpleCov::ResultMerger.store_result(SimpleCov::Result.new(coverage))
SimpleCov.at_exit { :quiet }

exit(status.exitstatus)
