# OpenVox Editor Services

A Ruby implementation of a [Language Server](https://github.com/Microsoft/language-server-protocol) and [Debug Server](https://github.com/microsoft/debug-adapter-protocol) for OpenVox.
The internal `Puppet` Ruby namespace and `puppet/*` protocol methods are retained for compatibility.

- [OpenVox Editor Services](#openvox-editor-services)
  - [Requirements](#requirements)
  - [Setting up editor services for development](#setting-up-editor-services-for-development)
  - [Build a local VSIX](#build-a-local-vsix)
  - [Language Server](#language-server)
    - [How to run the Language Server for Development](#how-to-run-the-language-server-for-development)
    - [How to run the Language Server in Production](#how-to-run-the-language-server-in-production)
    - [Command line arguments](#command-line-arguments)
  - [Language Server Sidecar](#language-server-sidecar)
    - [How to run the Language Server Sidecar for Development](#how-to-run-the-language-server-sidecar-for-development)
    - [Example usage](#example-usage)
      - [Confirm that the Sidecar loads correctly](#confirm-that-the-sidecar-loads-correctly)
      - [Output all default Puppet Types](#output-all-default-puppet-types)
      - [Output all default Puppet Functions with a different puppet configuration, and debug information](#output-all-default-puppet-functions-with-a-different-puppet-configuration-and-debug-information)
      - [Output all Puppet Classes in a workspace directory](#output-all-puppet-classes-in-a-workspace-directory)
    - [Command line arguments for the Language Server Sidecar](#command-line-arguments-for-the-language-server-sidecar)
  - [Debug Server](#debug-server)
    - [How to run the Debug Server for Development](#how-to-run-the-debug-server-for-development)
    - [How to run the Debug Server for Production](#how-to-run-the-debug-server-for-production)
    - [Command line arguments for the Debug Server](#command-line-arguments-for-the-debug-server)
  - [License](#license)
  - [Other information](#other-information)
    - [Reporting bugs](#reporting-bugs)
  - [Development](#development)
  - [Packaging and runtime dependencies](#packaging-and-runtime-dependencies)

## Requirements

- OpenVox 8 or above
- Ruby 3.4 or above

## Setting up editor services for development

Use Ruby 3.4 or above, then clone the repository and install the development dependencies:

```shell
git clone https://github.com/voxpupuli/openvox-editor-services.git
cd openvox-editor-services
bundle install
bundle exec rake gem_revendor
```

`gem_revendor` downloads runtime dependency sources and requires network access.
Run it before starting the servers from the checkout or running the test suites.

The Gemfile accepts `OPENVOX_GEM_VERSION` to select the OpenVox dependency.
For example, to use the OpenVox 8 series as configured in CI:

```shell
export OPENVOX_GEM_VERSION='~> 8.0'
bundle install
```

Keep this variable set for subsequent `bundle exec` commands.
Without it, the Gemfile does not constrain the OpenVox version; Bundler resolves it using the available gems and lockfile.
When changing the requirement, run `bundle update openvox` if the existing lockfile does not satisfy it.

## Build a local VSIX

To test the current editor-services checkout with the sibling `openvox-vscode` repository, run:

```shell
./scripts/build-local-vsix.sh
```

The script removes old local gem and VSIX build artifacts, builds the local gem, installs it and its dependencies into
the extension, compiles the extension, and creates
`../openvox-vscode/artifacts/openvox-vscode-local-<gem-version>.vsix`.
It requires Ruby 3.4 or newer and existing npm dependencies in `openvox-vscode`.
Set `RUBY`, `OPENVOX_VSCODE_DIR`, or `VSIX_OUTPUT` to override the detected Ruby, repository path, or output path.

## Language Server

### How to run the Language Server for Development

By default the language server stops if no connection is made within 10 seconds or after a client disconnects.
Adding `--debug=stdout` logs diagnostic messages to the console.
The example below shows only the readiness message; the port is selected dynamically.

```bash
> bundle exec ruby ./openvox-languageserver --debug=stdout
LANGUAGE SERVER RUNNING localhost:55087
```

To make the server run continuously add `--timeout=0` and `--no-stop` to the command line. For example;

```bash
> bundle exec ruby ./openvox-languageserver --debug=stdout --timeout=0 --no-stop
LANGUAGE SERVER RUNNING localhost:55087
```

### How to run the Language Server in Production

- Ensure that OpenVox Agent is installed

- Run the `openvox-languageserver` with ruby

On Windows, run Ruby from the `OpenVox Command Prompt` in the Start Menu.
This enables the OpenVox Agent Ruby environment.

```bash
> ruby openvox-languageserver
LANGUAGE SERVER RUNNING 127.0.0.1:55086
```

> Note the language server will stop after 10 seconds if no client connection is made.

Note that the Language Server will use TCP as the default transport on `localhost` at a random port.
The IP Address and Port can be changed using the `--ip` and `--port` arguments respectively.
For example to listen on all interfaces on port 9000;

```bash
> ruby ./openvox-languageserver --ip=0.0.0.0 --port=9000
```

To change the protocol to STDIO, that is using STDOUT and STDIN, use the `--stdio` argument.

### Command line arguments

Common options:

| Option | Behavior |
| --- | --- |
| `--ip=ADDRESS` | TCP listen address; defaults to `localhost`. |
| `--port=PORT` | TCP listen port; defaults to a randomly selected port. |
| `--stdio` | Use STDIN and STDOUT instead of TCP. |
| `--timeout=SECONDS` | Wait for a connection for up to 10 seconds by default; `0` disables this timeout. |
| `--no-stop` | Keep running after a client disconnects. |
| `--debug=PATH` | Write diagnostic logs to a file, or use `STDOUT` for console output. |
| `--[no-]cache` | Enable or disable sidecar caching; enabled by default. |
| `--openvox-version=VERSION` | Select an OpenVox gem version; `--puppet-version` is a compatibility alias. |
| `--puppet-settings=SETTINGS` | Pass comma-separated settings, such as `--vardir,/path/to/vardir`. |

`--no-preload` and `--slow-start` are deprecated.
`--enable-file-cache` and `--local-workspace` are deprecated and have no effect.
The client supplies the Language Server workspace; the Sidecar's `--local-workspace` option remains supported.

For the complete option list, run:

```shell
bundle exec ruby ./openvox-languageserver --help
```

## Language Server Sidecar

### How to run the Language Server Sidecar for Development

The Language Server Sidecar is a process used by the Language Server to get information about Puppet's environment, for example, all available functions, classes, and custom types.
This tool is typically only run by the Language Server itself, but it can be used to diagnose issues.

The sidecar is told to perform an action (using the `action`) parameter and then, by default, outputs the JSON encoded result to STDOUT.
This can be changed to a text file using the `--output=PATH` argument.

Note that using the `--debug=STDOUT` option without directing the output to a text file will generate output on STDOUT which cannot be deserialized correctly.
Typically this only used by a developer to inspect what the Sidecar is doing.

### Example usage

#### Confirm that the Sidecar loads correctly

The `noop` action just outputs an empty JSON array but can be used to confirm that the Sidecar does not error while loading Puppet.

```bash
> bundle exec ruby ./openvox-languageserver-sidecar --action=noop
[]
```

#### Output all default Puppet Types

```bash
> bundle exec ruby ./openvox-languageserver-sidecar --action=default_types
[{"key":"anchor","calling_source":"puppet/cache/lib/puppet/type/anchor.rb","sou ...
```

#### Output all default Puppet Functions with a different puppet configuration, and debug information

```bash
bundle exec ruby ./openvox-languageserver-sidecar --action=default_functions --puppet-settings=--vardir,./test/vardir,--confdir,./test/confdir --debug=STDOUT
```

This prints diagnostic messages followed by the JSON function data.
Use `--output=functions.json` to save the JSON separately from the diagnostic output.

#### Output all Puppet Classes in a workspace directory

```bash
> bundle exec ruby ./openvox-languageserver-sidecar --action=workspace_classes --local-workspace=C:\source\puppetlabs-sqlserver
[{"key":"sqlserver::config","calling_source":"C:/Source/puppetlabs-sqlserver/manifests/config.pp","source":"C:/Source/puppetlabs-sqlserver/manifests/config.pp","line":25,"ch...
```

### Command line arguments for the Language Server Sidecar

Common options:

| Option | Behavior |
| --- | --- |
| `--action=NAME` | Required action, such as `noop`, `default_functions`, or `workspace_classes`. |
| `--action-parameters=JSON` | Supply action parameters as a JSON string. |
| `--local-workspace=PATH` | Set the workspace or file path for module-specific actions. |
| `--output=PATH` | Save JSON output to a file; defaults to STDOUT. |
| `--puppet-settings=SETTINGS` | Pass comma-separated settings, such as `--vardir,/path/to/vardir`. |
| `--[no-]cache` | Enable or disable caching; enabled by default. |
| `--openvox-version=VERSION` | Select an OpenVox gem version; `--puppet-version` is a compatibility alias. |
| `--debug=PATH` | Write diagnostic logs to a file, or use `STDOUT` for console output. |

For all supported actions and options, run:

```shell
bundle exec ruby ./openvox-languageserver-sidecar --help
```

## Debug Server

### How to run the Debug Server for Development

By default the debug server will stop if no connection is made within 10 seconds and will also stop after a client disconnects.
Adding `--debug=stdout` logs diagnostic messages to the console.
The examples below show only the readiness message; the port is selected dynamically.

```bash
> bundle exec ruby ./openvox-debugserver --debug=stdout
DEBUG SERVER RUNNING 127.0.0.1:8082
```

To wait for a client without a connection timeout, add `--timeout=0`.
The debug server still stops after the client disconnects.

```bash
> bundle exec ruby ./openvox-debugserver --debug=stdout --timeout=0
DEBUG SERVER RUNNING 127.0.0.1:8082
```

### How to run the Debug Server for Production

- Ensure that OpenVox Agent is installed
- Run the `openvox-debugserver` with ruby

On Windows you need to run ruby with the `OpenVox Command Prompt` which can be found in the Start Menu.
This enables the OpenVox Agent ruby environment.

```bash
> ruby openvox-debugserver
DEBUG SERVER RUNNING 127.0.0.1:8082
```

Note the debug server will stop after 10 seconds if no client connection is made.

### Command line arguments for the Debug Server

Common options:

| Option | Behavior |
| --- | --- |
| `--ip=ADDRESS` | TCP listen address; defaults to `localhost`. |
| `--port=PORT` | TCP listen port; defaults to a randomly selected port. |
| `--timeout=SECONDS` | Wait for a connection for up to 10 seconds by default; `0` disables this timeout. |
| `--openvox-version=VERSION` | Select an OpenVox gem version; `--puppet-version` is a compatibility alias. |
| `--debug=PATH` | Write diagnostic logs to a file, or use `STDOUT` for console output. |

For the complete option list, run:

```shell
bundle exec ruby ./openvox-debugserver --help
```

## License

This codebase is licensed under Apache 2.0. However, the open source dependencies included in this codebase might be subject to other software licenses such as AGPL, GPL2.0, and MIT.

## Other information

### Reporting bugs

If you find a bug in OpenVox Editor Services or its results, please create an issue in the
[repository issue tracker](https://github.com/voxpupuli/openvox-editor-services/issues).
Bonus points will be awarded if you also include a patch that fixes the issue.

## Development

After completing the [development setup](#setting-up-editor-services-for-development), run the relevant checks:

```shell
bundle exec rake test_languageserver
bundle exec rake test_languageserver_sidecar
bundle exec rake test_debugserver
bundle exec rake acceptance_languageserver
bundle exec rake rubocop
```

The first three commands run the component specs; the acceptance suite runs separately.
For coverage across the three component suites, run `bundle exec rake test:coverage`.
CI currently runs these checks with Ruby 4.0 and `OPENVOX_GEM_VERSION='~> 8.0'`,
with component and acceptance tests on Linux and Windows.
Use the explicit tasks above; the default Rake task currently refers to an undefined `test` task.

If you run into an issue with this tool or would like to request a feature you can raise a PR with your suggested changes.
Alternatively, you can raise a GitHub issue with a feature request or to report any bugs.

## Packaging and runtime dependencies

Editor services can run with the Ruby runtime provided by OpenVox Agent.
Dependencies must be available to that runtime when the editor starts the server.
The repository supports two packaging paths:

- **Standalone archives:** `bundle exec rake build` runs `gem_revendor` and includes the downloaded Ruby sources from
  `vendor/` alongside `lib/` and the root-level server scripts in ZIP and tar.gz archives.
  The server loads these vendored dependencies through its Ruby load path, without requiring Bundler at runtime.
  Run `bundle exec rake gem_revendor` when preparing a checkout for development and tests as described above.
- **Ruby gem and local VSIX:** the gemspec declares runtime dependencies, which `gem install` resolves and installs.
  The gem contains `lib/` and `bin/`; it does not include the repository's `vendor/` directory.
  `scripts/build-local-vsix.sh` builds this gem and installs it with its dependencies into the extension's
  `vendor/languageserver/gems` directory, then packages the extension.
  This path does not run `gem_revendor` and does not require Bundler at runtime.

Keep dependencies compatible with the OpenVox Agent Ruby runtime and prefer pure Ruby dependencies to avoid
platform-specific native extension builds.
