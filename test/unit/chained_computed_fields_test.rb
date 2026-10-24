# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A formula reads `cfs` as a snapshot of the values stored before the first
# evaluation. A chain (`total = subtotal * rate`, where `subtotal` is itself
# computed) therefore used to settle one save behind: the second field read the
# value the first one had stored on the *previous* save, and the README told
# users to save twice. These tests pin the two halves of the fix: the fields are
# evaluated in dependency order, and the snapshot moves forward as they are.
class SmartCustomFieldChainedFieldsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @source = create_field('Chain source', 'int', '1')
    @middle = create_field('Chain middle', 'int', "cfs[#{@source.id}] * 10")
    @last = create_field('Chain last', 'int', "cfs[#{@middle.id}] + 5")
  end

  # Without moving the snapshot forward, the middle field read the source's
  # *stored* value (nil, cast to 0 on the first save) instead of the 1 it had
  # just produced.
  def test_a_two_level_chain_settles_in_one_save
    issue = create_issue

    assert_equal '10', value_of(issue, @middle)
  end

  def test_a_three_level_chain_settles_in_one_save
    issue = create_issue

    assert_equal '15', value_of(issue, @last)
  end

  # Redmine orders the values of an object by the field's position, which is
  # creation order. A formula edited later to read a newer field therefore sits
  # *before* the field it reads, and the dependency order has to win over that.
  def test_a_formula_edited_to_read_a_newer_field_settles_in_one_save
    first = create_field('Chain early reader', 'int', '1')
    second = create_field('Chain later source', 'int', '2')
    first.update_column(:formula, "cfs[#{second.id}] * 2")

    issue = build_issue
    order = issue.custom_field_values.map(&:custom_field_id)
    assert_operator order.index(first.id), :<, order.index(second.id),
                    'the test needs the reader to come before the field it reads'

    assert issue.save, issue.errors.full_messages.join(', ')
    assert_equal '2', value_of(issue, second)
    assert_equal '4', value_of(issue, first)
  end

  # The digest of a downstream field is computed from the value the upstream one
  # just produced. If it were computed from the stale snapshot, the downstream
  # field would be skipped exactly when its input moved.
  def test_a_change_upstream_reaches_the_downstream_field
    plain = create_field('Chain input', 'int', nil)
    source = create_field('Chain live source', 'int', "cfs[#{plain.id}] + 1")
    dependent = create_field('Chain live dependent', 'int', "cfs[#{source.id}] * 10")

    issue = create_issue(plain => '1')
    assert_equal '20', value_of(issue, dependent)

    issue = Issue.find(issue.id)
    issue.custom_field_values = {plain.id.to_s => '5'}
    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal '60', value_of(issue, dependent)
  end

  # A cycle the installation already carries cannot be ordered. The save must
  # still go through, one value behind, instead of failing forever.
  def test_a_stored_cycle_does_not_block_the_save
    first = create_field('Chain cycle A', 'int', '1')
    second = create_field('Chain cycle B', 'int', '2')
    first.update_column(:formula, "cfs[#{second.id}] + 1")
    second.update_column(:formula, "cfs[#{first.id}] + 1")

    issue = create_issue

    assert_not_nil value_of(issue, first)
    assert_not_nil value_of(issue, second)
  end

  private

  def create_field(name, format, formula, id: nil)
    attributes = {
      :name => name,
      :field_format => format,
      :is_for_all => true,
      :is_computed => !formula.nil?,
      :formula => formula
    }
    attributes[:id] = id if id

    field = IssueCustomField.create!(attributes)
    # Issue#available_custom_fields is the intersection of the project fields
    # and the tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end

  def create_issue(values = {})
    issue = build_issue
    issue.custom_field_values = values.to_h { |field, value| [field.id.to_s, value] }
    assert issue.save, issue.errors.full_messages.join(', ')
    issue
  end

  def build_issue
    Issue.new(:project_id => 1, :tracker_id => 1,
              :subject => 'Chained computed fields', :author_id => 2)
  end

  def value_of(issue, field)
    issue.reload.custom_field_value(field)
  end
end
