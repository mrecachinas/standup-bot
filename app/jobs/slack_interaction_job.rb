# Handles a Slack button or menu click that arrived over Socket Mode, then
# posts the reply to the click's response_url (Socket Mode ignores replies in
# the ack). The dispatcher queues it before acking, so a click isn't lost if
# the process stops right after acking.
class SlackInteractionJob < ApplicationJob
  RESPONSE_URL_HOST = /\A(?:[a-z0-9-]+\.)*slack\.com\z/

  queue_as :inbound
  limits_concurrency key: ->(payload) { ApplicationJob.inbound_concurrency_key(:slack, payload.dig("user", "id")) },
    group: INBOUND_CONCURRENCY_GROUP, duration: INBOUND_CONCURRENCY_DURATION

  def perform(payload)
    response = SlackInbound.interaction(payload)
    return unless response

    url = payload["response_url"]
    unless trusted_response_url?(url)
      Rails.logger.warn "Slack interaction has no usable response_url; dropping reply"
      return
    end

    http.post(url, response.body.to_json, "Content-Type" => "application/json")
  rescue Faraday::Error => error
    # The click was handled; only the reply didn't make it. Retrying would
    # handle the click again, so just note it.
    Rails.logger.warn "Couldn't post Slack interaction reply: #{error.class}"
  end

  private

  def http
    Faraday.new(request: { timeout: 10, open_timeout: 5 })
  end

  def trusted_response_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && RESPONSE_URL_HOST.match?(uri.host.to_s)
  rescue URI::InvalidURIError
    false
  end
end
