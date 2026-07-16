require 'spec_helper'

describe 'PuppetLanguageServer::Manifest::ValidationProvider' do
  let(:session_state) { PuppetLanguageServer::ClientSessionState.new(nil, :connection_id => 'mock') }
  let(:subject) { PuppetLanguageServer::Manifest::ValidationProvider }

  describe '#fix_validate_errors' do
    describe "Given an incomplete manifest which has syntax errors but no lint errors" do
      let(:manifest) { "user { 'Bob'\n" }

      it "should return no changes" do
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(0)
        expect(new_content).to eq(manifest)
      end
    end

    describe "Given a complete manifest which has a single fixable lint errors" do
      let(:manifest) do
        <<~PUPPET
          user { "Bob":
            ensure => 'present',
          }
        PUPPET
      end
      let(:new_manifest) do
        <<~PUPPET
          user { 'Bob':
            ensure => 'present',
          }
        PUPPET
      end

      it "should return changes" do
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(1)
        expect(new_content).to eq(new_manifest)
      end
    end

    describe "Given a complete manifest which has multiple fixable lint errors" do
      let(:manifest) do
        <<~PUPPET
          // bad comment
          user { "Bob":
            name => 'username',
            ensure => 'present',
          }
        PUPPET
      end
      let(:new_manifest) do
        <<~PUPPET
          # bad comment
          user { 'Bob':
            ensure => 'present',
            name   => 'username',
          }
        PUPPET
      end

      it "should return changes" do
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(4)
        expect(new_content).to eq(new_manifest)
      end
    end


    describe "Given a complete manifest which has unfixable lint errors" do
      let(:manifest) do
        <<~PUPPET
          user { 'Bob':
            ensure => 'present',
            name   => 'name',
          }
        PUPPET
      end

      it "should return no changes" do
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(0)
        expect(new_content).to eq(manifest)
      end
    end

    describe "Given a complete manifest with CRLF which has fixable lint errors" do
      let(:manifest)     { "user { \"Bob\":\r\nensure  => 'present'\r\n}" }
      let(:new_manifest) { "user { 'Bob':\r\nensure  => 'present'\r\n}" }

      it "should preserve CRLF" do
        skip('Release of https://github.com/rodjek/puppet-lint/commit/2a850ab3fd3694a4dd0c4d2f22a1e60b9ca0a495')
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(1)
        expect(new_content).to eq(new_manifest)
      end
    end

    describe "Given a complete manifest which has disabed fixable lint errors" do
      let(:manifest) do
        <<~PUPPET
          user { "Bob": # lint:ignore:double_quoted_strings
            ensure => 'present',
          }
        PUPPET
      end

      it "should return no changes" do
        problems_fixed, new_content = subject.fix_validate_errors(session_state, manifest)
        expect(problems_fixed).to eq(0)
        expect(new_content).to eq(manifest)
      end
    end
  end

  describe '#validate' do
    describe 'with vendored Vox Pupuli puppet-lint plugins' do
      let(:manifest) do
        <<~PUPPET
          # @summary Example class
          class example(
            String $documented = 'value',
            String $undocumented = 'value',
          ) {
          }
        PUPPET
      end

      it 'returns diagnostics from the plugin checks' do
        diagnostics = subject.validate(session_state, manifest)

        expect(diagnostics.map(&:code)).to include('parameter_documentation')
      end

      it 'marks at least one character for diagnostics without a puppet-lint token' do
        diagnostic = subject.validate(session_state, manifest).find do |item|
          item.code == 'parameter_documentation'
        end

        expect(diagnostic.range.end.character).to be > diagnostic.range.start.character
      end

      it 'uses the document path for autoloader layout checks' do
        diagnostics = subject.validate(
          session_state,
          "class example::nested {}\n",
          :document_uri => 'file:///workspace/puppet-example/manifests/nested.pp'
        )

        expect(diagnostics.map(&:code)).not_to include('autoloader_layout')
      end
    end

    describe "Given an incomplete manifest which has syntax errors" do
      let(:manifest) { 'user { "Bob"' }

      it "should return at least one error" do
        result = subject.validate(session_state, manifest)
        expect(result.length).to be > 0
      end
    end

    context 'Given a Puppet Plan', :if => Puppet.tasks_supported? do
      let(:manifest) do
        <<~PUPPET
          plan mymodule::my_plan(
          ) {
          }
        PUPPET
      end

      it "should not raise an error" do
        result = subject.validate(session_state, manifest, { :tasks_mode => true})
      end
    end

    describe "Given a complete manifest with no validation errors" do
      let(:manifest) { "user { 'Bob': ensure => 'present' }\n" }

      it "should return an empty array" do
        expect(subject.validate(session_state, manifest)).to eq([])
      end
    end

    describe "Given a complete manifest with linting errors" do
      let(:manifest_fixture) { File.join($fixtures_dir,'manifest_with_lint_errors.pp') }
      let(:manifest_lf) { File.open(manifest_fixture, 'r') { |file| file.read } }
      let(:manifest_crlf) { File.open(manifest_fixture, 'r') { |file| file.read }.gsub("\n","\r\n") }

      it "should return same errors for both LF and CRLF line endings" do
        lint_error_lf = subject.validate(session_state, manifest_lf)
        lint_error_crlf = subject.validate(session_state, manifest_crlf)
        expect(lint_error_crlf.to_json).to eq(lint_error_lf.to_json)
      end
    end

    describe "Given a complete manifest with a single linting error" do
      let(:manifest) do
        <<~PUPPET
          user { 'Bob':
            ensure  => 'present',
            comment => '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890',
          }
        PUPPET
      end

      it "should return an array with one entry" do
        expect(subject.validate(session_state, manifest).count).to eq(1)
      end

      it "should return an entry with linting error information" do
        lint_error = subject.validate(session_state, manifest)[0]

        expect(lint_error.source).to eq('Puppet')
        expect(lint_error.message).to match('140')
        expect(lint_error.range).to_not be_nil
        expect(lint_error.code).to_not be_nil
        expect(lint_error.severity).to_not be_nil
      end

      context "but disabled" do
        context "on a single line" do
          let(:manifest) do
            <<~PUPPET
              user { 'Bob':
                ensure  => 'present',
                comment => '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890'   # lint:ignore:140chars
              }
            PUPPET
          end

          it "should return an empty array" do
            expect(subject.validate(session_state, manifest)).to eq([])
          end
        end

        context "in a linting block" do
          let(:manifest) do
            <<~PUPPET
              user { 'Bob':
                ensure  => 'present',
                # lint:ignore:140chars
                comment => '123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890',
                # lint:endignore
              }
            PUPPET
          end

          it "should return an empty array" do
            expect(subject.validate(session_state, manifest)).to eq([])
          end
        end
      end
    end

    describe "Given a complete manifest with validation errors" do
      let(:manifest) do
        <<~PUPPET
          class bad_formatting {
            user { 'username':
              ensure          => absent,
              auth_membership => 'false',
            }
          }
        PUPPET
      end

      it "should return errors and warnings even after fix_validate_errors" do
        fixes = subject.fix_validate_errors(session_state, manifest)
        validation = subject.validate(session_state, manifest)

        expect(validation.count).to_not be_zero

        validation.each do |problem|
          expect([LSP::DiagnosticSeverity::ERROR, LSP::DiagnosticSeverity::WARNING]).to include(problem.severity)
        end
      end
    end
  end
end
