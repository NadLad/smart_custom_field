# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# `cfs` only sees the fields of the object being computed. These helpers reach
# the values of another object, with the same cast.
class SmartCustomFieldFormulaHelpersTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @project_field = ProjectCustomField.create!(
      :name => 'Project budget', :field_format => 'int', :is_for_all => true
    )
    project = Project.find(1)
    project.custom_field_values = {@project_field.id.to_s => '40'}
    assert project.save, project.errors.full_messages.join(', ')
  end

  def test_a_formula_reads_a_custom_field_of_its_project
    computed = create_computed("cf(project, #{@project_field.id}) * 2")

    issue = Issue.find(1)
    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal '80', issue.custom_field_value(computed)
  end

  def test_a_formula_reads_a_custom_field_of_its_parent
    parent_field = create_issue_field('Parent estimate', 'int')
    parent = Issue.find(1)
    parent.custom_field_values = {parent_field.id.to_s => '7'}
    assert parent.save, parent.errors.full_messages.join(', ')

    child = Issue.new(:project_id => parent.project_id, :tracker_id => parent.tracker_id,
                      :author => User.find(1), :subject => 'Child', :parent_id => parent.id)
    computed = create_computed("cf(parent, #{parent_field.id})")

    assert child.save, child.errors.full_messages.join(', ')
    assert_equal '7', child.custom_field_value(computed)
  end

  def test_cfs_is_public_so_a_formula_can_read_another_object
    field = create_issue_field('Parent estimate', 'int')
    parent = Issue.find(1)
    parent.custom_field_values = {field.id.to_s => '7'}
    assert parent.save, parent.errors.full_messages.join(', ')

    assert_equal 7, parent.cfs[field.id]
    assert_equal 7, SmartCustomField::FormulaHelpers.cf(parent, field.id)
  end

  def test_a_missing_relation_reads_as_nil_instead_of_raising
    computed = create_computed("cf(project, #{@project_field.id})")

    # A new issue has no project: the helper must not raise, the formula simply
    # gets nil.
    assert_nil SmartCustomField::FormulaHelpers.cf(nil, @project_field.id)
    assert_equal({}, SmartCustomField::FormulaHelpers.cfs_for(nil))
    assert computed.persisted?
  end

  def test_the_helpers_shadow_no_existing_redmine_method
    SmartCustomField::Patches::CUSTOMIZABLE_MODELS.each do |name|
      model = name.constantize
      %i[cfs cf].each do |method_name|
        owner = model.instance_method(method_name).owner
        assert_equal SmartCustomField::Patches::CustomizablePatch, owner,
                     "#{name}##{method_name} comes from #{owner}"
        # A non-nil super_method would mean a method of Redmine (or of another
        # plugin) is now hidden behind ours.
        assert_nil model.instance_method(method_name).super_method,
                   "#{name}##{method_name} hides an existing method"
      end
    end
  end

  def test_two_instances_of_the_same_record_share_one_cache_entry
    SmartCustomField::FormulaHelpers.with_cache do
      first = SmartCustomField::FormulaHelpers.cfs_for(Project.find(1))
      second = SmartCustomField::FormulaHelpers.cfs_for(Project.find(1))

      assert first.equal?(second), 'the second read should come from the cache'
      assert_equal 40, first[@project_field.id]
    end
  end

  def test_the_cache_does_not_survive_the_computation
    SmartCustomField::FormulaHelpers.with_cache do
      SmartCustomField::FormulaHelpers.cfs_for(Project.find(1))
    end

    assert_nil Thread.current[SmartCustomField::FormulaHelpers::CACHE_KEY]
  end

  def test_an_unsaved_object_is_never_cached
    first = SmartCustomField::FormulaHelpers.cfs_for(Issue.new)
    second = SmartCustomField::FormulaHelpers.cfs_for(Issue.new)

    refute first.equal?(second), 'two new instances must not share an entry'
  end

  private

  def create_issue_field(name, format, formula = nil, computed = false)
    field = IssueCustomField.create!(
      :name => name, :field_format => format, :is_for_all => true,
      :is_computed => computed, :formula => formula
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end

  def create_computed(formula)
    create_issue_field("Computed #{formula.hash.abs}", 'int', formula, true)
  end
end
