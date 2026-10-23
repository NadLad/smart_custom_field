# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# The admin form must expose the computed flag and the formula textarea.
class SmartCustomFieldAdminFormTest < Redmine::ControllerTest
  tests CustomFieldsController
  fixtures :custom_fields, :trackers

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
end
