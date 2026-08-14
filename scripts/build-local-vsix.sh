#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
editor_services_dir="$(cd "${script_dir}/.." && pwd)"
vscode_dir="${OPENVOX_VSCODE_DIR:-${editor_services_dir}/../openvox-vscode}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

find_ruby() {
  local candidate

  if [[ -n "${RUBY:-}" ]]; then
    [[ -x "${RUBY}" ]] || fail "RUBY is not executable: ${RUBY}"
    echo "${RUBY}"
    return
  fi

  if command -v ruby >/dev/null 2>&1 && ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4")' 2>/dev/null; then
    command -v ruby
    return
  fi

  for candidate in "${HOME}"/.rvm/rubies/ruby-3.*/bin/ruby; do
    [[ -x "${candidate}" ]] || continue
    if "${candidate}" -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4")' 2>/dev/null; then
      echo "${candidate}"
      return
    fi
  done

  fail 'Ruby 3.4 or newer is required. Set RUBY=/path/to/ruby and try again.'
}

cleanup_old_artifacts() {
  local artifact
  local -a old_artifacts=()

  shopt -s nullglob
  old_artifacts+=("${editor_services_dir}"/openvox-editor-services-*.gem)
  old_artifacts+=("${vscode_dir}"/artifacts/openvox-vscode-local-*.vsix)
  shopt -u nullglob

  if (( ${#old_artifacts[@]} == 0 )); then
    echo 'No old local gem or VSIX artifacts found'
    return
  fi

  echo 'Removing old local build artifacts:'
  for artifact in "${old_artifacts[@]}"; do
    echo "  ${artifact}"
    rm -f -- "${artifact}"
  done
}

[[ -f "${editor_services_dir}/openvox-editor-services.gemspec" ]] || fail 'Gem specification not found.'
[[ -f "${vscode_dir}/package.json" ]] || fail "openvox-vscode not found at ${vscode_dir}"
[[ -x "${vscode_dir}/node_modules/.bin/vsce" ]] || fail "VS Code dependencies are missing. Run 'npm install' in ${vscode_dir} first."
vscode_dir="$(cd "${vscode_dir}" && pwd)"

ruby="$(find_ruby)"
ruby_bin_dir="$(cd "$(dirname "${ruby}")" && pwd)"
export PATH="${ruby_bin_dir}:${PATH}"

gem_version="$(
  cd "${editor_services_dir}"
  "${ruby}" -Ilib -rpuppet_editor_services/version -e 'print PuppetEditorServices.version'
)"
gem_name="openvox-editor-services-${gem_version}.gem"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/openvox-local-vsix.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

gem_file="${tmp_dir}/${gem_name}"
vendor_stage="${tmp_dir}/languageserver"
gem_home="${vendor_stage}/gems"
gem_bin="${vendor_stage}/gem-bin"
gem_install_root="${gem_home}/gems/openvox-editor-services-${gem_version}"
vendor_target="${vscode_dir}/vendor/languageserver"
output_file="${VSIX_OUTPUT:-${vscode_dir}/artifacts/openvox-vscode-local-${gem_version}.vsix}"

if [[ "${output_file}" != /* ]]; then
  output_file="${PWD}/${output_file}"
fi

cleanup_old_artifacts

echo "Using Ruby: ${ruby} ($("${ruby}" -e 'print RUBY_VERSION'))"
echo "Building ${gem_name}"
(
  cd "${editor_services_dir}"
  gem build openvox-editor-services.gemspec --output "${gem_file}"
)

mkdir -p "${vendor_stage}"
echo 'Installing the local gem and its dependencies into the extension'
GEM_HOME="${gem_home}" GEM_PATH="${gem_home}" gem install "${gem_file}" \
  --install-dir "${gem_home}" \
  --bindir "${gem_bin}" \
  --no-document

for executable in openvox-languageserver openvox-languageserver-sidecar; do
  [[ -f "${gem_install_root}/bin/${executable}" ]] || fail "Missing executable in local gem: ${executable}"
  cp "${gem_install_root}/bin/${executable}" "${vendor_stage}/${executable}"
done

cp -R "${gem_install_root}/lib" "${vendor_stage}/lib"
cp "${gem_install_root}/LICENSE" "${vendor_stage}/LICENSE"
rm -rf "${gem_bin}"

rm -rf "${vendor_target}"
mkdir -p "$(dirname "${vendor_target}")"
mv "${vendor_stage}" "${vendor_target}"

mkdir -p "$(dirname "${output_file}")"
echo 'Compiling and checking openvox-vscode'
(
  cd "${vscode_dir}"
  npm run compile
  node scripts/check-package.mjs
  ./node_modules/.bin/vsce package --out "${output_file}"
)

echo
echo "VSIX created: ${output_file}"
