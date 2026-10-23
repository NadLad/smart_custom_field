# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# The computed value must fit the format of its custom field, and every
# customizable model must support it, not only Issue.
class SmartCustomFieldComputedFormatsTest < ActiveSupport::TestCase
  def setup
    @source = IssueCustomField.create!(
      :name => 'Source', :field_format => 'int', :is_for_all => true
    )
    @source.trackers = Tracker.all.to_a
  end

  def test_bool_format
    field = create_issue_field('Computed bool', 'bool', "cfs[#{@source.id}] > 2")

    assert_equal '1', value_of(create_issue(@source => '3'), field)
    assert_equal '0', value_of(create_issue(@source => '1'), field)
  end

  def test_list_format
    field = create_issue_field('Computed list', 'list', '"High"',
                               :possible_values => %w[Low High])

    assert_equal 'High', value_of(create_issue(@source => '1'), field)
  end

  # Only list formats support multiple values: CustomField#multiple is reset
  # for every other format.
  def test_string_interpolation
    field = create_issue_field('Computed label', 'string',
                               '"#{subject} (#{cfs[%d]})"' % @source.id)

    assert_equal 'Computed formats (7)', value_of(create_issue(@source => '7'), field)
  end

  def test_multiple_values
    field = create_issue_field(
      'Computed multiples', 'list',
      "(cfs[#{@source.id}] > 2) ? %w[low high] : %w[low]",
      :multiple => true, :possible_values => %w[low high]
    )

    assert field.multiple?
    assert_equal %w[low high], value_of(create_issue(@source => '3'), field)
    assert_equal %w[low], value_of(create_issue(@source => '1'), field)
  end

  def test_project_custom_field
    source = ProjectCustomField.create!(
      :name => 'Project source', :field_format => 'int', :is_for_all => true
    )
    field = ProjectCustomField.create!(
      :name => 'Project computed', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => "cfs[#{source.id}] * 10"
    )
    project = Project.new(:name => 'Computed project', :identifier => 'computed-project')
    project.custom_field_values = {source.id.to_s => '4'}
    assert project.save, project.errors.full_messages.join(', ')

    assert_equal '40', project.reload.custom_field_value(field)
  end

  def test_time_entry_custom_field
    source = TimeEntryCustomField.create!(
      :name => 'Hours source', :field_format => 'float', :is_for_all => true
    )
    field = TimeEntryCustomField.create!(
      :name => 'Hours computed', :field_format => 'float', :is_for_all => true,
      :is_computed => true, :formula => "cfs[#{source.id}] * 2"
    )
    entry = TimeEntry.new(:project_id => 1, :user_id => 2, :hours => 1,
                          :spent_on => Date.current, :activity_id => 9)
    entry.custom_field_values = {source.id.to_s => '1.5'}
    assert entry.save, entry.errors.full_messages.join(', ')

    assert_equal '3.0', entry.reload.custom_field_value(field)
  end

  private

  def create_issue_field(name, format, formula, attributes = {})
    field = IssueCustomField.create!({
      :name => name, :field_format => format, :is_for_all => true,
      :is_computed => true, :formula => formula
    }.merge(attributes))
    field.trackers = Tracker.all.to_a
    field
  end

  def create_issue(values = {})
    issue = Issue.new(:project_id => 1, :tracker_id => 1,
                      :subject => 'Computed formats', :author_id => 2)
    issue.custom_field_values = values.to_h { |field, value| [field.id.to_s, value] }
    assert issue.save, issue.errors.full_messages.join(', ')
    issue
  end

  def value_of(issue, field)
    issue.reload.custom_field_value(field)
  end
end
