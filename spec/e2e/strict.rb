# frozen_string_literal: true

# Loaded only by the live e2e workflow (`rspec --require ./spec/e2e/strict`).
# rspec exits 0 when the e2e spec skips (credentials missing) or when no
# example runs. In the e2e run either means the check did not happen, so fail
# it.
RSpec.configure do |config|
  config.fail_if_no_examples = true

  config.after(:suite) do
    skipped = RSpec.world.all_examples.count { |e| e.execution_result.status == :pending }
    raise "#{skipped} e2e example(s) pending or skipped" if skipped.positive?
  end
end
