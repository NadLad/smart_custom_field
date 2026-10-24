# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# The admin form must expose the computed flag and the formula textarea.
class SmartCustomFieldAdminFormTest < Redmine::ControllerTest
  tests CustomFieldsController
  fixtures :custom_fields, :trackers, :projects, :users, :email_addresses, :roles,
           :members, :member_roles, :issues, :issue_statuses, :enumerations,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @request.session[:user_id] = 1
  end

  def test_new_form_renders_the_computed_flag
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    assert_select 'input#custom_field_is_computed[type=checkbox]'
    assert_select 'textarea#custom_field_formula'
    assert_select 'select#smart-custom-field-available'
  end

  def test_new_form_renders_the_preview_panel
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    assert_select '#smart-custom-field-preview'
    assert_select '#smart-custom-field-preview-run'
  end

  def test_new_form_lists_the_fields_that_can_be_referenced
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    assert_select 'select#smart-custom-field-available option', :minimum => 1
  end

  def test_new_form_renders_the_condition_builder
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    assert_select '#smart-custom-field-builder'
    assert_select '#smart-custom-field-builder-rows'
    assert_select '#smart-custom-field-builder-add'
    assert_select '#smart-custom-field-builder-apply'
    # The behaviour lives in a plugin asset, not in an inline script.
    assert_select 'script[src*="smart_custom_field_formula_builder"]'
  end

  def test_the_builder_carries_the_format_of_each_referenceable_field
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    # The builder picks its operators and quotes the value from the format, so
    # the format has to travel with the option.
    assert_select 'select#smart-custom-field-builder-fields option[data-format]', :minimum => 1
  end

  def test_the_builder_never_replaces_the_formula_textarea
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    # The textarea stays the source of truth: the builder is a generator that
    # inserts into it, not a widget that owns the value.
    assert_select 'textarea#custom_field_formula'
    assert_select '#smart-custom-field-builder textarea', :count => 0
  end

  def test_edit_form_renders_the_formula_of_a_computed_field
    field = IssueCustomField.create!(
      :name => 'Computed edit', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => 'estimated_hours * 2'
    )

    get :edit, :params => {:id => field.id}
    assert_response :success

    assert_select 'textarea#custom_field_formula', :text => 'estimated_hours * 2'
    # The flag cannot be changed once the field exists.
    assert_select 'input#custom_field_is_computed[disabled]'
  end

  def test_create_a_computed_field_from_the_admin_form
    assert_difference 'IssueCustomField.count' do
      post :create, :params => {
        :type => 'IssueCustomField',
        :custom_field => {
          :name => 'Computed created', :field_format => 'int',
          :is_for_all => '1', :is_computed => '1', :formula => 'estimated_hours * 3'
        }
      }
    end
    assert_response :redirect

    field = IssueCustomField.order(:id).last
    assert field.is_computed?
    assert_equal 'estimated_hours * 3', field.formula
  end

  def test_create_rejects_an_invalid_formula
    assert_no_difference 'IssueCustomField.count' do
      post :create, :params => {
        :type => 'IssueCustomField',
        :custom_field => {
          :name => 'Computed broken', :field_format => 'int',
          :is_for_all => '1', :is_computed => '1', :formula => 'cfs[999999] + 1'
        }
      }
    end
    assert_response :success
    assert_select 'div#errorExplanation'
  end

  # Editing a formula does not rewrite the values it already produced: the form
  # has to say so before the save, not after.
  def test_edit_form_warns_about_the_values_already_computed
    field = create_computed_field('Stale singular', '1')
    save_issue_with(field)

    get :edit, :params => {:id => field.id}
    assert_response :success

    assert_select 'p.stale-computed-values', :text => /1 stored value/
  end

  # Counted on objects, not on rows: the warning is about records whose value
  # will not follow the new formula.
  def test_edit_form_counts_the_objects
    field = create_computed_field('Stale plural', '1')
    save_issue_with(field)
    save_issue_with(field)

    get :edit, :params => {:id => field.id}
    assert_response :success

    assert_select 'p.stale-computed-values', :text => /2 stored values/
  end

  def test_edit_form_does_not_warn_without_stored_values
    field = create_computed_field('Stale none', '1')

    get :edit, :params => {:id => field.id}
    assert_response :success

    assert_select 'p.stale-computed-values', :count => 0
  end

  def test_new_form_does_not_warn
    get :new, :params => {:type => 'IssueCustomField'}
    assert_response :success

    assert_select 'p.stale-computed-values', :count => 0
  end

  private

  def create_computed_field(name, formula)
    field = IssueCustomField.create!(
      :name => name, :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => formula
    )
    field.trackers = Tracker.all.to_a
    field
  end

  def save_issue_with(field)
    issue = Issue.new(:project_id => 1, :tracker_id => 1,
                      :subject => "Stale value #{field.id}", :author_id => 2)
    issue.custom_field_values = {field.id.to_s => '1'}
    assert issue.save, issue.errors.full_messages.join(', ')
    issue
  end
end
