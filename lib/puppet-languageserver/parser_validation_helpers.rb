# frozen_string_literal: true

module PuppetLanguageServer
  # Shared helpers for turning Puppet parser validation failures into LSP
  # diagnostics.
  #
  # The parser reports a single issue by raising an exception that carries its
  # position, but when there are multiple issues it logs each one and raises a
  # positionless "Language validation logged N errors" exception. These helpers
  # capture the logged issues so they can all become diagnostics.
  module ParserValidationHelpers
    COLLECTOR_DESTINATION = 'lsp_validation_collector'
    THREAD_BUFFER_KEY = :puppet_lsp_validation_messages

    module_function

    # Collect the Puppet log messages that are emitted while the block runs.
    #
    # The collector destination is registered on demand because
    # Puppet.initialize_settings can clear the destination list. The log level
    # is temporarily lowered to :err so that a stricter configured level cannot
    # filter out the parser issues that are being captured.
    def capture_parser_messages(captured)
      Puppet::Util::Log.newdestination(COLLECTOR_DESTINATION) unless Puppet::Util::Log.destinations.key?(COLLECTOR_DESTINATION)

      original_log_level = Puppet::Util::Log.level
      Puppet::Util::Log.level = :err
      Thread.current[THREAD_BUFFER_KEY] = captured
      begin
        yield
      ensure
        Thread.current[THREAD_BUFFER_KEY] = nil
        Puppet::Util::Log.level = original_log_level
      end
      captured
    end

    # Build the diagnostics for a parser failure, preferring the individual
    # issues that the parser logged and falling back to the raised exception.
    def parser_diagnostics(content, error, captured, max_problems = 100)
      messages = captured.select { |message| message.level == :err }
      messages = messages.uniq { |message| [message.line, message.pos, message.message] }
      messages = messages.first(max_problems) unless max_problems.nil?

      return messages.map { |message| diagnostic_from_log_message(content, message) } unless messages.empty?

      diagnostic = diagnostic_from_exception(content, error)
      diagnostic.nil? ? [] : [diagnostic]
    end

    def diagnostic_from_log_message(content, message)
      line, char = message_position(content, message.line, message.pos)
      LSP::Diagnostic.new('severity' => LSP::DiagnosticSeverity::ERROR,
                          'code' => message.issue_code&.to_s,
                          'range' => LSP.create_range(line, char, line, char + 1),
                          'source' => 'Puppet',
                          'message' => message.message)
    end

    def diagnostic_from_exception(content, error)
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

    # Puppet line and position numbers are 1-based. A positionless error, such
    # as "Syntax error at end of input", is reported at the end of the document.
    def message_position(content, line, pos)
      return end_of_document_position(content) if line.nil? || pos.nil?

      [[line - 1, 0].max, [pos - 1, 0].max]
    end

    def end_of_document_position(content)
      lines = content.split("\n", -1)
      line = [lines.length - 1, 0].max
      [line, lines[line].to_s.chomp("\r").length]
    end
  end
end
