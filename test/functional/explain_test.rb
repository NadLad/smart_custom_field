# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# "Why is this value 15?" The explain endpoint returns the formula of a saved
# computed field, the custom values it read and the result, for one real object.
class SmartCustomFieldExplainTest < Redmine::ControllerTest
  tests SmartCustomField::PreviewsController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    @request.session[:user_id] = 1
    @input = create_field('Explain input', 'int')
    @computed = create_field('Explain computed', 'int', "cfs[#{@input.id}] * 3", true)
    @issue = Issue.find(1)
    @issue.custom_field_values = {@input.id.to_s => '5'}
    assert @issue.save, @issue.errors.full_messages.join(', ')
  end

  def test_an_admin_gets_the_breakdown_of_a_saved_field
    get :explain, :params => {:custom_field_id => @computed.id, :object_id => @issue.id}

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload['ok'], payload.inspect
    assert_equal "cfs[#{@input.id}] * 3", payload['formula']
    assert_equal '15', payload['cast_value']
  end

  def test_the_breakdown_lists_every_input_with_its_name_and_value
    get :explain, :params => {:custom_field_id => @computed.id, :object_id => @issue.id}

    entry = JSON.parse(response.body)['inputs'].first
    assert_equal @input.id, entry['id']
    assert_equal 'Explain input', entry['name']
    assert_equal '5', entry['cast']
  end

  def test_the_breakdown_never_writes_a_custom_value
    assert_no_difference 'CustomValue.count' do
      get :explain, :params => {:custom_field_id => @computed.id, :object_id => @issue.id}
    end

    assert_response :success
  end

  def test_a_non_admin_is_refused
    @request.session[:user_id] = 2

    get :explain, :params => {:custom_field_id => @computed.id, :object_id => @issue.id}

    assert_response :forbidden
  end

  def test_a_regular_field_is_not_found
    get :explain, :params => {:custom_field_id => @input.id, :object_id => @issue.id}

    assert_response :not_found
  end

  def test_an_unknown_object_is_not_found
    get :explain, :params => {:custom_field_id => @computed.id, :object_id => 999_999}

    assert_response :not_found
  end

  private

  def create_field(name, format, formula = nil, computed = false)
    field = IssueCustomField.create!(
      :name => name, :field_format => format, :is_for_all => true,
      :is_computed => computed, :formula => formula
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end
end
