# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A computed field is rendered as its value on every customizable form: an
# editable control would only invite an edit the next save throws away.
class SmartCustomFieldReadOnlyFormTest < Redmine::ControllerTest
  tests ProjectsController
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :custom_fields,
           :custom_values, :issue_statuses, :enumerations

  def setup
    @request.session[:user_id] = 1
    @computed = ProjectCustomField.create!(
      :name => 'Computed read only', :field_format => 'int',
      :is_for_all => true, :is_computed => true, :formula => '42'
    )
    @plain = ProjectCustomField.create!(
      :name => 'Plain editable', :field_format => 'int', :is_for_all => true
    )
  end

  def test_the_project_form_offers_no_input_for_a_computed_field
    get :settings, :params => {:id => 1}
    assert_response :success

    assert_select "input[name=?]", "project[custom_field_values][#{@computed.id}]", :count => 0
    assert_select 'span.computed-custom-field-value'
  end

  def test_the_project_form_keeps_an_ordinary_field_editable
    get :settings, :params => {:id => 1}
    assert_response :success

    assert_select "input[name=?]", "project[custom_field_values][#{@plain.id}]"
  end

  def test_the_label_of_a_computed_field_points_at_no_control
    get :settings, :params => {:id => 1}
    assert_response :success

    assert_select 'label[for=?]', "project_custom_field_values_#{@computed.id}", :count => 0
  end

  def test_the_new_project_form_says_the_value_is_not_computed_yet
    get :new
    assert_response :success

    assert_select 'span.computed-custom-field-value', :text => I18n.t(:label_computed_value_pending)
  end

  def test_a_stored_value_is_shown_as_text
    project = Project.find(1)
    # '999' is what a client would have posted; the formula overwrites it.
    project.custom_field_values = {@computed.id.to_s => '999'}
    assert project.save, project.errors.full_messages.join(', ')

    get :settings, :params => {:id => 1}
    assert_response :success

    assert_select 'span.computed-custom-field-value', :text => '42'
  end
end
