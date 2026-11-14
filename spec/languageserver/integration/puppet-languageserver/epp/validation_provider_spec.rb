require 'spec_helper'

describe 'PuppetLanguageServer::Epp::ValidationProvider' do
  let(:subject) { PuppetLanguageServer::Epp::ValidationProvider }

  describe '#validate' do
    describe "Given an EPP which has a syntax error" do
      let(:template) { '<%- String $tmp
      | -%>

      <%= $tmp %>' }

      it "should return a single syntax error with a zero-based position" do
        result = subject.validate(template, nil)
        expect(result.length).to eq(1)
        expect(result[0].code).to eq('SYNTAX_ERROR')
        expect(result[0].range.start.line).to eq(1)
        expect(result[0].range.start.character).to eq(6)
        expect(result[0].range.end.line).to eq(1)
        expect(result[0].range.end.character).to eq(7)
        expect(result[0].message).to eq("Syntax error at '|'")
      end
    end

    describe "Given an EPP which has a syntax error without a position" do
      let(:template) { '<% if true { %>' }

      it "should report the error at the end of the document" do
        result = subject.validate(template, nil)
        expect(result.length).to eq(1)
        expect(result[0].code).to eq('SYNTAX_ERROR')
        expect(result[0].range.start.line).to eq(0)
        expect(result[0].range.start.character).to eq(template.length)
        expect(result[0].message).to eq('Syntax error at end of input')
      end
    end

    describe "Given an EPP which has multiple validation errors" do
      let(:template) { "<% $ %>\n<% $ %>" }

      it "should return every issue that the parser logs instead of an aggregate error" do
        result = subject.validate(template, nil)
        expect(result.length).to eq(3)
        expect(result.map(&:code)).to include('IDEM_EXPRESSION_NOT_LAST', 'ILLEGAL_VAR_NAME')
        expect(result.map { |item| [item.range.start.line, item.range.start.character] })
          .to eq([[0, 3], [0, 3], [1, 3]])
        expect(result.map(&:message)).to all(
          satisfy { |message| message.start_with?('This Variable has no effect') || message.start_with?('Illegal variable name') }
        )
        expect(result.map(&:message)).to all(satisfy { |message| !message.include?('(line:') })
      end

      it "should cap the number of diagnostics" do
        expect(subject.validate(template, 1).length).to eq(1)
      end
    end

    describe "Given a complete EPP which has no syntax errors" do
      let(:template) { '<%- | String $tmp
      | -%>

      <%= $tmp %>' }

      it "should return an empty array" do
        expect(subject.validate(template, nil)).to eq([])
      end
    end
  end
end
