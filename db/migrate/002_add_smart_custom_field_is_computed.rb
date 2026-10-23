# frozen_string_literal: true

class AddSmartCustomFieldIsComputed < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:custom_fields, :is_computed)
      add_column :custom_fields, :is_computed, :boolean, :default => false, :null => false
    end
  end

  def down
    remove_column :custom_fields, :is_computed if column_exists?(:custom_fields, :is_computed)
  end
end
