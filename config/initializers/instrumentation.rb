# Subscribes the built-in log and metrics backends to Rails.error and
# Rails.event. See lib/instrumentation.rb, and docs/architecture.md#observability
# for plugging in another backend such as an error tracker.
Instrumentation.install!
