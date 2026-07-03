require 'spec_helper'
require 'puppet-languageserver/manifest/document_formatting_provider'

describe 'PuppetLanguageServer::Manifest::DocumentFormattingProvider' do
  let(:subject) { PuppetLanguageServer::Manifest::DocumentFormattingProvider.new }

  describe '::instance' do
    it 'should exist' do
      expect(PuppetLanguageServer::Manifest::DocumentFormattingProvider).to respond_to(:instance)
    end

    it 'should return the same object' do
      object1 = PuppetLanguageServer::Manifest::DocumentFormattingProvider.instance
      object2 = PuppetLanguageServer::Manifest::DocumentFormattingProvider.instance
      expect(object1).to eq(object2)
    end
  end

  describe '#format' do
    let(:formatting_options) do
      LSP::FormattingOptions.new.tap do |item|
        item.tabSize = 2
        item.insertSpaces = true
      end.to_h
    end

    let(:content) do <<-MANIFEST
user {
  ensure=> 'something',
  password   =>
  name => {
    'abc' => '123',
    'def'    => '789',
  },
  name2    => 'correct',
}
MANIFEST
    end

    it 'should return an empty array if the formatting options uses tabs' do
      result = subject.format(content, formatting_options.tap { |i| i['insertSpaces'] = false })
      expect(result).to eq([])
    end

    it 'should return an empty array if the document is large' do
      large_content = content + ' ' * 4096
      result = subject.format(large_content, formatting_options)
      expect(result).to eq([])
    end

    it 'should return document-wide hashrocket alignment edits' do
      result = subject.format(content, formatting_options)

      expect(result.count).to eq(4)
      expect(result[0].to_h).to eq(
        {"range"=>{"start"=>{"character"=>8,  "line"=>1}, "end"=>{"character"=>8,  "line"=>1}}, "newText"=>"   "}
      )
      expect(result[1].to_h).to eq(
        {"range"=>{"start"=>{"character"=>10, "line"=>2}, "end"=>{"character"=>13, "line"=>2}}, "newText"=>" "}
      )
      expect(result[2].to_h).to eq(
        {"range"=>{"start"=>{"character"=>6,  "line"=>3}, "end"=>{"character"=>7,  "line"=>3}}, "newText"=>"     "}
      )
      expect(result[3].to_h).to eq(
        {"range"=>{"start"=>{"character"=>9,  "line"=>5}, "end"=>{"character"=>13, "line"=>5}}, "newText"=>" "}
      )
    end
  end
end
