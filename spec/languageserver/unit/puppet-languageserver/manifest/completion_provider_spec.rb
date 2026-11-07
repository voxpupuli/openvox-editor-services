require 'spec_helper'

describe 'PuppetLanguageServer::Manifest::CompletionProvider' do
  let(:session_state) { PuppetLanguageServer::ClientSessionState.new(nil, :connection_id => 'mock') }
  let(:subject) { PuppetLanguageServer::Manifest::CompletionProvider }

  def number_of_completion_item_with_type(completion_list, typename)
    (completion_list.items.select { |item| item.data['type'] == typename}).length
  end

  RSpec::Matchers.define :be_completion_item_with_type do |value|
    value = [value] unless value.is_a?(Array)

    match { |actual| value.include?(actual.data['type']) }

    description do
      "be a Completion Item with a data type in the list of #{value}"
    end
  end

  def create_mock_type(parameters = [], properties = [])
    object = PuppetLanguageServer::Sidecar::Protocol::PuppetType.new
    object.doc = 'mock documentation'
    object.attributes = {}
    parameters.each { |name| object.attributes[name] = {
      :type        => :param,
      :doc         => 'mock parameter doc',
      :required? => nil,
      :isnamevar?  => nil
    }}
    properties.each { |name| object.attributes[name] = {
      :type        => :property,
      :doc         => 'mock parameter doc',
      :required? => nil,
      :isnamevar?  => nil
    }}

    object
  end

  before(:each) do
    # Prepopulate the Object Cache with workspace objects
    # Types
    list = PuppetLanguageServer::Sidecar::Protocol::PuppetTypeList.new
    list << create_mock_type(['param1'], ['prop1']).tap { |i| i.key = :mocktype }
    session_state.object_cache.import_sidecar_list!(list, :type, :workspace)
  end

  after(:each) do
    # Clear out the Object Cache of workspace objects
    PuppetLanguageServer::SessionState::ObjectCache::SECTIONS.each do |section|
      session_state.object_cache.import_sidecar_list!([], section, :workspace)
    end
  end

  describe '#complete' do
    # https://puppet.com/docs/puppet/latest/lang_classes.html#section-x54-1hk-xhb
    context 'given a resource-like declaration of a resource' do
      context 'where the title refers to a non-existant class' do
        let(:content) { <<-EOT
          class { 'does::not::exist':

          }
          EOT
        }
        let(:line_num) { 1 }
        let(:char_num) { 0 }

        it 'should return an empty completion list' do
          result = subject.complete(session_state, content, line_num, char_num)
          expect(result.items.count).to eq(0)
        end
      end

      context 'with a missing title name' do
        let(:content) { <<-EOT
          class {

          }
          EOT
        }
        let(:line_num) { 1 }
        let(:char_num) { 0 }

        it 'should raise an error' do
          expect{ subject.complete(session_state, content, line_num, char_num) }.to raise_error(RuntimeError)
        end
      end

      context 'with a known title class' do
        let(:content) { <<-EOT
          class { 'mocktype':

          }
          EOT
        }
        let(:line_num) { 1 }
        let(:char_num) { 0 }
        let(:expected_types) { ['resource_parameter','resource_property'] }

        it 'should return only parameter and property items' do
          result = subject.complete(session_state, content, line_num, char_num)

          result.items.each do |item|
            expect(item).to be_completion_item_with_type(expected_types)
          end
        end

        it 'should return the parameters of the class' do
          result = subject.complete(session_state, content, line_num, char_num)
          expect(number_of_completion_item_with_type(result, 'resource_parameter')).to eq(1)
        end

        it 'should return the properties of the class' do
          result = subject.complete(session_state, content, line_num, char_num)
          expect(number_of_completion_item_with_type(result, 'resource_property')).to eq(1)
        end
      end

      context 'with a partially typed attribute name' do
        let(:content) { "mocktype { 'title':\n  pro\n}\n" }
        let(:line_num) { 1 }
        let(:char_num) { 5 }

        it 'should return the resource attributes' do
          result = subject.complete(session_state, content, line_num, char_num)
          expect(result.items.map(&:label)).to include('param1', 'prop1')
        end
      end

      context 'with an attribute name longer than the padding cap' do
        let(:content) { "mocktype { 'title':\n  #{'a' * 1000} => 'value',\n  pro\n}\n" }
        let(:line_num) { 2 }
        let(:char_num) { 5 }

        it 'does not add alignment data' do
          result = subject.complete(session_state, content, line_num, char_num)
          item = result.items.find { |completion_item| completion_item.label == 'prop1' }

          expect(item).not_to be_nil
          expect(item.data['padding']).to eq('prop1'.length)
          expect(item.data).not_to have_key('additional_edits')
        end
      end
    end
  end

  describe '.alignment_edits_from_operations' do
    def operations_for(content, line_num, char_num)
      result = PuppetLanguageServer::PuppetParserHelper.object_under_cursor(
        content, line_num, char_num,
        multiple_attempts: true,
        disallowed_classes: [Puppet::Pops::Model::QualifiedName, Puppet::Pops::Model::BlockExpression],
        tasks_mode: false,
        remove_trigger_char: false
      )
      result[:model].bodies.flat_map { |body| body.operations || [] }
    end

    {
      'short existing attribute' => {
        content: "class example {\n  file { '/tmp/test':\n    mode => '0644',\n    own\n  }\n}\n",
        line_num: 3,
        char_num: 7,
        indent: '    ',
        width: 5
      },
      'missing space before hashrocket' => {
        content: "class example {\n  file { '/tmp/test':\n    ensure=> 'present',\n    mod\n  }\n}\n",
        line_num: 3,
        char_num: 7,
        indent: '    ',
        width: 6
      },
      'misaligned existing attributes' => {
        content: "class example {\n  file { '/tmp/test':\n    ensure    => 'present',\n    uid => 1,\n    mode\n  }\n}\n",
        line_num: 4,
        char_num: 8,
        indent: '    ',
        width: 6
      },
      'multiple hashrockets on one line' => {
        content: "class example {\n  file { '/tmp/test':\n    a => 1, b => 2,\n    mode\n  }\n}\n",
        line_num: 3,
        char_num: 8,
        indent: '    ',
        width: 6
      }
    }.each do |name, testcase|
      it "matches format-on-type for #{name}" do
        operations = operations_for(
          testcase[:content],
          testcase[:line_num],
          testcase[:char_num]
        )

        actual = subject.alignment_edits_from_operations(
          operations,
          testcase[:line_num],
          testcase[:indent].length,
          testcase[:width]
        ).map(&:to_h)

        candidate = testcase[:content].split("\n", -1)
        candidate[testcase[:line_num]] = "#{testcase[:indent]}#{'x' * testcase[:width]} =>"

        expected = PuppetLanguageServer::Manifest::FormatOnTypeProvider.instance.format(
          candidate.join("\n"),
          testcase[:line_num],
          testcase[:indent].length + testcase[:width] + 2,
          '>',
          { 'insertSpaces' => true },
          0
        ).reject { |edit| edit.range.start.line == testcase[:line_num] }.map(&:to_h)

        expect(actual).to eq(expected)
      end
    end
  end
end
