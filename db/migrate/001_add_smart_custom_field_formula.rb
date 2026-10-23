# frozen_string_literal: true

# Column names match computed_custom_field on purpose: the plugin can take
# over an existing installation without migrating any data.
class AddSmartCustomFieldFormula < ActiveRecord::Migration[8.1]
  def up
    add_column :custom_fields, :formula, :text unless column_exists?(:custom_fields, :formula)
  end

  def down
    remove_column :custom_fields, :formula if column_exists?(:custom_fields, :formula)
  end
end
