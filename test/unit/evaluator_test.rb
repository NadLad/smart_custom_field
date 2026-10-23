# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldEvaluatorTest < ActiveSupport::TestCase
  FakeObject = Struct.new(:estimated_hours, :project_id)
  FakeRecord = Struct.new(:id)

  def setup
    @object = FakeObject.new(4, 7)
  end

  def test_custom_field_ids_extracts_referenced_ids_once
    assert_equal [12, 13], SmartCustomField::Evaluator.custom_field_ids('cfs[12] * 2 + cfs[13] + cfs[12]')
  end

  def test_custom_field_ids_returns_empty_array_without_placeholder
    assert_equal [], SmartCustomField::Evaluator.custom_field_ids('1 + 2')
  end

  def test_evaluate_exposes_cfs_hash
    assert_equal 16, SmartCustomField::Evaluator.evaluate('cfs[1] * 2 + cfs[2]', @object, 1 => 3, 2 => 10)
  end

  def test_evaluate_binds_self_to_the_customized_object
    assert_equal 8, SmartCustomField::Evaluator.evaluate('(self.estimated_hours || 0) * 2', @object)
  end

  def test_evaluate_supports_multiline_formulas
    formula = "if cfs[1].zero?\n  1\nelse\n  2\nend"

    assert_equal 1, SmartCustomField::Evaluator.evaluate(formula, @object, 1 => 0)
    assert_equal 2, SmartCustomField::Evaluator.evaluate(formula, @object, 1 => 5)
  end

  def test_evaluate_raises_on_invalid_code
    assert_raises(NameError) { SmartCustomField::Evaluator.evaluate('unknown_method', @object) }
  end

  def test_cast_int_truncates_to_integer
    assert_equal '42', SmartCustomField::Evaluator.cast(custom_field('int'), 42.9)
  end

  def test_cast_bool_maps_booleans
    assert_equal '1', SmartCustomField::Evaluator.cast(custom_field('bool'), true)
    assert_equal '0', SmartCustomField::Evaluator.cast(custom_field('bool'), false)
  end

  def test_cast_uses_the_id_of_records
    assert_equal '5', SmartCustomField::Evaluator.cast(custom_field('user'), FakeRecord.new(5))
  end

  def test_cast_string_passes_through
    assert_equal 'hello', SmartCustomField::Evaluator.cast(custom_field('string'), 'hello')
  end

  def test_cast_nil_becomes_empty_string
    assert_equal '', SmartCustomField::Evaluator.cast(custom_field('string'), nil)
  end

  def test_cast_maps_arrays
    assert_equal %w(1 2), SmartCustomField::Evaluator.cast(custom_field('int'), [1, 2])
  end

  private

  def custom_field(format)
    CustomField.new(:field_format => format)
  end
end
