# frozen_string_literal: true

# Fingerprint of the inputs the last computation of a computed field saw.
#
# A save whose inputs still hash to the same digest skips the evaluation
# entirely: the stored value cannot have changed, and rewriting it would make
# an untouched object look edited.
class AddSmartCustomFieldComputations < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:smart_custom_field_computations)

    create_table :smart_custom_field_computations do |t|
      t.string :customized_type, :null => false
      t.bigint :customized_id, :null => false
      t.bigint :custom_field_id, :null => false
      t.string :input_digest, :null => false
      t.timestamps
    end

    # One row per field and per object: the digest is a cache entry, not a log.
    add_index :smart_custom_field_computations,
              [:customized_type, :customized_id, :custom_field_id],
              :unique => true, :name => 'index_scf_computations_unique'
    add_index :smart_custom_field_computations, :custom_field_id,
              :name => 'index_scf_computations_on_custom_field'
  end

  def down
    drop_table :smart_custom_field_computations if table_exists?(:smart_custom_field_computations)
  end
end
