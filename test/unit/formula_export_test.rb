# frozen_string_literal: true

require 'tmpdir'
require File.expand_path('../test_helper', File.dirname(__FILE__))

class SmartCustomFieldFormulaExportTest < ActiveSupport::TestCase
  def setup
    @computed = IssueCustomField.create!(
      :name => 'Export computed', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '1 + 1'
    )
    @other = IssueCustomField.create!(
      :name => 'Export other', :field_format => 'int', :is_for_all => true,
      :is_computed => true, :formula => '2 + 2'
    )
    @regular = IssueCustomField.create!(
      :name => 'Export regular', :field_format => 'string', :is_for_all => true
    )
  end

  # --- dump -------------------------------------------------------------

  def test_dump_exports_computed_fields_only
    ids = SmartCustomField::FormulaExport.dump['custom_fields'].map { |entry| entry['id'] }

    assert_includes ids, @computed.id
    assert_not_includes ids, @regular.id
  end

  def test_dump_records_the_formula_and_the_type
    entry = entry_for(@computed)

    assert_equal '1 + 1', entry['formula']
    assert_equal true, entry['is_computed']
    assert_equal 'IssueCustomField', entry['type']
    assert_equal 'int', entry['field_format']
  end

  def test_dump_carries_the_format_version
    assert_equal SmartCustomField::FormulaExport::FORMAT_VERSION,
                 SmartCustomField::FormulaExport.dump['format_version']
  end

  def test_write_and_read_round_trip
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      SmartCustomField::FormulaExport.write_to(path)

      exported = SmartCustomField::FormulaExport.read(path)

      assert_equal SmartCustomField::FormulaExport.dump['custom_fields'].size, exported.size
      assert_equal '1 + 1', exported.find { |entry| entry['id'] == @computed.id }['formula']
    end
  end

  def test_read_rejects_an_unknown_format_version
    in_tmpdir do |dir|
      path = File.join(dir, 'broken.json')
      File.write(path, JSON.generate('format_version' => 99, 'custom_fields' => []))

      assert_raises(ArgumentError) { SmartCustomField::FormulaExport.read(path) }
    end
  end

  # --- diff -------------------------------------------------------------

  def test_diff_is_empty_when_the_file_matches_the_database
    assert_empty SmartCustomField::FormulaExport.diff(dump_entries)
  end

  def test_diff_reports_a_changed_formula
    entries = dump_entries
    entries.find { |entry| entry['id'] == @computed.id }['formula'] = '9 + 9'

    change = SmartCustomField::FormulaExport.diff(entries).find { |c| c.id == @computed.id }

    assert_equal :updated, change.action
    assert_equal '1 + 1', change.from_formula
    assert_equal '9 + 9', change.to_formula
  end

  def test_diff_reports_a_field_unknown_locally
    entries = dump_entries
    entries << { 'id' => 999_999, 'name' => 'Ghost', 'formula' => '1 + 1' }

    change = SmartCustomField::FormulaExport.diff(entries).find { |c| c.id == 999_999 }

    assert_equal :added, change.action
  end

  def test_diff_reports_a_computed_field_absent_from_the_file
    entries = dump_entries.reject { |entry| entry['id'] == @computed.id }

    change = SmartCustomField::FormulaExport.diff(entries).find { |c| c.id == @computed.id }

    assert_equal :removed, change.action
  end

  def test_diff_writes_nothing
    entries = dump_entries
    entries.each { |entry| entry['formula'] = '7 + 7' }

    SmartCustomField::FormulaExport.diff(entries)

    assert_equal '1 + 1', @computed.reload.formula
    assert_equal '2 + 2', @other.reload.formula
  end

  # --- import (dry run by default) --------------------------------------

  def test_import_without_write_leaves_every_row_untouched
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      write_file_with(path, @computed.id => '42 + 42')

      report = SmartCustomField::FormulaExport.import(path)

      assert_not report.written
      assert_equal 1, report.changes.size
      assert_empty report.results
      assert_equal '1 + 1', @computed.reload.formula
    end
  end

  def test_import_with_write_updates_the_formula
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      write_file_with(path, @computed.id => '42 + 42')

      report = SmartCustomField::FormulaExport.import(path, :write => true)

      assert_equal 1, report.applied.size
      assert_empty report.failed
      assert_equal '42 + 42', @computed.reload.formula
    end
  end

  def test_import_never_touches_the_name_nor_the_field_format
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      entries = dump_entries
      entry = entries.find { |e| e['id'] == @computed.id }
      entry['name'] = 'Renamed by the file'
      entry['field_format'] = 'string'
      entry['formula'] = '42 + 42'
      File.write(path, JSON.generate('format_version' => 1, 'custom_fields' => entries))

      SmartCustomField::FormulaExport.import(path, :write => true)

      field = @computed.reload
      assert_equal 'Export computed', field.name
      assert_equal 'int', field.field_format
      assert_equal '42 + 42', field.formula
    end
  end

  def test_import_keeps_the_old_formula_when_the_new_one_does_not_validate
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      write_file_with(path, @computed.id => 'not even valid ruby +')

      report = SmartCustomField::FormulaExport.import(path, :write => true)

      assert_equal 1, report.failed.size
      assert_empty report.applied
      assert_equal '1 + 1', @computed.reload.formula
    end
  end

  def test_import_never_creates_a_field_declared_in_the_file
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      entries = dump_entries
      entries << { 'id' => 999_999, 'name' => 'Ghost', 'formula' => '1 + 1' }
      File.write(path, JSON.generate('format_version' => 1, 'custom_fields' => entries))

      report = SmartCustomField::FormulaExport.import(path, :write => true)

      skipped = report.results.find { |result| result.change.id == 999_999 }
      assert_equal :skipped, skipped.status
      assert_nil CustomField.find_by(:id => 999_999)
    end
  end

  def test_import_never_deletes_a_field_absent_from_the_file
    in_tmpdir do |dir|
      path = File.join(dir, 'formulas.json')
      entries = dump_entries.reject { |entry| entry['id'] == @computed.id }
      File.write(path, JSON.generate('format_version' => 1, 'custom_fields' => entries))

      SmartCustomField::FormulaExport.import(path, :write => true)

      assert CustomField.exists?(@computed.id)
      assert_equal '1 + 1', @computed.reload.formula
    end
  end

  private

  def dump_entries
    # Deep copy: the test mutates the entries it gets back.
    Marshal.load(Marshal.dump(SmartCustomField::FormulaExport.dump['custom_fields']))
  end

  def entry_for(field)
    SmartCustomField::FormulaExport.dump['custom_fields'].find { |entry| entry['id'] == field.id }
  end

  def write_file_with(path, formulas_by_id)
    entries = dump_entries
    formulas_by_id.each do |id, formula|
      entries.find { |entry| entry['id'] == id }['formula'] = formula
    end
    File.write(path, JSON.generate('format_version' => 1, 'custom_fields' => entries))
  end

  def in_tmpdir(&block)
    Dir.mktmpdir('smart_custom_field', &block)
  end
end
