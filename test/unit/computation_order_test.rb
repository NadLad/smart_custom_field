# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A formula reads `cfs` as a snapshot of the values stored before the first
# evaluation, so the order the computed fields are evaluated in decides whether
# a chain settles in one save or one save behind. The ordering itself is pure:
# no database, no evaluation.
class SmartCustomFieldComputationOrderTest < ActiveSupport::TestCase
  def setup
    @first = field(1, '1')
    @second = field(2, 'cfs[1] * 2')
    @third = field(3, 'cfs[2] + 1')
  end

  def test_orders_a_chain_from_its_source
    assert_equal [1, 2, 3], ids(ordered(@third, @second, @first))
  end

  # Two fields that do not read each other keep the order they were handed in:
  # a save has to be deterministic, not merely correct.
  def test_keeps_the_incoming_order_between_independent_fields
    a = field(10, '1')
    b = field(11, '2')

    assert_equal [10, 11], ids(ordered(a, b))
    assert_equal [11, 10], ids(ordered(b, a))
  end

  # Only a *computed* field can change during this save, and `sort` is only
  # ever handed computed fields: a reference to an id outside that list (an
  # ordinary field, or a computed one this object does not carry) is ignored
  # rather than treated as a dependency nothing could satisfy.
  def test_a_reference_outside_the_given_fields_is_ignored
    reader = field(21, 'cfs[20] * 2')

    assert_equal [21], ids(ordered(reader))
  end

  # A cycle is refused when the field is saved, but an installation can already
  # carry one. Refusing to order it would make the save impossible, so the rest
  # keeps the incoming order and settles one save later.
  def test_a_stored_cycle_keeps_the_incoming_order
    a = field(30, 'cfs[31] + 1')
    b = field(31, 'cfs[30] + 1')

    assert_equal [30, 31], ids(ordered(a, b))
  end

  def test_a_single_field_is_returned_untouched
    assert_equal [40], ids(ordered(field(40, '1')))
    assert_equal [], ids(SmartCustomField::ComputationOrder.sort([]))
  end

  private

  # Custom fields that only exist in memory: the ordering reads the id and the
  # formula, nothing else.
  def field(id, formula)
    CustomField.new(:id => id, :formula => formula, :is_computed => true)
  end

  def ordered(*fields)
    SmartCustomField::ComputationOrder.sort(fields)
  end

  def ids(fields)
    fields.map(&:id)
  end
end
