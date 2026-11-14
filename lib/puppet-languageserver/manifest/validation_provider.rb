# frozen_string_literal: true

require 'puppet-languageserver/puppet_lint'
require 'puppet-languageserver/uri_helper'
module PuppetLanguageServer
  module Manifest
    module ValidationProvider
      LINT_FILENAME = 'manifest.pp'

      # Similar to 'validate' this will run puppet-lint and returns
      # the manifest with any fixes applied
      #
      # Returns:
      #  [ <Int> Number of problems fixed,
      #    <String> New Content
      #  ]
      def self.fix_validate_errors(session_state, content, document_uri = nil)
        init_puppet_lint(session_state.documents.store_root_path, ['--fix', '--relative'])

        linter = PuppetLint::Checks.new
        problems = begin
          linter.run(lint_filename(document_uri), content)
        rescue SystemExit
          PuppetLanguageServer.log_message(:error, '(fix_validate_errors) puppet-lint aborted')
          nil
        end

        # When puppet-lint cannot parse the manifest (for example a syntax error)
        # it discards all of the tokens and `manifest` returns an empty string.
        # Returning that to the client would replace the document with nothing,
        # so leave the original content untouched instead.
        return [0, content] if problems.nil? || syntax_errors?(problems)

        problems_fixed = problems.count { |item| item[:kind] == :fixed }

        [problems_fixed, linter.manifest]
      end

      def self.syntax_errors?(problems)
        problems.any? { |problem| problem[:kind] == :error && problem[:check] == :syntax }
      end
      private_class_method :syntax_errors?

      def self.validate(session_state, content, options = {})
        options = {
          max_problems: 100,
          tasks_mode: false
        }.merge(options)

        result = []
        # TODO: Need to implement max_problems
        problems = 0

        init_puppet_lint(session_state.documents.store_root_path, ['--relative'])

        begin
          linter = PuppetLint::Checks.new
          problems = begin
            linter.run(lint_filename(options[:document_uri]), content)
          rescue SystemExit
            PuppetLanguageServer.log_message(:error, '(textDocument/validation) puppet-lint aborted')
            nil
          end
          unless problems.nil?
            problems.each do |problem|
              # Syntax errors are better handled by the puppet parser, not puppet lint
              next if problem[:kind] == :error && problem[:check] == :syntax
              # Ignore linting errors what were ignored by puppet-lint
              next if problem[:kind] == :ignored

              severity = case problem[:kind]
                         when :error
                           LSP::DiagnosticSeverity::ERROR
                         when :warning
                           LSP::DiagnosticSeverity::WARNING
                         else
                           LSP::DiagnosticSeverity::HINT
                         end

              startpos = problem[:column] - 1
              token_length = if problem[:token].nil? || problem[:token].value.nil?
                               1
                             else
                               problem[:token].to_manifest.length
                             end
              endpos = startpos + [token_length, 1].max

              result << LSP::Diagnostic.new('severity' => severity,
                                            'code' => problem[:check].to_s,
                                            'range' => LSP.create_range(problem[:line] - 1, startpos, problem[:line] - 1, endpos),
                                            'source' => 'Puppet',
                                            'message' => problem[:message])
            end
          end
        rescue StandardError
          # If anything catastrophic happens we resort to puppet parsing anyway
        end
        # The parser reports a single issue by raising an exception that carries
        # its position, but when there are multiple issues it logs each one and
        # raises a positionless "Language validation logged N errors" exception.
        # Capture the logged issues so they can all become diagnostics.
        Puppet::Util::Log.newdestination('lsp_validation_collector') unless Puppet::Util::Log.destinations.key?('lsp_validation_collector')
        captured = []

        env = Puppet.lookup(:current_environment)
        loaders = Puppet::Pops::Loaders.new(env)
        Puppet.override({ loaders: }, 'For puppet parser validate') do
          validation_environment = env
          $PuppetParserMutex.synchronize do # rubocop:disable Style/GlobalVars
            original_taskmode = Puppet[:tasks] if Puppet.tasks_supported?
            original_log_level = Puppet::Util::Log.level
            Puppet[:code] = content
            Puppet[:tasks] = options[:tasks_mode] if Puppet.tasks_supported?
            # Do not let the configured log level filter out the issues we are
            # about to capture.
            Puppet::Util::Log.level = :err
            Thread.current[:puppet_lsp_validation_messages] = captured
            validation_environment.check_for_reparse
            validation_environment.known_resource_types.clear
          ensure
            Thread.current[:puppet_lsp_validation_messages] = nil
            Puppet::Util::Log.level = original_log_level
            Puppet[:tasks] = original_taskmode if Puppet.tasks_supported?
          end
        rescue StandardError => e
          parser_errors = captured.select { |message| message.level == :err }
          parser_errors = parser_errors.uniq { |message| [message.line, message.pos, message.message] }
          parser_errors = parser_errors.first(options[:max_problems]) unless options[:max_problems].nil?

          if parser_errors.empty?
            diagnostic = diagnostic_from_exception(content, e)
            result << diagnostic unless diagnostic.nil?
          else
            parser_errors.each { |message| result << diagnostic_from_log_message(content, message) }
          end
        end

        result
      end

      def self.diagnostic_from_log_message(content, message)
        line, char = message_position(content, message.line, message.pos)
        LSP::Diagnostic.new('severity' => LSP::DiagnosticSeverity::ERROR,
                            'code' => message.issue_code.nil? ? nil : message.issue_code.to_s,
                            'range' => LSP.create_range(line, char, line, char + 1),
                            'source' => 'Puppet',
                            'message' => message.message)
      end
      private_class_method :diagnostic_from_log_message

      def self.diagnostic_from_exception(content, error)
        # Sometimes the error is in the cause not the root object itself
        error = error.cause if !error.respond_to?(:line) && error.respond_to?(:cause)

        message = if error.respond_to?(:basic_message) && !error.basic_message.nil?
                    error.basic_message
                  elsif error.respond_to?(:message)
                    error.message
                  end
        return nil if message.nil?

        error_line = error.respond_to?(:line) ? error.line : nil
        error_pos = error.respond_to?(:pos) ? error.pos : nil
        line, char = message_position(content, error_line, error_pos)
        code = error.respond_to?(:issue_code) && !error.issue_code.nil? ? error.issue_code.to_s : nil

        LSP::Diagnostic.new('severity' => LSP::DiagnosticSeverity::ERROR,
                            'code' => code,
                            'range' => LSP.create_range(line, char, line, char + 1),
                            'source' => 'Puppet',
                            'message' => message)
      end
      private_class_method :diagnostic_from_exception

      # Puppet line and position numbers are 1-based. A positionless error, such
      # as "Syntax error at end of input", is reported at the end of the document.
      def self.message_position(content, line, pos)
        return end_of_document_position(content) if line.nil? || pos.nil?

        [[line - 1, 0].max, [pos - 1, 0].max]
      end
      private_class_method :message_position

      def self.end_of_document_position(content)
        lines = content.split("\n", -1)
        line = [lines.length - 1, 0].max
        [line, lines[line].to_s.chomp("\r").length]
      end
      private_class_method :end_of_document_position

      def self.init_puppet_lint(root_dir, lint_options = [])
        linter_options = nil
        if root_dir.nil?
          linter_options = PuppetLint::OptParser.build
        else
          begin
            $PuppetParserMutex.synchronize do # rubocop:disable Style/GlobalVars
              Dir.chdir(root_dir.to_s) { linter_options = PuppetLint::OptParser.build }
            end
          rescue OptionParser::InvalidOption => e
            PuppetLanguageServer.log_message(:error, "(#{name}) Error reading Puppet Lint configuration.  Using default: #{e}")
            linter_options = PuppetLint::OptParser.build
          end
        end
        # Reset the fix flag
        PuppetLint.configuration.fix = false
        linter_options.parse!(lint_options)
      end
      private_class_method :init_puppet_lint

      def self.lint_filename(document_uri)
        PuppetLanguageServer::UriHelper.uri_path(document_uri) || LINT_FILENAME
      rescue URI::InvalidURIError
        LINT_FILENAME
      end
      private_class_method :lint_filename
    end
  end
end
