# frozen_string_literal: true

require 'puppet-languageserver/manifest/format_on_type_provider'

module PuppetLanguageServer
  module Manifest
    # Helpers for completing resource attributes.
    module CompletionProviderAttributes
      def attribute_data(resource_data, context, type, name_key, name)
        max_length = [resource_data['padding'], name.to_s.length].max
        data = resource_data.merge('type' => type, name_key => name.to_s, 'padding' => max_length)
        edits = attribute_alignment_edits(context, max_length)
        edits.empty? ? data : data.merge('additional_edits' => edits)
      end

      # Reuse format-on-type hashrocket alignment so existing attributes are
      # padded when the completed attribute is longer.
      def attribute_alignment_edits(context, max_length)
        cached = context[:cache][max_length]
        return cached unless cached.nil?

        context[:cache][max_length] = FormatOnTypeProvider.alignment_edits(
          context[:lines], context[:line_num], context[:indent], max_length
        )
      rescue StandardError
        []
      end

      def attribute_insert_text(item, data, name)
        item.insertText = "#{name.to_s.ljust(data['padding'].to_i)} => ${1},$0"
        item.textEdit = LSP::TextEdit.new.from_h!('newText' => item.insertText, 'range' => data['replace_range'])
        item.additionalTextEdits = data['additional_edits'].map { |edit| LSP::TextEdit.new(edit) } unless data['additional_edits'].nil?
      end
    end
  end
end
