# frozen_string_literal: true

require 'digest'
require 'json'

module SmartCustomField
  # Fingerprint of everything a computed value depends on.
  #
  # A save recomputes every computed field of the object, even when nothing the
  # formula reads has moved: a bulk update, an import or a workflow that
  # touches one attribute then pays for every evaluation and for every custom
  # value write. Hashing the inputs lets that save skip the work entirely.
  #
  # The digest is only ever returned when the formula is fully reproducible:
  #   - it must not read the clock, the current user or a random source, or the
  #     same inputs would legitimately give another result;
  #   - it must not read another record, whose own changes are invisible here.
  # In both cases `for` returns nil, which means "always compute".
  module ComputationDigest
    # Columns that move on their own during a save, or that describe the row
    # rather than its content: including them would make every digest differ
    # from the one stored by the previous save.
    IGNORED_ATTRIBUTES = %w[updated_on created_on lock_version].freeze

    # Anything that makes the same inputs produce another value.
    VOLATILE_PATTERNS = [
      /\bDate\s*\.\s*(?:today|current|new)\b/,
      /\bDateTime\s*\.\s*(?:now|current|new)\b/,
      /\bTime\s*\.\s*(?:now|current|new)\b/,
      /\bUser\s*\.\s*current\b/,
      /\bSecureRandom\b/,
      /\bRandom\b/,
      /\brand\b/,
      /\bsrand\b/
    ].freeze

    module_function

    # Digest for `field` on `object`, given the cast values exposed to the
    # formula as `cfs`. Returns nil when this formula must always be evaluated.
    def for(field, object, values)
      return nil if object.nil? || object.new_record?

      source = field.formula.to_s
      return nil if volatile?(source)
      return nil unless self_contained?(source, field)

      Digest::SHA256.hexdigest(JSON.generate(payload(field, object, values)))
    end

    def volatile?(source)
      VOLATILE_PATTERNS.any? { |pattern| pattern.match?(source) }
    end

    # True when the formula only reads the object's own attributes and the
    # custom field values handed to it: everything else can change without this
    # object being saved, so a matching digest would prove nothing.
    def self_contained?(source, field)
      analysis = StaticAnalyzer.analyze(source, field.class.customized_class)
      analysis.self_contained?
    end

    def payload(field, object, values)
      {
        'formula' => field.formula.to_s,
        'attributes' => attributes_for(object),
        'values' => referenced_values(field, values)
      }
    end

    # Every own attribute, not only the ones the formula seems to read:
    # guessing wrong here would serve a stale value, and a false positive only
    # costs one evaluation. Keys are sorted and values stringified so that the
    # hash does not depend on column order or on a value's class.
    def attributes_for(object)
      object.attributes.reject { |name, _value| IGNORED_ATTRIBUTES.include?(name) }
            .sort.to_h
            .transform_values { |value| value.nil? ? nil : value.to_s }
    end

    def referenced_values(field, values)
      Evaluator.custom_field_ids(field.formula).sort.map do |id|
        value = values[id]
        [id, value.nil? ? nil : value.to_s]
      end
    end
  end
end
