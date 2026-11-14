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
        # TODO: Should I wrap this thing in a big rescue block?
        Puppet[:code] = content
        env = Puppet.lookup(:current_environment)
        loaders = Puppet::Pops::Loaders.new(env)
        Puppet.override({ loaders: }, 'For puppet parser validate') do
          validation_environment = env
          $PuppetParserMutex.synchronize do # rubocop:disable Style/GlobalVars
            original_taskmode = Puppet[:tasks] if Puppet.tasks_supported?
            Puppet[:tasks] = options[:tasks_mode] if Puppet.tasks_supported?
            validation_environment.check_for_reparse
            validation_environment.known_resource_types.clear
          ensure
            Puppet[:tasks] = original_taskmode if Puppet.tasks_supported?
          end
        rescue StandardError => e
          # Sometimes the error is in the cause not the root object itself
          e = e.cause if !e.respond_to?(:line) && e.respond_to?(:cause)
          ex_line = e.respond_to?(:line) && !e.line.nil? ? e.line - 1 : nil # Line numbers from puppet exceptions are base 1
          ex_pos = e.respond_to?(:pos) && !e.pos.nil? ? e.pos : nil # Pos numbers from puppet are base 1

          message = e.respond_to?(:message) ? e.message : nil
          message = e.basic_message if message.nil? && e.respond_to?(:basic_message)

          unless ex_line.nil? || ex_pos.nil? || message.nil?
            result << LSP::Diagnostic.new('severity' => LSP::DiagnosticSeverity::ERROR,
                                          'range' => LSP.create_range(ex_line, ex_pos, ex_line, ex_pos + 1),
                                          'source' => 'Puppet',
                                          'message' => message)
          end
        end

        result
      end

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
