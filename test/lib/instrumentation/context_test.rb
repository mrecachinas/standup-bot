require "test_helper"

module Instrumentation
  class ContextTest < ActiveSupport::TestCase
    test "with_context sets the context for the block and then restores it" do
      Instrumentation.set_context(request_id: "req-1", job_id: "outer")
      seen = nil

      Instrumentation.with_context(job_id: "inner", queue: "default") do
        Instrumentation.set_context(user_id: 7)
        seen = [ Instrumentation.context.dup, ActiveSupport::ExecutionContext.to_h ]
      end

      expected_inside = { request_id: "req-1", job_id: "inner", queue: "default", user_id: 7 }
      assert_equal expected_inside, seen.first
      assert_equal expected_inside, seen.second.slice(*expected_inside.keys)
      assert_equal({ request_id: "req-1", job_id: "outer" }, Instrumentation.context)
      assert_equal({ request_id: "req-1", job_id: "outer" }, ActiveSupport::ExecutionContext.to_h.slice(:request_id, :job_id))
      assert_nil ActiveSupport::ExecutionContext.to_h[:queue]
      assert_nil ActiveSupport::ExecutionContext.to_h[:user_id]
    end

    test "with_context restores the context when the block raises" do
      Instrumentation.set_context(job_id: "outer")

      assert_raises(ArgumentError) do
        Instrumentation.with_context(job_id: "inner") { raise ArgumentError }
      end

      assert_equal({ job_id: "outer" }, Instrumentation.context)
      assert_equal "outer", ActiveSupport::ExecutionContext.to_h[:job_id]
    end
  end
end
