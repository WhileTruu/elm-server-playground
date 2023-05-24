#!/bin/bash

set -e -o pipefail
shopt -s nullglob



## CHECK ARGUMENTS


if [ $# -ne 1 ]; then
    printf "expecting one argument to ./build.sh like this:\n\n    ./build.sh prod\n    ./build.sh dev\n\n"
    exit 1
fi


case $1 in
    prod)
        echo "Running a PROD build.";
        is_prod () { return 0; } ;;
    dev)
        echo "Running a DEV build.";
        is_prod () { return 1; } ;;
    *)
        printf "expecting one argument to ./build.sh like this:\n\n    ./build.sh prod\n    ./build.sh dev\n\n";
        exit 1 ;;
esac



## MAKE PAGE HTML

# ARGS:
#   $1 = _site/pages/NAME.html
#   $2 = <title>
#   $3 = js
#
function makePageHtml {
  cat <<EOF > $1
<!DOCTYPE HTML>
<html lang="en">

<head>
  <title>$2</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
</head>

<body>

<script type="text/javascript">
$(cat $3)
var app = Elm.Main.init({ flags: { width: window.innerWidth, height : window.innerHeight } });
</script>

</body>
</html>
EOF

}



## DOWNLOAD BINARIES


PATH=$(pwd)/node_modules/.bin:$PATH

if ! [ -x "$(command -v elm)" ]; then
  npm install elm@latest-0.19.1
fi
if ! [ -x "$(command -v uglifyjs)" ]; then
  npm install uglify-js
fi



## GENERATE HTML


mkdir -p _site
mkdir -p _temp



## pages


echo "PAGES"
for elm in $(find pages -type f -name "*.elm")
do
    subpath="${elm#pages/}"
    name="${subpath%.elm}"
    js="_temp/$name.js"
    html="_site/$name.html"

    if [ -f $html ] && [ $(date -r $elm +%s) -le $(date -r $html +%s) ]; then
        echo "Cached: $elm"
    else
        echo "Compiling: $elm"
        mkdir -p $(dirname $js)
        mkdir -p $(dirname $html)
        rm -f elm-stuff/*/Main.elm*

        if is_prod
        then
            elm make $elm --optimize --output=$js > /dev/null
            uglifyjs $js --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' \
              | uglifyjs --mangle \
              | makePageHtml $html $name
        else
            elm make $elm --output=$js > /dev/null
            cat $js | makePageHtml $html $name
        fi
    fi
done



## REMOVE TEMP FILES


rm -rf _temp