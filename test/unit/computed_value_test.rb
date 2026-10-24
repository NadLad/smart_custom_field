# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# Computed custom fields must be recalculated on every save and must not be
# editable by the user.
class SmartCustomFieldComputedValueTest < ActiveSupport::TestCase
  def setup
    @a = create_field('Computed A', 'int', '1')
    @b = create_field('Computed B', 'int', '2')
    @sum = create_field('Computed sum', 'int', "cfs[#{@a.id}] + cfs[#{@b.id}]", true)
  end

  def test_computes_the_value_on_save
    issue = create_issue(@a => '3', @b => '4')

    assert_equal '7', value_of(issue, @sum)
  end

  def test_recomputes_the_value_when_an_input_changes
    issue = create_issue(@a => '3', @b => '4')
    issue = Issue.find(issue.id)
    issue.custom_field_values = {@a.id.to_s => '10'}
    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal '14', value_of(issue.reload, @sum)
  end

  def test_ignores_a_value_submitted_for_the_computed_field
    issue = create_issue(@a => '3', @b => '4', @sum => '999')

    assert_equal '7', value_of(issue, @sum)
  end

  def test_uses_model_attributes
    field = create_field('Computed hours', 'float', 'estimated_hours * 2', true)
    issue = create_issue({}, :estimated_hours => 4)

    assert_equal '8.0', value_of(issue, field)
  end

  # A formula that never returns must block the save with a message, not hold
  # the request until the client gives up. The field is written around the
  # validator: a formula like this one cannot be saved through the admin form,
  # but an existing field can be given one by a bad import.
  def test_a_runaway_formula_blocks_the_save
    field = create_field('Computed loop', 'int', '1', true)
    field.update_column(:formula, 'loop { }')
    issue = Issue.new(:project_id => 1, :tracker_id => 1,
                      :subject => 'Runaway formula', :author_id => 2)

    SmartCustomField::Evaluator.evaluation_timeout = 0.05
    assert_not issue.save
  ensure
    SmartCustomField::Evaluator.evaluation_timeout = SmartCustomField::Evaluator::EVALUATION_TIMEOUT

    assert_match(/took more than 0\.05 seconds/, issue.errors.full_messages.join(' '))
  end

  def test_casts_the_result_to_the_field_format
    field = create_field('Computed text', 'string', '"total: #{cfs[%d]}"' % @a.id, true)
    issue = create_issue(@a => '42')

    assert_equal 'total: 42', value_of(issue, field)
  end

  def test_reports_a_runtime_error_on_the_object
    field = create_field('Computed broken', 'int', "cfs[#{@a.id}]", true)
    # Bypass validation: the validator rejects an obviously broken formula, so
    # a runtime failure can only be reached by a formula that became invalid
    # after the field was saved.
    field.update_column(:formula, 'no_such_method')
    issue = Issue.new(:project_id => 1, :tracker_id => 1,
                      :subject => 'Broken formula', :author_id => 2)

    assert_not issue.valid?
    assert_match(/no_such_method/, issue.errors[:base].join)
  end

  def test_computed_field_is_read_only_on_issues
    issue = create_issue(@a => '1')

    user = User.find(2)

    assert_includes issue.read_only_attribute_names(user), @sum.id.to_s
    assert_not_includes issue.read_only_attribute_names(user), @a.id.to_s
    assert_not_includes issue.editable_custom_field_values(user).map(&:custom_field_id), @sum.id
  end

  def test_patches_are_applied_once
    before = Issue._validation_callbacks.count

    SmartCustomField::Patches.apply!
    SmartCustomField::Patches.apply!

    assert_equal before, Issue._validation_callbacks.count
    assert_equal 1, Issue.ancestors.count { |a| a == SmartCustomField::Patches::IssuePatch }
  end

  private

  def create_field(name, format, formula, computed = false)
    field = IssueCustomField.create!(
      :name => name,
      :field_format => format,
      :is_for_all => true,
      :is_computed => computed,
      :formula => formula
    )
    # Issue#available_custom_fields is the intersection of the project fields
    # and the tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end

  def create_issue(values = {}, attributes = {})
    issue = Issue.new({
      :project_id => 1,
      :tracker_id => 1,
      :subject => 'Computed field test',
      :author_id => 2
    }.merge(attributes))
    issue.custom_field_values = values.to_h { |field, value| [field.id.to_s, value] }
    assert issue.save, issue.errors.full_messages.join(', ')
    issue
  end

  def value_of(issue, field)
    issue.reload.custom_field_value(field)
  end
end
