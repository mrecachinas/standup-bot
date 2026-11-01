# A chat platform's app status for the console: which credentials are set
# (never their values), whether the app is installed, and the live API check.
class ChatStatusSerializer
  def initialize(status, connection_result: nil, platform: nil)
    @status = status.to_h.deep_symbolize_keys
    @connection_result = connection_result
    @platform = (platform || @status[:platform]).to_s
  end

  def as_json(*)
    configured = @status[:configured] || false
    {
      platform: @platform,
      label: label,
      title: "#{label} app status",
      status: @status[:status],
      configured: configured,
      status_label: configured ? "Connected" : "Needs setup",
      status_tone: configured ? "success" : "warning",
      installation: @status[:installation],
      credentials: credentials,
      health: @status[:health],
      connection: ChatResultSerializer.new(@connection_result).as_json
    }
  end

  private

  def label
    @status[:label].presence || ChatPlatform.for(@platform.presence || ChatPlatform::DEFAULT).label
  end

  def credentials
    @status.fetch(:credentials, {}).map do |key, credential|
      {
        key: key.to_s,
        label: credential[:label],
        configured: credential[:configured] || false,
        required: credential[:required] || false,
        message: credential[:message],
        state_label: credential[:configured] ? "Configured" : "Missing",
        tone: credential[:configured] ? "success" : (credential[:required] ? "warning" : nil)
      }
    end
  end
end
