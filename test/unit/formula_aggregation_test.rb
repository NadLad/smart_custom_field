# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# Totals over a set of issues: a formula should not have to walk a relation by
# hand, and it must never be able to turn one save into a full table scan.
class SmartCustomFieldFormulaAggregationTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @field = create_issue_field('Aggregated points', 'int')
    @root = Issue.find(1)
  end

  def test_cf_sum_adds_the_values_of_a_collection
    first = create_child(@root, 10)
    second = create_child(@root, 20)

    assert_equal 30, SmartCustomField::FormulaHelpers.cf_sum([first, second], @field.id)
    assert_equal 30, @root.cf_sum(@root.children, @field.id)
  end

  # `cf` reads an unset integer field as 0, which would drag the mean down: the
  # aggregation has to look at the stored value instead.
  def test_cf_avg_ignores_the_values_that_are_not_set
    create_child(@root, 10)
    create_child(@root, nil)
    create_child(@root, 20)

    assert_equal 15.0, SmartCustomField::FormulaHelpers.cf_avg(@root.children, @field.id)
  end

  def test_cf_min_and_cf_max
    create_child(@root, 10)
    create_child(@root, 3)
    create_child(@root, 42)

    assert_equal 3, SmartCustomField::FormulaHelpers.cf_min(@root.children, @field.id)
    assert_equal 42, SmartCustomField::FormulaHelpers.cf_max(@root.children, @field.id)
  end

  def test_an_empty_collection_aggregates_to_nothing
    helpers = SmartCustomField::FormulaHelpers

    assert_equal 0, helpers.cf_sum(@root.children, @field.id)
    assert_nil helpers.cf_avg(@root.children, @field.id)
    assert_nil helpers.cf_min(@root.children, @field.id)
    assert_nil helpers.cf_max(@root.children, @field.id)
    assert_equal 0, helpers.cf_sum(nil, @field.id)
  end

  def test_a_collection_above_the_cap_raises
    too_big = Array.new(SmartCustomField::FormulaHelpers::MAX_COLLECTION + 1)

    error = assert_raises(SmartCustomField::FormulaHelpers::AggregationError) do
      SmartCustomField::FormulaHelpers.cf_sum(too_big, @field.id)
    end

    assert_match(/more than #{SmartCustomField::FormulaHelpers::MAX_COLLECTION}/, error.message)
  end

  def test_subtree_walks_the_whole_branch_and_excludes_the_issue_itself
    child = create_child(@root, 10)
    grandchild = create_child(child, 20)
    create_child(grandchild, 40)

    # Creating a child rewrites the parent's lft/rgt in the database: the
    # instance loaded by the fixture is stale until it is reloaded.
    @root.reload

    # The root's own value is left out: a formula computing the root cannot
    # read its own value back.
    @root.custom_field_values = {@field.id.to_s => '5'}
    assert @root.save, @root.errors.full_messages.join(', ')

    assert_equal 70, SmartCustomField::FormulaHelpers.cf_sum(@root.subtree, @field.id)
    assert_equal 3, @root.subtree.size
  end

  def test_subtree_of_a_leaf_is_empty
    assert_equal [], @root.subtree
  end

  def test_subtree_refuses_a_tree_deeper_than_the_cap
    issue = @root
    (SmartCustomField::FormulaHelpers::MAX_DEPTH + 1).times { issue = create_child(issue, 1) }
    @root.reload

    error = assert_raises(SmartCustomField::FormulaHelpers::AggregationError) do
      @root.subtree
    end

    assert_match(/levels deep/, error.message)
  end

  # The whole point: a formula totals a branch without a single line of Ruby
  # in the formula itself.
  def test_a_formula_totals_a_subtree
    computed = create_issue_field('Aggregated total', 'int',
                                  :is_computed => true,
                                  :formula => "cf_sum(subtree, #{@field.id})")
    create_child(@root, 10)
    create_child(@root, 32)
    @root.reload

    assert @root.save, @root.errors.full_messages.join(', ')
    assert_equal '42', @root.custom_field_value(computed)
  end

  private

  def create_issue_field(name, format, options = {})
    field = IssueCustomField.create!(
      {:name => name, :field_format => format, :is_for_all => true}.merge(options)
    )
    field.trackers = Tracker.all.to_a
    field
  end

  def create_child(parent, value)
    child = Issue.new(:project_id => parent.project_id, :tracker_id => parent.tracker_id,
                      :author_id => 2, :subject => "Child of ##{parent.id}",
                      :parent_id => parent.id)
    child.custom_field_values = {@field.id.to_s => value.to_s} unless value.nil?
    assert child.save, child.errors.full_messages.join(', ')
    child
  end
end
