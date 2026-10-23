# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldStaticAnalyzerTest < ActiveSupport::TestCase
  def test_a_valid_attribute_is_not_reported
    result = SmartCustomField::StaticAnalyzer.analyze('estimated_hours * 2', Issue)

    assert_empty result.unknown_methods
    assert_empty result.warnings
  end

  def test_a_misspelled_attribute_is_reported
    result = SmartCustomField::StaticAnalyzer.analyze('estimted_hours * 2', Issue)

    assert_includes result.unknown_methods, 'estimted_hours'
  end

  # The case the evaluator cannot catch: `project` is nil on a blank instance,
  # so the NoMethodError looks exactly like the expected nil-receiver one.
  def test_a_misspelled_attribute_behind_a_nil_association_is_reported
    result = SmartCustomField::StaticAnalyzer.analyze('project.estimted_hours', Issue)

    assert_includes result.unknown_methods, 'estimted_hours'
  end

  def test_a_call_on_self_is_checked
    result = SmartCustomField::StaticAnalyzer.analyze('self.estimted_hours', Issue)

    assert_includes result.unknown_methods, 'estimted_hours'
  end

  def test_a_valid_call_on_self_is_not_reported
    result = SmartCustomField::StaticAnalyzer.analyze('self.estimated_hours || 0', Issue)

    assert_empty result.unknown_methods
  end

  def test_cfs_references_are_not_reported_and_are_listed
    result = SmartCustomField::StaticAnalyzer.analyze('cfs[1] * 2 + cfs[2]', Issue)

    assert_empty result.unknown_methods
    assert_equal [1, 2], result.referenced_ids
  end

  def test_the_inter_object_helpers_are_not_reported
    result = SmartCustomField::StaticAnalyzer.analyze('cf(project, 1) + (parent&.cfs[2] || 0)', Issue)

    assert_empty result.unknown_methods
  end

  def test_a_syntax_error_is_reported_without_raising
    result = SmartCustomField::StaticAnalyzer.analyze('1 +', Issue)

    assert_not result.valid_syntax?
    assert_not_nil result.syntax_error
    assert(result.warnings.any? { |warning| warning.start_with?('syntax error') })
  end

  def test_reading_user_current_is_reported
    result = SmartCustomField::StaticAnalyzer.analyze('User.current.admin? ? 1 : 0', Issue)

    assert result.uses_current_user
    assert(result.warnings.any? { |warning| warning.include?('User.current') })
  end

  def test_the_method_check_is_skipped_without_a_model_class
    result = SmartCustomField::StaticAnalyzer.analyze('estimted_hours * 2', nil)

    assert_empty result.unknown_methods
  end

  # Advisory means advisory: a warning must never turn into a validation error,
  # otherwise a working formula becomes impossible to re-save.
  def test_the_analysis_never_blocks_a_save
    field = IssueCustomField.new(
      :name => 'Advisory only', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => 'project.estimted_hours'
    )

    assert field.valid?, field.errors.full_messages.join(', ')
    assert_includes SmartCustomField::StaticAnalyzer.for_field(field).unknown_methods,
                    'estimted_hours'
  end

  def test_unknown_references_reports_ids_of_another_type
    field = IssueCustomField.create!(
      :name => 'Refs', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '1 + 1'
    )
    other = ProjectCustomField.create!(
      :name => 'Project ref', :field_format => 'int',
      :is_computed => true, :formula => '1 + 1'
    )
    field.update_column(:formula, "cfs[#{other.id}]")

    assert_equal [other.id], SmartCustomField::StaticAnalyzer.unknown_references(field)
  end

  def test_unknown_references_is_empty_when_every_id_exists
    field = IssueCustomField.create!(
      :name => 'Refs ok', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '1 + 1'
    )
    other = IssueCustomField.create!(
      :name => 'Issue ref', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '1 + 1'
    )
    field.update_column(:formula, "cfs[#{other.id}]")

    assert_empty SmartCustomField::StaticAnalyzer.unknown_references(field)
  end
end
