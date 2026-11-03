module StandupFormatter
  def self.format_question(question_text, formatter: ChatPlatform::SlackFormatter)
    formatter.bold(question_text)
  end
end
