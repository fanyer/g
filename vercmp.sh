#!/bin/bash

VER_SPLIT_SED='s/\./ /g;s/\([[:digit:]]\)\([^[:digit:] ]\)/\1 \2/g;s/\([^[:digit:] ]\)\([[:digit:]]\)/\1 \2/g'

# Compare with one element of version components
_ver_cmp_1() {
  [[ "$1" = "$2" ]] && return 0
  if [[ -z "${1//[[:digit:]]/}" ]] && [[ -z "${2//[[:digit:]]/}" ]]; then
    # Both $1 and $2 are numbers
    # Using arithmetic comparison
    (( $1 > $2 )) && return 1
    (( $1 < $2 )) && return 2
  else
    # Either or both are not numbers, containing non-digit characters
    # Using string comparison
    [[ "$1" > "$2" ]] && return 1
    [[ "$1" < "$2" ]] && return 2
  fi
  # This should not be happening
  exit 1
}

vercmp() {
  local A B i result
  A=($(sed "$VER_SPLIT_SED"  <<< "$1"))
  B=($(sed "$VER_SPLIT_SED"  <<< "$2"))
  i=0
  while (( i < ${#A[@]} )) && (( i < ${#B[@]})); do
    _ver_cmp_1 "${A[i]}" "${B[i]}"
    result=$?
    [[ $result =~ [12] ]] && return $result
    let i++
  done
  # Which has more, then it is the newer version
  _ver_cmp_1 "${#A[i]}" "${#B[i]}"
  return $?
}
