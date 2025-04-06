module StandupFormatter
  # Format standup questions consistently
  def self.format_question(question_text, question_number, total_questions)
    "*Question #{question_number}/#{total_questions}:* #{question_text}\n\n_Type your answer or 'skip' to skip this question._"
  end
end
