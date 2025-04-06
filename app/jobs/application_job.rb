class ApplicationJob < ActiveJob::Base
  # Track if retry attempts are needed
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Provide a memoized slack client for all job classes
  def self.slack_client
    SlackClient.instance
  end

  # Allow instance methods to access the class method
  delegate :slack_client, to: :class
end
