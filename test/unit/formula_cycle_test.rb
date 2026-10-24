# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldFormulaCycleTest < ActiveSupport::TestCase
  def computed_field(name, formula = '1')
    IssueCustomField.create!(
      :name => name,
      :field_format => 'int',
      :is_for_all => true,
      :is_computed => true,
      :formula => formula
    )
  end

  def test_detect_returns_nil_for_an_acyclic_formula
    first = computed_field('Cycle first')
    second = computed_field('Cycle second', "cfs[#{first.id}] + 1")

    assert_nil SmartCustomField::FormulaCycle.detect(second, "cfs[#{first.id}] * 2")
  end

  def test_detect_reports_a_self_reference
    field = computed_field('Cycle self')

    cycle = SmartCustomField::FormulaCycle.detect(field, "cfs[#{field.id}]")

    assert_equal [field.id, field.id], cycle
  end

  def test_detect_reports_a_two_field_cycle
    first = computed_field('Cycle two a')
    second = computed_field('Cycle two b', "cfs[#{first.id}]")

    cycle = SmartCustomField::FormulaCycle.detect(first, "cfs[#{second.id}]")

    assert_equal [first.id, second.id, first.id], cycle
  end

  def test_detect_reports_a_longer_cycle
    first = computed_field('Cycle three a')
    second = computed_field('Cycle three b', "cfs[#{first.id}]")
    third = computed_field('Cycle three c', "cfs[#{second.id}]")

    # `first` would read `third`, which reads `second`, which reads `first`:
    # the walk runs first -> third -> second -> first.
    cycle = SmartCustomField::FormulaCycle.detect(first, "cfs[#{third.id}]")

    assert_equal [first.id, third.id, second.id, first.id], cycle
  end

  def test_detect_ignores_a_field_of_another_type
    project_field = ProjectCustomField.first
    assert_not_nil project_field, 'fixtures must provide a project custom field'
    issue_field = computed_field('Cycle other type')

    assert_nil SmartCustomField::FormulaCycle.detect(issue_field, "cfs[#{project_field.id}]")
  end

  def test_validator_rejects_a_new_cycle
    first = computed_field('Validator cycle a')
    second = computed_field('Validator cycle b', "cfs[#{first.id}]")

    first.formula = "cfs[#{second.id}] * 2"

    assert_invalid first
    assert_match(/circular dependency/i, first.errors[:formula].join)
    assert_match(/#{first.id} -> #{second.id} -> #{first.id}/, first.errors[:formula].join)
  end

  def test_validator_rejects_a_self_reference
    field = computed_field('Validator self')
    field.formula = "cfs[#{field.id}] + 1"

    assert_invalid field
    assert_match(/circular dependency/i, field.errors[:formula].join)
  end

  # A field whose stored formula already loops must stay saveable: the loop
  # predates this save, and refusing it would lock the field out of the admin
  # form that is the only place it can be fixed.
  def test_validator_tolerates_a_cycle_already_stored
    first = computed_field('Legacy cycle a')
    second = computed_field('Legacy cycle b', "cfs[#{first.id}]")
    first.update_column(:formula, "cfs[#{second.id}]")
    first.reload

    # The loop is really there, detection just reports it as pre-existing.
    assert_not_nil SmartCustomField::FormulaCycle.detect(first, first.formula)
    assert_not_nil SmartCustomField::FormulaCycle.stored_cycle(first)

    assert_valid first
  end

  def test_validator_accepts_a_chain_that_is_not_a_cycle
    first = computed_field('Chain a')
    second = computed_field('Chain b', "cfs[#{first.id}]")
    third = computed_field('Chain c', "cfs[#{second.id}]")

    assert_nil SmartCustomField::FormulaCycle.detect(third, third.formula)
    assert_valid third
  end

  def test_validator_accepts_a_formula_that_reads_a_shared_input
    shared = computed_field('Shared input')
    first = computed_field('Shared reader a', "cfs[#{shared.id}]")
    second = computed_field('Shared reader b', "cfs[#{shared.id}]")

    # Two fields reading the same input is a diamond, not a cycle.
    assert_nil SmartCustomField::FormulaCycle.detect(first, first.formula)
    assert_nil SmartCustomField::FormulaCycle.detect(second, second.formula)
  end

  private

  def assert_valid(record)
    record.valid?
    assert_empty record.errors.full_messages
  end

  def assert_invalid(record)
    assert_not record.valid?
  end
end
