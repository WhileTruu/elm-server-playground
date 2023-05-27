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
// REPLACE_ME_WITH_FLAGS
var app = Elm.Main.init({ flags: flags });
</script>

</body>
</html>
EOF

}



## MAKE WORKER JS

# ARGS:
#   $1 = _site/pages/NAME.html
#   $2 = compiled elm app js
#
function makeWorkerJs {
  cat <<EOF > $1
$(cat $2)

var main = this.Elm.Worker.init();

main.ports.put.subscribe(portCallback(main))

function portCallback(elmApp) {
  var f = function(portData) {
    console.log(JSON.stringify(portData));
    elmApp.ports.put.unsubscribe(f)
  };
  return f;
}

portCallback(main);
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



## codegen

echo "CODEGEN"

pages="$(find src/Pages -type f -name "*.elm")"
pages="$(echo $pages | sed 's/ /,/g' | sed 's/src\/Pages\///g')"
npx elm-codegen run --output=_temp --flags="\"$pages\""

workerJs="_temp/elm-worker.js"
elm make "_temp/Worker.elm" --optimize --output=$workerJs > /dev/null
makeWorkerJs "_temp/worker.js" $workerJs
node "_temp/worker.js" > "_site/worker.json"

## pages


echo "PAGES"
for elm in $(find _temp/pages -type f -name "*.elm")
do
    sed -i '/^module /d' "$elm"
    sed -i -e ':a' -e 'N' -e '$!ba' -e 's/{-| \n-}/ /g' "$elm"

    subpath=$(echo "${elm#pages/}" | sed 's/_temp\/pages\///g')
    name="${subpath%.elm}"
    js="_temp/$name.js"
    html="_site/$name.html"


    # FIXME replace generated file paths with the ones that are generated from (src/Pages/**/*.elm)
    # this is currently not working, as we are compiling generated files which
    # are always new
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