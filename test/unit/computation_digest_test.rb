# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))

# A save that changes nothing the formula reads must not re-evaluate it; a
# formula whose result is not reproducible from its inputs must always be
# evaluated. The counter in the formulas below is the only way to tell a skip
# from a computation that happens to produce the same value.
class SmartCustomFieldComputationDigestTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :custom_fields,
           :custom_values, :versions, :projects_trackers, :enabled_modules

  def setup
    $scf_digest_evaluations = 0
    @plain = create_field('Digest input', 'int')
    @computed = create_field('Digest output', 'int',
                             :is_computed => true,
                             :formula => counting("cfs[#{@plain.id}] * 2"))
    @issue = Issue.find(1)
    @issue.custom_field_values = {@plain.id.to_s => '5'}
    assert @issue.save, @issue.errors.full_messages.join(', ')
    $scf_digest_evaluations = 0
  end

  def teardown
    $scf_digest_evaluations = nil
  end

  def test_an_unchanged_save_does_not_evaluate_the_formula
    issue = Issue.find(@issue.id)

    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal 0, $scf_digest_evaluations
    assert_equal '10', Issue.find(@issue.id).custom_field_value(@computed)
  end

  # What the skip buys: nothing is written at all, so a derived value never
  # makes an untouched object look edited.
  def test_a_skipped_save_leaves_the_object_untouched
    issue = Issue.find(@issue.id)
    updated_on = issue.updated_on
    journals = issue.journals.count

    assert issue.save, issue.errors.full_messages.join(', ')

    reloaded = Issue.find(@issue.id)
    assert_equal updated_on, reloaded.updated_on
    assert_equal journals, reloaded.journals.count
  end

  def test_a_changed_input_recomputes
    issue = Issue.find(@issue.id)
    issue.custom_field_values = {@plain.id.to_s => '7'}

    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal 1, $scf_digest_evaluations
    assert_equal '14', Issue.find(@issue.id).custom_field_value(@computed)
  end

  def test_a_changed_formula_recomputes
    @computed.update_column(:formula, counting("cfs[#{@plain.id}] * 3"))

    issue = Issue.find(@issue.id)
    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal 1, $scf_digest_evaluations
    assert_equal '15', Issue.find(@issue.id).custom_field_value(@computed)
  end

  # The formula reads an attribute of the object itself, which no custom value
  # digest would catch. The digest covers every own attribute, so a subject
  # change recomputes each computed field of the object, not only the one that
  # reads it: over-recomputing costs one evaluation, under-recomputing would
  # serve a stale value.
  def test_a_changed_attribute_recomputes
    field = create_field('Digest subject', 'int', :is_computed => true,
                         :formula => counting('self.subject.to_s.length'))
    subject = 'A longer subject'

    issue = Issue.find(@issue.id)
    issue.subject = subject
    assert issue.save, issue.errors.full_messages.join(', ')

    assert_equal subject.length.to_s, Issue.find(@issue.id).custom_field_value(field)

    # The digest written by that save describes the new attributes: saving the
    # same object again moves nothing and must evaluate nothing.
    $scf_digest_evaluations = 0
    reloaded = Issue.find(@issue.id)
    assert reloaded.save, reloaded.errors.full_messages.join(', ')
    assert_equal 0, $scf_digest_evaluations
  end

  def test_a_volatile_formula_is_never_skipped
    field = create_field('Digest volatile', 'int', :is_computed => true,
                         :formula => counting('rand(1_000_000)'))
    $scf_digest_evaluations = 0

    2.times do
      issue = Issue.find(@issue.id)
      assert issue.save, issue.errors.full_messages.join(', ')
    end

    assert_equal 2, $scf_digest_evaluations
    assert_nil SmartCustomFieldComputation.find_by(:custom_field_id => field.id),
               'a volatile formula must not leave a digest behind'
  end

  def test_a_formula_reading_another_record_is_never_skipped
    field = create_field('Digest related', 'int', :is_computed => true,
                         :formula => counting("cf(project, #{@plain.id}).to_i * 2"))
    $scf_digest_evaluations = 0

    2.times do
      issue = Issue.find(@issue.id)
      assert issue.save, issue.errors.full_messages.join(', ')
    end

    assert_equal 2, $scf_digest_evaluations
    assert_nil SmartCustomFieldComputation.find_by(:custom_field_id => field.id),
               'a formula reading another record must not leave a digest behind'
  end

  def test_a_new_record_is_always_computed
    copy = Issue.find(@issue.id).dup
    copy.subject = 'Digest copy'
    $scf_digest_evaluations = 0

    assert copy.save, copy.errors.full_messages.join(', ')

    assert_equal 1, $scf_digest_evaluations
  end

  def test_the_digest_is_stored_for_the_object
    record = SmartCustomFieldComputation.find_by(
      :customized_type => 'Issue',
      :customized_id => @issue.id,
      :custom_field_id => @computed.id
    )

    assert record, 'the digest of the computation should have been stored'
    assert_equal 64, record.input_digest.length
  end

  private

  def counting(expression)
    "$scf_digest_evaluations += 1; #{expression}"
  end

  def create_field(name, format, options = {})
    field = IssueCustomField.create!(
      {:name => name, :field_format => format, :is_for_all => true}.merge(options)
    )
    # Issue#available_custom_fields intersects the project fields with the
    # tracker fields: without the join rows the field is invisible.
    field.trackers = Tracker.all.to_a
    field
  end
end
