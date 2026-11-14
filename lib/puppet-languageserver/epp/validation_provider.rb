# frozen_string_literal: true

require 'puppet-languageserver/parser_validation_helpers'

module PuppetLanguageServer
  module Epp
    module ValidationProvider
      def self.validate(content, max_problems = 100)
        result = []
        captured = []

        begin
          parser = Puppet::Pops::Parser::EvaluatingParser::EvaluatingEppParser.new
          # The mutex also protects the global log level that is temporarily
          # lowered while capturing parser messages.
          $PuppetParserMutex.synchronize do # rubocop:disable Style/GlobalVars
            ParserValidationHelpers.capture_parser_messages(captured) { parser.parse_string(content, nil) }
          end
        rescue StandardError => e
          result.concat(ParserValidationHelpers.parser_diagnostics(content, e, captured, max_problems))
        end

        result
      end
    end
  end
end
