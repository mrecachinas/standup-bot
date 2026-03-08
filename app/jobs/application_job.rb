class ApplicationJob < ActiveJob::Base
  # Retry only transient/network errors, not permanent failures
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: :exponentially_longer, attempts: 5
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
           wait: :exponentially_longer, attempts: 3

  # Discard jobs where the record no longer exists
  discard_on ActiveRecord::RecordNotFound

  # Provide a memoized slack client for all job classes
  def self.slack_client
    SlackClient.instance
  end

  # Allow instance methods to access the class method
  delegate :slack_client, to: :class
end
