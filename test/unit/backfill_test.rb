# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A computed field only gets a value when its object is saved, so a field added
# to a populated installation stays empty until every issue is touched again.
class SmartCustomFieldBackfillTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules,
           :journals, :journal_details

  def setup
    @issue = Issue.find(1)
  end

  def test_a_dry_run_reports_the_changes_without_writing_them
    field = create_computed('(self.estimated_hours || 0) * 2')

    report = SmartCustomField::Backfill.run

    assert report.scanned.positive?, 'the run should have walked the issues'
    assert report.changed.positive?, 'an empty computed field should be reported'
    assert_equal 0, report.failed
    assert_nil Issue.find(@issue.id).custom_field_value(field), 'a dry run must not write'
  end

  def test_applying_writes_the_computed_value
    field = create_computed('(self.estimated_hours || 0) * 2')
    expected = ((@issue.estimated_hours || 0) * 2).to_i.to_s

    SmartCustomField::Backfill.run(:apply => true)

    assert_equal expected, Issue.find(@issue.id).custom_field_value(field)
  end

  def test_applying_creates_the_missing_value_row
    field = create_computed('42')
    assert_nil @issue.custom_values.detect { |cv| cv.custom_field_id == field.id }

    SmartCustomField::Backfill.run(:apply => true)

    custom_value = Issue.find(@issue.id).custom_values.detect { |cv| cv.custom_field_id == field.id }
    assert_not_nil custom_value, 'the backfill should have created the row'
    assert_equal '42', custom_value.value
  end

  # The whole point of writing custom_values directly: a backfill of a
  # populated installation must not look like an edit of every issue.
  def test_applying_touches_neither_updated_on_nor_the_journals
    create_computed('42')
    before_updated_on = Issue.find(@issue.id).updated_on
    before_journals = Journal.where(:journalized_type => 'Issue').count

    SmartCustomField::Backfill.run(:apply => true)

    assert_equal before_updated_on, Issue.find(@issue.id).updated_on
    assert_equal before_journals, Journal.where(:journalized_type => 'Issue').count
  end

  def test_a_second_run_finds_nothing_left_to_do
    create_computed('42')

    SmartCustomField::Backfill.run(:apply => true)
    report = SmartCustomField::Backfill.run(:apply => true)

    assert_equal 0, report.changed
  end

  def test_a_failing_formula_is_collected_per_field_and_does_not_stop_the_run
    broken = create_computed('1')
    broken.update_column(:formula, 'raise "boom"')
    healthy = create_computed('7')

    report = SmartCustomField::Backfill.run(:apply => true)

    assert report.failed.positive?
    assert_match(/boom/, report.errors.first)
    assert_match(/#{broken.name}/, report.errors.first)
    assert_equal '7', Issue.find(@issue.id).custom_field_value(healthy)
  end

  def test_a_field_the_object_cannot_carry_is_left_alone
    other_tracker = Tracker.where.not(:id => @issue.tracker_id).first
    assert_not_nil other_tracker, 'fixtures must provide a second tracker'

    field = create_computed('42')
    field.trackers = [other_tracker]

    SmartCustomField::Backfill.run(:apply => true)

    assert_nil Issue.find(@issue.id).custom_field_value(field),
               'a field of another tracker must not be filled'
  end

  def test_an_empty_result_creates_no_row
    # A string field is the one format whose empty result stays empty: an int
    # field casts '' to '0' and therefore does have a value to store.
    field = create_computed("''", 'string')

    SmartCustomField::Backfill.run(:apply => true)

    assert_nil @issue.custom_values.detect { |cv| cv.custom_field_id == field.id },
               'an empty computed value is the same as no value at all'
  end

  def test_warns_about_a_formula_reading_user_current
    create_computed('User.current.id')

    report = SmartCustomField::Backfill.run

    assert report.warnings.any? { |warning| warning.include?('User.current') }
  end

  def test_warns_about_a_formula_reading_another_computed_field
    first = create_computed('1')
    create_computed("cfs[#{first.id}] + 1")

    report = SmartCustomField::Backfill.run

    assert report.warnings.any? { |warning| warning.include?('another computed field') }
  end

  def test_no_computed_field_leaves_an_empty_report
    # The plugin's own fields are the only computed ones, and this test creates
    # none: the run must not walk anything.
    report = SmartCustomField::Backfill.run

    assert_equal 0, report.scanned
    assert_equal 0, report.changed
  end

  def test_a_custom_batch_size_does_not_change_the_result
    field = create_computed('42')

    SmartCustomField::Backfill.run(:apply => true, :batch_size => 1)

    assert_equal '42', Issue.find(@issue.id).custom_field_value(field)
  end

  private

  def create_computed(formula, format = 'int')
    field = IssueCustomField.create!(
      :name => "Backfill #{formula.hash.abs}", :field_format => format,
      :is_for_all => true, :is_computed => true, :formula => formula
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end
end
