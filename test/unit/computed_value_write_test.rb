# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A computed value is derived: the form must not offer to edit it, and a
# submitted value must never reach the database.
class SmartCustomFieldComputedValueWriteTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @field = create_field('Write guard', 'int', :is_computed => true, :formula => '42')
    @issue = Issue.find(1)
  end

  def test_a_submitted_computed_value_is_ignored
    @issue.custom_field_values = {@field.id.to_s => '999'}

    assert @issue.save, @issue.errors.full_messages.join(', ')
    assert_equal '42', Issue.find(@issue.id).custom_field_value(@field)
  end

  def test_the_computation_still_writes_its_own_value
    assert @issue.save, @issue.errors.full_messages.join(', ')

    assert_equal '42', Issue.find(@issue.id).custom_field_value(@field)
  end

  # Without the window the computation would filter out its own results.
  def test_the_window_is_closed_once_the_computation_is_over
    @issue.save

    assert_not SmartCustomField::FormulaComputation.writing?
  end

  def test_the_window_is_counted_so_a_nested_write_cannot_close_it
    SmartCustomField::FormulaComputation.writing do
      SmartCustomField::FormulaComputation.writing { nil }

      assert SmartCustomField::FormulaComputation.writing?
    end

    assert_not SmartCustomField::FormulaComputation.writing?
  end

  # A formula that raises writes no new value: without the filter the value
  # posted by the client would survive exactly in that case.
  def test_a_failing_formula_does_not_let_a_submitted_value_through
    @field.update_column(:formula, 'raise "boom"')
    @issue.custom_field_values = {@field.id.to_s => '999'}

    assert_not @issue.save
    assert_nil Issue.find(@issue.id).custom_field_value(@field)
  end

  def test_an_ordinary_field_is_still_assignable
    plain = create_field('Write plain', 'int')

    @issue.custom_field_values = {plain.id.to_s => '5'}

    assert @issue.save, @issue.errors.full_messages.join(', ')
    assert_equal '5', Issue.find(@issue.id).custom_field_value(plain)
  end

  def test_an_ordinary_field_is_assignable_next_to_a_computed_one
    plain = create_field('Write mixed', 'int')

    @issue.custom_field_values = {@field.id.to_s => '999', plain.id.to_s => '5'}

    assert @issue.save, @issue.errors.full_messages.join(', ')
    reloaded = Issue.find(@issue.id)
    assert_equal '42', reloaded.custom_field_value(@field)
    assert_equal '5', reloaded.custom_field_value(plain)
  end

  private

  def create_field(name, format, options = {})
    field = IssueCustomField.create!(
      {:name => name, :field_format => format, :is_for_all => true}.merge(options)
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end
end
