# frozen_string_literal: true

module PuppetLanguageServer
  module Manifest
    # Helpers for completing resource attributes.
    module CompletionProviderAttributes
      # OpenVox/Puppet does not limit attribute name length. The longest
      # built-in attribute is 23 characters (selinux_ignore_defaults), and the
      # style guide recommends lines no longer than 140 characters. This cap is
      # purely defensive: it bounds alignment padding for pathological manifests
      # and for client-supplied completion data.
      MAX_ATTRIBUTE_PADDING = 999

      def attribute_data(resource_data, type, name_key, name)
        name_length = name.to_s.length
        padding = [resource_data['padding'].to_i, name_length].max
        alignment = resource_data['alignment'] == true && padding.positive? && padding <= MAX_ATTRIBUTE_PADDING
        padding = name_length if padding > MAX_ATTRIBUTE_PADDING

        resource_data.merge(
          'type' => type,
          name_key => name.to_s,
          'padding' => padding,
          'alignment' => alignment
        )
      end

      # Build the shared data payload for every completion item generated from
      # one resource expression.
      def attribute_resource_data(content, line_num, char_num, options, resource_type, operations)
        slice = content.split("\n", -1)[line_num].to_s[0, char_num].to_s
        indent = slice[/\A[ \t]*/] || ''
        # An unanchored search can retry at every offset, so use rindex instead
        # of a trailing-anchored regex on long runs of attribute-name characters.
        boundary = slice.rindex(/[^\w-]/)
        prefix = boundary.nil? ? slice : slice[(boundary + 1)..].to_s

        padding = operations.map { |operation| operation.attribute_name.to_s.length }.max || 0
        alignment = padding.positive? && padding <= MAX_ATTRIBUTE_PADDING

        {
          'resource_type' => resource_type,
          'padding' => alignment ? padding : 0,
          'alignment' => alignment,
          'replace_range' => LSP.create_range(line_num, char_num - prefix.length, line_num, char_num),
          'uri' => options[:file_uri],
          'document_version' => options[:document_version],
          'cursor_line' => line_num,
          'cursor_char' => char_num,
          'indent_width' => indent.length,
          'tasks_mode' => options[:tasks_mode] == true
        }
      end

      # Build hashrocket alignment edits for resource attributes.
      #
      # operations   - Array of Puppet::Pops::Model::AttributeOperation
      # cursor_line  - 0-based line number of the completion, which is skipped
      # indent_width - number of leading spaces on the completion line
      # width        - desired attribute-name column width
      #
      # Returns an Array of LSP::TextEdit. Returns an empty Array when
      # alignment is not possible or not safe.
      def alignment_edits_from_operations(operations, cursor_line, indent_width, width)
        return [] if width.nil? || width <= 0 || width > MAX_ATTRIBUTE_PADDING
        return [] if operations.nil? || operations.empty?

        infos = []
        operations.each do |operation|
          name = operation.attribute_name.to_s
          next if name.empty?
          return [] if name.length > MAX_ATTRIBUTE_PADDING

          locator = operation.respond_to?(:locator) ? operation.locator : nil
          next if locator.nil?

          source = locator.string
          next if source.nil?

          name_start = operation.offset
          name_end = name_start + name.length
          value_expr = operation.value_expr
          next if value_expr.nil? || !value_expr.respond_to?(:offset)

          gap = source[name_end...value_expr.offset]
          next if gap.nil?

          arrow_offset = gap.index('=>')
          next if arrow_offset.nil?

          arrow_start = name_end + arrow_offset

          infos << {
            line: locator.line_for_offset(name_start) - 1,
            name_end_col: locator.pos_on_line(name_start) - 1 + name.length,
            arrow_col: locator.pos_on_line(arrow_start) - 1
          }
        end

        return [] if infos.empty?

        # Match format-on-type: if two hashrockets share a line we cannot
        # align the body safely.
        lines = infos.map { |info| info[:line] }
        return [] if lines.uniq.length != lines.length

        target_col = infos.map { |info| info[:name_end_col] }.max + 1
        target_col = [target_col, indent_width.to_i + width + 1].max

        infos.each_with_object([]) do |info, edits|
          # The completion snippet handles the line being completed.
          next if info[:line] == cursor_line

          whitespace = target_col - info[:name_end_col]
          next if info[:arrow_col] - info[:name_end_col] == whitespace

          edits << LSP::TextEdit.new.from_h!(
            'newText' => ' ' * whitespace,
            'range' => LSP.create_range(info[:line], info[:name_end_col], info[:line], info[:arrow_col])
          )
        end
      end

      def attribute_insert_text(session_state, item, data, name)
        raw_padding = data['padding'].to_i
        padding = if raw_padding.positive? && raw_padding <= MAX_ATTRIBUTE_PADDING
                    [raw_padding, name.to_s.length].max
                  else
                    name.to_s.length
                  end

        item.insertText = "#{name.to_s.ljust(padding)} => ${1},$0"
        item.textEdit = LSP::TextEdit.new.from_h!('newText' => item.insertText, 'range' => data['replace_range'])
        item.additionalTextEdits = nil

        edits = attribute_resolve_alignment_edits(session_state, data, padding)
        item.additionalTextEdits = edits unless edits.empty?
      end

      private

      def attribute_resolve_alignment_edits(session_state, data, padding)
        return [] unless data['alignment'] == true

        raw_padding = data['padding'].to_i
        return [] unless raw_padding.positive? && raw_padding <= MAX_ATTRIBUTE_PADDING

        uri = data['uri']
        version = data['document_version']
        return [] if uri.nil? || version.nil?

        content = session_state.documents.document_content(uri, version)
        return [] if content.nil?

        operations = attribute_operations(
          content,
          data['cursor_line'].to_i,
          data['cursor_char'].to_i,
          data['tasks_mode'] == true
        )
        alignment_edits_from_operations(
          operations,
          data['cursor_line'].to_i,
          data['indent_width'].to_i,
          padding
        )
      rescue StandardError
        []
      end

      def attribute_operations(content, line_num, char_num, tasks_mode)
        result = PuppetLanguageServer::PuppetParserHelper.object_under_cursor(
          content, line_num, char_num,
          multiple_attempts: true,
          disallowed_classes: [Puppet::Pops::Model::QualifiedName, Puppet::Pops::Model::BlockExpression],
          tasks_mode: tasks_mode,
          remove_trigger_char: false
        )
        return [] if result.nil?

        model = result[:model]
        return [] unless model.instance_of?(::Puppet::Pops::Model::ResourceExpression)

        model.bodies.flat_map { |body| body.operations || [] }
      end
    end
  end
end
