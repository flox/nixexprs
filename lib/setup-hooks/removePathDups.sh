function removePathDups {
  for varname in "$@"; do
    declare -A __seen
    __rewrite=
    for i in $(local IFS=:; echo ${!varname}); do
      if [ -z "${__seen[$i]}" ]; then
        __rewrite="$__rewrite${__rewrite:+:}$i"
        __seen[$i]=1
      fi
    done
    export $varname="$__rewrite"
    unset __seen
    unset __rewrite
  done
}
function removeAllPathDups {
  removePathDups "PATH" "PYTHONPATH" "PERL5LIB"
}
prePhases="removeAllPathDups ${prePhases:-}"
