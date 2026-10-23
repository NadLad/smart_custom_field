# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldCustomFieldTest < ActiveSupport::TestCase
  def setup
    @field = IssueCustomField.create!(
      :name => 'Computed flag', :field_format => 'int', :is_for_all => true
    )
  end

  def test_is_computed_is_assignable_on_creation
    field = IssueCustomField.create!(
      :name => 'Created computed', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '1 + 1'
    )

    assert field.is_computed?
  end

  def test_is_computed_cannot_be_changed_after_creation
    @field.update!(:is_computed => true, :formula => '1 + 1')

    assert_not @field.reload.is_computed?
  end

  def test_formula_is_stripped
    @field.update!(:formula => "  cfs[1] * 2\n")

    assert_equal 'cfs[1] * 2', @field.reload.formula
  end

  def test_formula_is_not_validated_on_a_regular_field
    @field.update!(:formula => 'not even valid ruby +')

    assert_not @field.is_computed?
    assert_empty @field.errors.full_messages
  end

  def test_formula_and_is_computed_are_safe_attributes
    # safe_attributes is a list of [names, options] pairs.
    names = IssueCustomField.safe_attributes.flat_map { |attributes, _options| attributes }

    assert_includes names, 'formula'
    assert_includes names, 'is_computed'
  end
end
