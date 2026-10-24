# frozen_string_literal: true

# Digest of the inputs the last computation of one computed custom field saw
# on one object.
#
# The row is a cache entry, never a source of truth: it is written after a
# successful computation, read before the next one, and its absence only costs
# one extra evaluation. Anything that cannot be fingerprinted reliably (a
# volatile formula, a formula reading another object) simply has no row.
class SmartCustomFieldComputation < ApplicationRecord
  self.table_name = 'smart_custom_field_computations'

  validates :customized_type, :customized_id, :custom_field_id, :input_digest,
            :presence => true
end
