# frozen_string_literal: true

module SmartCustomField
  # Orders the computed fields of one save so that a field is computed after
  # every computed field its formula reads.
  #
  # A formula sees `cfs` as a snapshot of the values stored before the first
  # evaluation. Without an order, `total = cfs[subtotal] * cfs[rate]` read the
  # values written by the *previous* save: a chain settled only on the second
  # save, which is the kind of bug a user reports as "the total is one edit
  # behind". Computing the fields in dependency order and moving the snapshot
  # forward after each one settles the chain in a single save.
  #
  # Cycles are the validator's business (see FormulaCycle): a new one is
  # refused when the field is saved. This module only has to survive a cycle an
  # installation already carries.
  module ComputationOrder
    module_function

    # `fields` are CustomField records. Returns the same records, each one
    # placed after the computed fields its formula references. The incoming
    # order breaks every tie, so a save is deterministic.
    def sort(fields)
      return fields if fields.size < 2

      dependencies = dependencies_of(fields)
      ordered = []
      remaining = fields.dup

      until remaining.empty?
        remaining_ids = remaining.map(&:id)
        ready = remaining.select { |field| (dependencies[field.id] & remaining_ids).empty? }

        # Nothing is ready: what is left is a stored cycle, which cannot be
        # ordered. Refusing to save would make it impossible to repair from the
        # admin form, so the rest keeps the order it came in and the value
        # settles one save later, exactly as it did before this ordering
        # existed.
        return ordered + remaining if ready.empty?

        ordered.concat(ready)
        remaining -= ready
      end

      ordered
    end

    # Ids of the *computed* fields each formula reads. A reference to an
    # ordinary field is irrelevant here: its value cannot change during the
    # save that is being ordered.
    def dependencies_of(fields)
      known = fields.map(&:id)
      fields.each_with_object({}) do |field, hash|
        hash[field.id] = Evaluator.custom_field_ids(field.formula) & known
      end
    end

    private_class_method :dependencies_of
  end
end
