#!/bin/bash

script() {
  [[ ${0##*/} = firefox_addon ]]
}

fail() {
  local _msg=$1
  local _stdout=$2
  printf '{ "failed": true, "msg": "%s", "stdout": "%s" }\n' "$_msg" "$_stdout" >&2
  { script && exit 1; } || return 1
}

result() {
  declare -g -r $1="$2" 2>/dev/null || fail "invalid result identifier: $1"
}

ensure_profile() {
  local _result_name=$1
  local _display=$2
  local _stdout
  _stdout=$(firefox ${_display:+--display $_display} -no-remote -CreateProfile default 2>&1)
  [[ $? -eq 0 ]] || fail "couldn't determine profile path" "$_stdout"
  [[ $_stdout =~ Success:\ created\ profile\ \'(.+)\'\ at\ \'(.+)\' ]] || fail "couldn't determine profile path"
  local _profile_path=${BASH_REMATCH[2]}
  result "$_result_name" ${_profile_path%/*}
}

url_slug() {
  local _url=$1
  { [[ $_url =~ https://addons.mozilla.org/.+/firefox/addon/([^/]+) ]] && printf '%s' ${BASH_REMATCH[1]}; } || return 1
}

details() {
  local _url=$1
  local _result_name=$2
  local _slug
  _slug=$(url_slug $_url) || fail "couldn't determine addon id from url: $_url"
  local _stdout
  _stdout=$(curl -s -f -L https://services.addons.mozilla.org/firefox/api/1.5/addon/$_slug)
  [[ $? -eq 0 ]] || fail "couldn't get details of addon: $_slug" "$_stdout"
  result "$_result_name" "$_stdout"
}

details_guid() {
  local _details=$1
  local _result_name=$2
  local _stdout
  _stdout=$(xmllint --xpath "normalize-space(//addon/guid)" <(printf '%s' "$_details")) || fail "couldn't determine guid of addon"
  result "$_result_name" "$_stdout" 
}

details_url() {
  local _details=$1
  local _result_name=$2
  local _stdout
  _stdout=$(xmllint --xpath "normalize-space(//addon/install[@os='Linux' or @os='ALL'])" <(printf '%s' "$_details")) || \
    fail "couldn't determine download url of addon"
  result "$_result_name" "$_stdout"
}

details_complete_theme() {
  local _details=$1
  xmllint --xpath "//addon[type/@id=2]" <(printf '%s' "$_details") >/dev/null 2>&1
}

download() {
  local _url=$1
  local _dir=$2
  local _result_name=$3
  { pushd $_dir >/dev/null && curl -s -f -L -o addon.xpi $_url && popd >/dev/null; } || fail "couldn't download addon: $url"
  result "$_result_name" "$_dir/addon.xpi"
}

parse_guid() {
  local _file=$1
  local _result_name=$2
  local IFS=$'\n'
  local _stdout_lines
  _stdout_lines=($(xmllint --shell <(unzip -p $_file install.rdf) <<EOF
    setns rdf=http://www.w3.org/1999/02/22-rdf-syntax-ns#
    setns em=http://www.mozilla.org/2004/em-rdf#
    cat /rdf:RDF/rdf:Description/em:id/text()
EOF
  ))
  [[ $? -eq 0 ]] || fail "couldn't determine guid of addon"
  result "$_result_name" "${_stdout_lines[1]}"
}

parse_internal_name() {
  local _file=$1 
  local _result_name=$2
  local IFS=$'\n'
  local _stdout_lines
  _stdout_lines=($(xmllint --shell <(unzip -p $_file install.rdf) <<EOF
    setns rdf=http://www.w3.org/1999/02/22-rdf-syntax-ns#
    setns em=http://www.mozilla.org/2004/em-rdf#
    cat /rdf:RDF/rdf:Description/em:internalName/text()
EOF
  ))
  [[ $? -eq 0 ]] || fail "couldn't determine internal name of addon"
  result "$_result_name" "${_stdout_lines[1]}"  
}

verify() {
  local _uid=$1
  [[ -d "$addon_path/$_uid" ]] && return 0
  return 1
}

install() {
  local _uid=$1
  local _file=$2
  local _stdout
  _stdout=$({ mkdir -p $addon_path && unzip $_file -d "$addon_path/$_uid" && chmod -R u=rwX,go=rX "$addon_path/$_uid"; } 2>&1)
  [[ $? -eq 0 ]] || fail "couldn't install addon: $_uid" "$_stdout"
}

uninstall() {
  local _uid=$1
  local _stdout
  _stdout=$(rm -r "$addon_path/$_uid" 2>&1)
  [[ $? -eq 0 ]] || fail "couldn't uninstall addon: $_uid" "$_stdout"
}

prefs_user() {
  local _profile=$1
  local _name=$2
  local _value=$3
  [[ -e $_profile/user.js ]] || printf '\n' > $_profile/user.js
  sed -i '/user_pref("'$_name'",/{h;s/,.*/, '$_value');/};${x;/^$/{s//user_pref("'$_name'", '$_value');/;H};x}' \
    $_profile/user.js || fail "couldn't modify prefs: $_profile/user.js" 
}

setup_tmp() {
  local _result_name=$1
  local _stdout
  _stdout=$(mktemp -d 2>&1) || fail "couldn't create tmp dir" "$_stdout"
  result "$_result_name" "$_stdout"
}

cleanup_tmp() {
  local _tmp=$1
  rm -rf $_tmp
}

main() {
  source $1

  [[ -n $url ]] || fail "missing required arguments: url"
  [[ -z $profile || -e "${profile}/prefs.js" ]] || fail "no profile found at: $profile"
  [[ -z $state || $state = "present" || $state = "absent" ]] || fail "value of state must be one of: present,absent, got: $state"

  # http://stackoverflow.com/questions/592620/check-if-a-program-exists-from-a-bash-script
  hash firefox 2>/dev/null || fail "required command not found: firefox"
  hash curl 2>/dev/null || fail "required command not found: curl"
  hash unzip 2>/dev/null || fail "required command not found: unzip"
  hash xmllint 2>/dev/null || fail "required command not found: xmllint"
  hash chmod 2>/dev/null || fail "required command not found: chmod"

  setup_tmp addon_tmp
  trap 'cleanup_tmp $addon_tmp' EXIT

  { [[ -n $profile ]] && readonly addon_profile=$profile; } || ensure_profile addon_profile $display
  readonly addon_path=${addon_profile}/extensions
  details $url addon_details
  details_guid "$addon_details" addon_guid
  readonly addon_state="${state:-present}"

  if [[ $addon_state = "present" ]]; then
    { verify $addon_guid && printf '{"changed": false}'; } || { 
      details_url "$addon_details" addon_url
      download $addon_url $addon_tmp addon_file
      install $addon_guid $addon_file
      details_complete_theme "$addon_details" && {
        parse_internal_name $addon_file addon_internal_name
        prefs_user $addon_profile general.skins.selectedSkin '"'$addon_internal_name'"'
      }
      printf '{"changed": true}' 
    }
  else
    { verify $addon_guid && uninstall $addon_guid && printf '{"changed": true}'; } || printf '{"changed": false}' 
  fi
}

{ script && main $1; } || true

