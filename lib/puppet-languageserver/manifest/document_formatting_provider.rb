# frozen_string_literal: true

require 'puppet-languageserver/manifest/format_on_type_provider'
require 'puppet-languageserver/puppet_lint'

module PuppetLanguageServer
  module Manifest
    class DocumentFormattingProvider
      class << self
        def instance
          @instance ||= new
        end
      end

      def format(content, formatting_options, max_filesize = 4096)
        return [] unless formatting_options['insertSpaces'] == true
        return [] if !max_filesize.zero? && (content.length > max_filesize)

        lexer = PuppetLint::Lexer.new
        tokens = lexer.tokenise(content)
        edits = {}

        tokens.select { |token| token.type == :FARROW }.each do |token|
          FormatOnTypeProvider.instance.format(
            content,
            token.line - 1,
            token.column,
            '>',
            formatting_options,
            max_filesize
          ).each do |edit|
            edits[edit.to_h] = edit
          end
        end

        edits.values.sort_by do |edit|
          [edit.range.start.line, edit.range.start.character, edit.range.end.line, edit.range.end.character]
        end
      end
    end
  end
end
