// Expression builder for computed custom field formulas.
//
// It is a one-way generator: condition rows produce Ruby source that is
// inserted into the `formula` textarea, which stays the source of truth. The
// rows are never re-read from the text, so editing the formula by hand cannot
// corrupt the builder - it simply stops matching what the rows describe.
(function () {
  'use strict';

  var NUMERIC = {int: true, float: true};
  var DATE = {date: 'Date', datetime: 'Time'};
  var OPERATORS = ['==', '!=', '>', '>=', '<', '<='];
  var BOOLEAN_OPERATORS = ['==', '!='];

  function onReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback);
    } else {
      callback();
    }
  }

  function escapeString(value) {
    return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  }

  function optionValue(select) {
    var option = select.options[select.selectedIndex];
    return option ? option.value : '';
  }

  function optionFormat(select) {
    var option = select.options[select.selectedIndex];
    return option ? (option.getAttribute('data-format') || 'string') : 'string';
  }

  function appendOptions(select, pairs) {
    pairs.forEach(function (pair) {
      var option = document.createElement('option');
      option.value = pair[0];
      option.textContent = pair[1];
      select.appendChild(option);
    });
    return select;
  }

  onReady(function () {
    var builder = document.getElementById('smart-custom-field-builder');
    var template = document.getElementById('smart-custom-field-builder-fields');
    var rows = document.getElementById('smart-custom-field-builder-rows');
    var addLink = document.getElementById('smart-custom-field-builder-add');
    var applyLink = document.getElementById('smart-custom-field-builder-apply');
    var textarea = document.getElementById('custom_field_formula');
    if (!builder || !template || !rows || !addLink || !applyLink || !textarea) {
      return;
    }
    // Nothing to build a condition on: a field with no sibling has no
    // reference to offer, and the plain field list above is enough.
    if (template.options.length === 0) {
      builder.style.display = 'none';
      return;
    }

    function fieldSelect() {
      var select = document.createElement('select');
      for (var i = 0; i < template.options.length; i += 1) {
        select.appendChild(template.options[i].cloneNode(true));
      }
      return select;
    }

    function valueWidget() {
      var input = document.createElement('input');
      input.type = 'text';
      input.size = 20;
      return input;
    }

    // The operator list and the value widget depend on the field format: a
    // boolean only knows equality and its value is true or false, never free
    // text that would silently compare as a string.
    function refreshRow(row) {
      var format = optionFormat(row.field);
      var wanted = format === 'bool' ? BOOLEAN_OPERATORS : OPERATORS;
      var current = optionValue(row.operator);

      row.operator.textContent = '';
      appendOptions(row.operator, wanted.map(function (operator) {
        return [operator, operator];
      }));
      if (wanted.indexOf(current) !== -1) {
        row.operator.value = current;
      }

      if (format === 'bool' && row.value.tagName === 'INPUT') {
        var select = appendOptions(document.createElement('select'), [['true', 'true'], ['false', 'false']]);
        row.value.parentNode.replaceChild(select, row.value);
        row.value = select;
      }
    }

    function addRow() {
      var row = document.createElement('div');
      row.className = 'smart-custom-field-condition';

      // The join is only meaningful between two conditions.
      var join = appendOptions(document.createElement('select'), [[' && ', 'ET'], [' || ', 'OU']]);
      join.className = 'smart-custom-field-condition-join';
      join.style.visibility = rows.children.length === 0 ? 'hidden' : '';

      row.field = fieldSelect();
      row.operator = appendOptions(document.createElement('select'), []);
      row.value = valueWidget();
      row.join = join;

      var remove = document.createElement('a');
      remove.href = '#';
      remove.className = 'icon icon-del';
      remove.title = 'remove';
      remove.addEventListener('click', function (event) {
        event.preventDefault();
        rows.removeChild(row);
        if (rows.children.length > 0) {
          rows.children[0].join.style.visibility = 'hidden';
        }
      });

      row.appendChild(join);
      row.appendChild(row.field);
      row.appendChild(row.operator);
      row.appendChild(row.value);
      row.appendChild(remove);
      row.field.addEventListener('change', function () { refreshRow(row); });

      rows.appendChild(row);
      refreshRow(row);
    }

    function literal(row) {
      var format = optionFormat(row.field);
      var value = row.value.value;

      if (NUMERIC[format]) {
        // An empty numeric input would generate `cfs[12] > ` and break the
        // formula: zero is the only value that keeps it valid.
        return value === '' ? '0' : value;
      }
      if (format === 'bool') {
        return value === 'true' ? 'true' : 'false';
      }
      if (DATE[format]) {
        return DATE[format] + ".parse('" + escapeString(value) + "')";
      }
      return "'" + escapeString(value) + "'";
    }

    function expression() {
      var parts = [];
      for (var i = 0; i < rows.children.length; i += 1) {
        var row = rows.children[i];
        var condition = 'cfs[' + optionValue(row.field) + '] ' +
          optionValue(row.operator) + ' ' + literal(row);
        parts.push(i === 0 ? condition : optionValue(row.join) + condition);
      }
      return parts.length > 1 ? '(' + parts.join('') + ')' : parts.join('');
    }

    // Inserted at the cursor rather than replacing the textarea: the builder
    // expresses one part of a formula, it does not own the whole formula.
    function insert(text) {
      var start = textarea.selectionStart;
      var end = textarea.selectionEnd;
      var value = textarea.value;
      textarea.value = value.slice(0, start) + text + value.slice(end);
      textarea.selectionStart = textarea.selectionEnd = start + text.length;
      textarea.focus();
    }

    addLink.addEventListener('click', function (event) {
      event.preventDefault();
      addRow();
    });

    applyLink.addEventListener('click', function (event) {
      event.preventDefault();
      var text = expression();
      if (text) { insert(text); }
    });

    addRow();
  });
})();
