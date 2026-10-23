# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# The admin preview evaluates a formula against a real object and returns the
# result. It must never write, and it must stay admin-only: it runs arbitrary
# Ruby in the context of the object.
class SmartCustomFieldPreviewTest < Redmine::ControllerTest
  tests SmartCustomField::PreviewsController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @request.session[:user_id] = 1
  end

  def test_an_admin_gets_the_result_and_the_casted_value
    post :preview, :params => {
      :object_type => 'Issue', :object_id => 1,
      :formula => '1 + 1', :field_format => 'int'
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload['ok'], payload.inspect
    assert_equal '2', payload['result']
    assert_equal '2', payload['cast_value']
  end

  def test_a_non_admin_is_refused
    @request.session[:user_id] = 2

    post :preview, :params => {
      :object_type => 'Issue', :object_id => 1,
      :formula => '1 + 1', :field_format => 'int'
    }

    assert_response :forbidden
  end

  def test_the_preview_writes_no_custom_value
    field = IssueCustomField.create!(
      :name => 'Preview no write', :field_format => 'int', :is_for_all => true
    )
    field.trackers = Tracker.all.to_a

    assert_no_difference 'CustomValue.count' do
      post :preview, :params => {
        :object_type => 'Issue', :object_id => 1,
        :formula => "cfs[#{field.id}] + 1", :field_format => 'int'
      }
    end

    assert_response :success
  end

  def test_the_preview_lists_the_inputs_the_formula_reads
    field = IssueCustomField.create!(
      :name => 'Preview input', :field_format => 'int', :is_for_all => true
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a

    issue = Issue.find(1)
    issue.custom_field_values = {field.id.to_s => '7'}
    assert issue.save, issue.errors.full_messages.join(', ')

    post :preview, :params => {
      :object_type => 'Issue', :object_id => issue.id,
      :formula => "cfs[#{field.id}] * 2", :field_format => 'int'
    }

    payload = JSON.parse(response.body)
    assert_equal '14', payload['cast_value'], payload.inspect

    input = payload['inputs'].first
    assert_equal field.id, input['id']
    assert_equal 'Preview input', input['name']
    assert_equal '7', input['cast']
  end

  def test_the_preview_returns_the_static_warnings
    post :preview, :params => {
      :object_type => 'Issue', :object_id => 1,
      :formula => 'project.estimted_hours', :field_format => 'int'
    }

    payload = JSON.parse(response.body)
    assert(payload['warnings'].any? { |warning| warning.include?('estimted_hours') })
  end

  def test_a_broken_formula_is_reported_without_an_error_response
    post :preview, :params => {
      :object_type => 'Issue', :object_id => 1,
      :formula => '1 +', :field_format => 'int'
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_not payload['ok']
    assert_not_nil payload['error']
  end

  def test_an_unknown_object_type_is_refused
    post :preview, :params => {
      :object_type => 'Tracker', :object_id => 1,
      :formula => '1 + 1', :field_format => 'int'
    }

    assert_response :not_found
  end

  def test_a_missing_object_is_not_found
    post :preview, :params => {
      :object_type => 'Issue', :object_id => 999_999,
      :formula => '1 + 1', :field_format => 'int'
    }

    assert_response :not_found
  end
end
