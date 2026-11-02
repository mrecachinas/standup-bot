# The member's recent check-ins, optionally for one standup.
class MemberResponsesSerializer
  def self.status_label(response)
    response.status == "completed" ? "Answered" : response.status.titleize
  end

  def initialize(member, standups:, standup:, responses:, limit:)
    @member = member
    @standups = standups
    @standup = standup
    @responses = responses
    @limit = limit
  end

  def as_json(*)
    {
      member: MemberProfileSerializer.new(@member).as_json,
      standups: @standups.map { |standup| { id: standup.id, name: standup.name } },
      standup: @standup && { id: @standup.id, name: @standup.name },
      responses: @responses.map { |response| response_json(response) },
      limit: @limit,
      limited: @responses.size >= @limit
    }
  end

  private

  def response_json(response)
    date = response.standup_date
    label = self.class.status_label(response)
    {
      id: response.id,
      standup_id: response.standup_id,
      standup_name: response.standup.name,
      date: date.iso8601,
      date_label: date.strftime("%A, %B %-d, %Y"),
      status: response.status,
      status_label: label,
      status_tone: UiFormat.status_tone(label),
      answers: Array(response.answers).map do |answer|
        { question: answer["question"] || answer[:question], answer: (answer["answer"] || answer[:answer]).presence }
      end,
      created_at: response.created_at&.iso8601,
      updated_at: response.updated_at&.iso8601
    }
  end
end
