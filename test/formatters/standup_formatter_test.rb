require "test_helper"

class StandupFormatterTest < ActiveSupport::TestCase
  test "format_question formats the question correctly" do
    question_text = "What did you work on yesterday?"
    question_number = 1
    total_questions = 3

    formatted_question = StandupFormatter.format_question(question_text, question_number, total_questions)

    expected = "*Question 1/3:* What did you work on yesterday?\n\n_Type your answer or 'skip' to skip this question._"
    assert_equal expected, formatted_question
  end

  test "format_question handles different question numbers" do
    question_text = "Any blockers?"
    question_number = 3
    total_questions = 3

    formatted_question = StandupFormatter.format_question(question_text, question_number, total_questions)

    expected = "*Question 3/3:* Any blockers?\n\n_Type your answer or 'skip' to skip this question._"
    assert_equal expected, formatted_question
  end

  test "format_question handles special characters" do
    question_text = "What are your *priorities* for today? (in order)"
    question_number = 2
    total_questions = 3

    formatted_question = StandupFormatter.format_question(question_text, question_number, total_questions)

    expected = "*Question 2/3:* What are your *priorities* for today? (in order)\n\n_Type your answer or 'skip' to skip this question._"
    assert_equal expected, formatted_question
  end
end
