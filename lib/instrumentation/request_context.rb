module Instrumentation
  # Sets the request ID as instrumentation context, so every log line and
  # error report in the request carries it. Sits right after
  # ActionDispatch::RequestId, inside the executor that clears it again.
  class RequestContext
    def initialize(app)
      @app = app
    end

    def call(env)
      Instrumentation.set_context(request_id: env["action_dispatch.request_id"])
      @app.call(env)
    end
  end
end
