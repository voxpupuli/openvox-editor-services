# OpenBolt Introspection

OpenBolt uses OpenVox modules to add functions and types to the language during task and plan execution. This information is not available to Editor Services when it does not run with the OpenBolt gem. The introspection script extracts metadata from OpenBolt's compatibility modules using the Language Server Sidecar and its serialisation protocol.

## Usage

Downloads a specific version of OpenBolt and extracts the module metadata for caching into Editor Services.

``` text
> bundle install

.... (lots of text)

> bundle exec ruby introspect_openbolt.rb
```

This regenerates the OpenBolt compatibility data in `/lib/puppet-languageserver/static_data`. The `bolt-*.json` filenames remain unchanged for protocol compatibility.

## Component Version Information

> This table is used by the introspection script

| Component       | Version |
| --------------- | ------- |
| OpenBolt        | 5.6.0    |
| Editor Services | 2.0.4   |
