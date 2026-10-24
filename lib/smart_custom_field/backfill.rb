# frozen_string_literal: true

module SmartCustomField
  # Fills in the stored value of every computed custom field on the objects
  # that were never saved since the field was created.
  #
  # A computed field only gets a value when its object is saved, so a field
  # added to a populated installation stays empty until every issue is touched
  # again. This walks the objects and fills them in.
  #
  # Writes go to `custom_values.value` and nothing else: never through
  # `object.save`, which would bump `updated_on`, run workflow rules, notify
  # watchers and create journals. A formula produces a derived value, not an
  # edit, and backfilling 10 000 issues must not look like 10 000 edits.
  module Backfill
    DEFAULT_BATCH_SIZE = 500

    # Returned by `compute` when the formula raised, so a legitimately empty
    # result is never mistaken for a failure.
    ERROR = Object.new.freeze

    # Associations formulas commonly read, preloaded so the walk does not
    # issue one query per object.
    INCLUDES = {
      'Issue' => [:project, :tracker]
    }.freeze

    Report = Struct.new(:scanned, :changed, :failed, :errors, :warnings,
                        :keyword_init => true)

    module_function

    def new_report
      Report.new(:scanned => 0, :changed => 0, :failed => 0, :errors => [], :warnings => [])
    end

    # Recomputes every computed value. Nothing is written unless `apply` is
    # true; the report then describes what a dry run would have changed.
    def run(apply: false, batch_size: DEFAULT_BATCH_SIZE)
      report = new_report
      fields_by_model = computed_fields_by_model
      return report if fields_by_model.empty?

      all_fields = fields_by_model.values.flatten
      warn_about_user_current(all_fields, report)
      warn_about_multiple_fields(all_fields, report)

      fields_by_model.each do |model, fields|
        scope = INCLUDES.key?(model.name) ? model.includes(*INCLUDES[model.name]) : model.all
        scope.find_each(:batch_size => batch_size) do |object|
          report.scanned += 1
          FormulaHelpers.with_cache { backfill_object(object, fields, apply, report) }
        end
      end

      report
    end

    # Computed fields grouped by the class they belong to. A field whose type
    # has no customized class cannot be evaluated and is ignored.
    def computed_fields_by_model
      CustomField.where(:is_computed => true).to_a
                 .group_by { |field| field.class.customized_class }
                 .reject { |model, _fields| model.nil? }
    end

    def backfill_object(object, fields, apply, report)
      # `custom_field_values` is the list of fields this object can carry
      # (project and tracker filtered for an issue): a field Redmine would not
      # have created a value for is not ours to fill either.
      available_ids = object.custom_field_values.map(&:custom_field_id)
      values = Evaluator.values_for(object)

      # Dependency order, so a field reading another computed field sees the
      # value this run produced instead of the one stored before it.
      ComputationOrder.sort(fields).each do |field|
        next unless available_ids.include?(field.id)
        # A multi-valued field stores one row per value; that write path is
        # Redmine's, and it is announced as skipped by the run.
        next if field.multiple?

        new_value = compute(field, object, values, report)
        next if new_value.equal?(ERROR)

        # Move the snapshot forward even on a dry run: the report has to
        # describe what an apply would do, chains included.
        values[field.id] = Evaluator.cfs_value(field, new_value) unless new_value.is_a?(Array)

        # Comparing the strings rather than the records keeps a dry run free of
        # side effects and treats "no row" and "empty row" as the same thing.
        next if stored_value(object, field).to_s == new_value.to_s

        report.changed += 1
        next unless apply

        persist(object, field, new_value, report)
      end
    end

    # The value currently stored for `field`, or nil when the object has none.
    # `custom_values` already carries a *built* record for every available
    # field (Redmine creates them on demand), so a new_record? one counts as
    # absent.
    def stored_value(object, field)
      custom_value = object.custom_values.detect { |cv| cv.custom_field_id == field.id }
      return nil if custom_value.nil? || custom_value.new_record?

      custom_value.value
    end

    def compute(field, object, values, report)
      Evaluator.cast(field, Evaluator.evaluate(field.formula, object, values))
    rescue *FormulaValidator::RESCUABLE => e
      report.failed += 1
      report.errors << "#{label(object)} / #{field.name}: #{e.message}"
      ERROR
    end

    def persist(object, field, new_value, report)
      custom_value = object.custom_values.detect { |cv| cv.custom_field_id == field.id }
      custom_value ||= object.custom_values.build(:custom_field => field, :customized => object)
      custom_value.value = new_value
      return if custom_value.save

      report.failed += 1
      report.errors << "#{label(object)} / #{field.name}: " \
                       "#{custom_value.errors.full_messages.join(', ')}"
    end

    def label(object)
      "#{object.class.name} ##{object.id}"
    end

    # A formula calling `User.current` produces a different value depending on
    # who saved the object last, so a backfill run by the wrong account freezes
    # the wrong answer into every row.
    def warn_about_user_current(fields, report)
      risky = fields.select { |field| field.formula.to_s.match?(/\bUser\.current\b/) }
      return if risky.empty?

      report.warnings << "#{risky.size} formula(s) read User.current: the value depends on the " \
                         'account running this task. Set USER_ID to the account that should own ' \
                         'the result, or those fields will be filled for AnonymousUser.'
    end

    # A multi-valued field stores one custom_values row per value, and splitting
    # a result into rows is Redmine's own write path. Rather than reimplement it
    # (and risk writing a half-filled list), those fields are skipped and said
    # so.
    def warn_about_multiple_fields(fields, report)
      multiple = fields.select(&:multiple?)
      return if multiple.empty?

      report.warnings << "#{multiple.size} computed field(s) accept several values: they are " \
                         'skipped by this task and still need a regular save.'
    end
  end
end
