# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# The condition builder is JavaScript: it cannot be exercised from here. What
# can be pinned down is the contract it produces - the exact shapes it writes
# into the textarea must be Ruby the evaluator accepts.
#
# These tests document those shapes; the builder's source is the only place
# that generates them.
class SmartCustomFieldFormulaBuilderExpressionTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @object = Issue.find(1)
    @number = 12
    @text = 13
    @flag = 14
    @date = 15
  end

  def test_a_numeric_condition_joined_with_and
    expression = "(cfs[#{@number}] > 5 && cfs[#{@number}] < 10)"

    assert_equal true, evaluate(expression, @number => 7)
    assert_equal false, evaluate(expression, @number => 11)
  end

  def test_conditions_joined_with_or
    expression = "(cfs[#{@number}] > 5 || cfs[#{@text}] == 'x')"

    assert_equal true, evaluate(expression, @number => 1, @text => 'x')
    assert_equal false, evaluate(expression, @number => 1, @text => 'y')
  end

  def test_a_quoted_string_keeps_an_apostrophe
    # The builder escapes backslashes then apostrophes, which is exactly what
    # Ruby needs inside a single quoted literal.
    expression = "cfs[#{@text}] == 'l\\'été'"

    assert_equal true, evaluate(expression, @text => "l'été")
  end

  def test_a_boolean_condition_compares_to_true
    assert_equal true, evaluate("cfs[#{@flag}] == true", @flag => true)
    assert_equal false, evaluate("cfs[#{@flag}] == true", @flag => false)
  end

  def test_a_date_condition_parses_the_literal
    assert_equal true, evaluate("cfs[#{@date}] == Date.parse('2026-01-01')",
                                @date => Date.new(2026, 1, 1))
  end

  def test_an_empty_numeric_value_is_written_as_zero
    # The builder never emits a dangling comparison: an empty input becomes 0,
    # so the expression stays valid Ruby and stays falsy.
    assert_equal false, evaluate("cfs[#{@number}] > 0", @number => 0)
  end

  private

  def evaluate(source, values)
    SmartCustomField::Evaluator.evaluate(source, @object, values)
  end
end
