module Percentage
  module_function

  # numerator as a percentage of denominator, to one decimal place, or `empty`
  # when there's nothing to divide by.
  def of(numerator, denominator, empty: 0.0)
    return empty unless denominator.to_f.positive?

    (numerator * 100.0 / denominator).round(1)
  end
end
