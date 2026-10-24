# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Recomputes the value of every computed custom field before the object is
    # validated, so the fresh value goes through Redmine's own custom value
    # validation and gets persisted by `save_custom_field_values`.
    module CustomizablePatch
      extend ActiveSupport::Concern

      included do
        before_validation :compute_computed_custom_fields
        after_save :store_computation_digests
      end

      # Values exposed to formulas as `cfs[<id>]`, cast to the type of their
      # custom field so that `cfs[12] * 2` works on an integer field.
      #
      # Public, and therefore reachable from another object: `parent&.cfs[5]`
      # or `assigned_to.cfs[3]`.
      def cfs
        FormulaHelpers.cfs_for(self)
      end

      # Value of one custom field of any customizable object, cast like `cfs`:
      # `cf(project, 12)`. Defined on the models rather than on the evaluator so
      # a formula can call it without a receiver.
      def cf(object, custom_field_id)
        FormulaHelpers.cf(object, custom_field_id)
      end

      # Aggregations over a collection, for a formula that totals a set of
      # issues: `cf_sum(children, 7)`, `cf_avg(subtree, 7)`, `cf_max(children, 7)`.
      # Unset values are ignored, and a collection or a tree bigger than the
      # caps raises instead of scanning the table.
      def cf_sum(collection, custom_field_id)
        FormulaHelpers.cf_sum(collection, custom_field_id)
      end

      def cf_avg(collection, custom_field_id)
        FormulaHelpers.cf_avg(collection, custom_field_id)
      end

      def cf_min(collection, custom_field_id)
        FormulaHelpers.cf_min(collection, custom_field_id)
      end

      def cf_max(collection, custom_field_id)
        FormulaHelpers.cf_max(collection, custom_field_id)
      end

      # The issues below this one, itself excluded: `cf_sum(subtree, 7)`.
      def subtree
        FormulaHelpers.subtree(self)
      end

      # A computed value is derived, never chosen: the ids of computed fields
      # are dropped from whatever is assigned from the outside, so a crafted
      # POST cannot store a value the next save would have to fight with. This
      # also closes the hole left by a formula that raises, where no new value
      # is written and a submitted one would otherwise survive.
      #
      # The computation writes its own results through `FormulaComputation`.
      def custom_field_values=(values)
        super(FormulaComputation.writing? ? values : without_computed_ids(values))
      end

      private

      # Drops the ids of computed fields from an assignment. The hash is
      # rebuilt as a plain Hash: the caller may hand an
      # ActionController::Parameters, and Redmine stringifies the keys itself.
      def without_computed_ids(values)
        return values unless values.respond_to?(:each_pair)

        blocked = computed_custom_field_ids
        return values if blocked.empty?

        values.each_pair.with_object({}) do |(key, value), kept|
          kept[key] = value unless blocked.include?(key.to_s)
        end
      end

      def computed_custom_field_ids
        custom_field_values.select { |value| value.custom_field.is_computed? }
                           .map { |value| value.custom_field_id.to_s }
      end

      def compute_computed_custom_fields
        @smart_custom_field_digests = nil
        computed = custom_field_values.select { |value| value.custom_field.is_computed? }
        return if computed.empty?

        # One cache per save: the values of a related object are read once,
        # and the next save starts from a clean slate.
        FormulaHelpers.with_cache { compute_into(computed) }
      end

      def compute_into(computed)
        # Read once: every field of this save sees the same snapshot, exactly
        # as it did when the evaluation called `cfs` itself.
        values = cfs
        stored = stored_computation_digests(computed.map(&:custom_field_id))
        new_values = {}
        digests = {}

        computed.each do |custom_field_value|
          field = custom_field_value.custom_field
          digest = ComputationDigest.for(field, self, values)

          # Nothing this formula reads has moved since the value was stored:
          # rewriting it would mark an untouched object as edited and pay for
          # an evaluation that cannot produce anything new.
          next if digest && stored[field.id] == digest

          begin
            result = Evaluator.evaluate(field.formula, self, values)
            new_values[field.id] = Evaluator.cast(field, result)
            digests[field.id] = digest if digest
          rescue *FormulaValidator::RESCUABLE => e
            errors.add(:base, I18n.t(:error_while_formula_computing,
                                     :custom_field_name => field.name,
                                     :message => e.message))
          end
        end

        # A formula that raised stores no digest: the next save has to try
        # again instead of trusting a value it never wrote.
        @smart_custom_field_digests = digests

        # `custom_field_values=` flags the values as changed, which makes
        # Redmine re-validate and re-save them. The window tells the setter
        # this assignment is the computation itself, not a client edit.
        FormulaComputation.writing { self.custom_field_values = new_values } if new_values.any?
      end

      def stored_computation_digests(field_ids)
        return {} if new_record? || field_ids.empty?

        SmartCustomFieldComputation
          .where(:customized_type => computation_owner_type, :customized_id => id,
                 :custom_field_id => field_ids)
          .pluck(:custom_field_id, :input_digest)
          .to_h
      end

      # Runs inside the save transaction, after the value has been written: a
      # digest is only worth storing once the computation it describes landed.
      def store_computation_digests
        digests = @smart_custom_field_digests
        return if digests.nil? || digests.empty?

        digests.each do |field_id, digest|
          record = SmartCustomFieldComputation.find_or_initialize_by(
            :customized_type => computation_owner_type,
            :customized_id => id,
            :custom_field_id => field_id
          )
          next if record.persisted? && record.input_digest == digest

          record.input_digest = digest
          # A digest is a cache entry: failing to store it costs one extra
          # evaluation later, never a wrong value, so it must not fail the save.
          next if record.save

          Rails.logger.warn(
            "[smart_custom_field] could not store the computation digest of " \
            "#{computation_owner_type}##{id}/#{field_id}: " \
            "#{record.errors.full_messages.join(', ')}"
          )
        end
      ensure
        @smart_custom_field_digests = nil
      end

      # Enumeration is subclassed (IssuePriority...): the digests are keyed on
      # the base class so a field finds them whatever the concrete class is.
      def computation_owner_type
        self.class.base_class.name
      end
    end
  end
end
