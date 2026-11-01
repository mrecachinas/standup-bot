module StandupFormatter
  def self.format_question(question_text, question_number, total_questions, formatter: ChatPlatform::SlackFormatter)
    [
      "#{formatter.bold("Question #{question_number}/#{total_questions}:")} #{question_text}",
      "",
      formatter.italic("Type your answer or 'skip' to skip this question.")
    ].join("\n")
  end
end
