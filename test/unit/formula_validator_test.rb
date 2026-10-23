# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldFormulaValidatorTest < ActiveSupport::TestCase
  def setup
    @other = IssueCustomField.where(:is_for_all => true).first
    assert_not_nil @other, 'fixtures must provide an issue custom field'
    @custom_field = IssueCustomField.new(
      :name => 'Validator test',
      :field_format => 'int',
      :is_for_all => true,
      :is_computed => true
    )
  end

  def test_accepts_a_valid_formula
    @custom_field.formula = "cfs[#{@other.id}] * 2"

    assert_valid @custom_field
  end

  def test_accepts_a_formula_using_model_attributes
    @custom_field.formula = '(self.estimated_hours || 0) * 2'

    assert_valid @custom_field
  end

  def test_rejects_a_blank_formula
    @custom_field.formula = '  '

    assert_invalid @custom_field
    assert @custom_field.errors[:formula].any?
  end

  def test_rejects_a_syntax_error
    @custom_field.formula = 'cfs[1] +'

    assert_invalid @custom_field
    assert_match(/syntax error/i, @custom_field.errors[:formula].join)
  end

  def test_rejects_an_unknown_custom_field_id
    missing_id = CustomField.maximum(:id).to_i + 1000
    @custom_field.formula = "cfs[#{missing_id}] + 1"

    assert_invalid @custom_field
    assert_match(/#{missing_id}/, @custom_field.errors[:formula].join)
  end

  def test_rejects_a_custom_field_of_another_type
    project_field = ProjectCustomField.first
    @custom_field.formula = "cfs[#{project_field.id}] + 1"

    assert_invalid @custom_field
    assert_match(/#{project_field.id}/, @custom_field.errors[:formula].join)
  end

  def test_rejects_an_unknown_method
    @custom_field.formula = 'no_such_method_here'

    assert_invalid @custom_field
    assert_match(/no_such_method_here/, @custom_field.errors[:formula].join)
  end

  def test_ignores_fields_that_are_not_computed
    @custom_field.is_computed = false
    @custom_field.formula = 'cfs[999999] +'

    assert_valid @custom_field
  end

  private

  def assert_valid(record)
    record.valid?
    assert_empty record.errors.full_messages
  end

  def assert_invalid(record)
    assert_not record.valid?
  end
end
