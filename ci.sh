#!/usr/bin/env bash
# shellcheck disable=SC1003
set -ex

# Based on https://gist.github.com/pkuczynski/8665367
# https://github.com/jasperes/bash-yaml MIT license

parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    (
        sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' |

        sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/[[:space:]]*$//g;' \
            -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
            -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)${s}[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

        awk -F"$fs" '{
            indent = length($1)/2;
           if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |

        sed -e 's/_=/+=/g' |

        awk 'BEGIN {
                FS="=";
                OFS="="
            }
            /(-|\.).*=/ {
                gsub("-|\\.", "_", $1)
            }
            { print }'
    ) < "$yaml_file"
}
create_variables() {
    local yaml_file="$1"
    local prefix="$2"
    eval "$(parse_yaml "$yaml_file" "$prefix")"
}

create_variables fairwinds-insights.yaml fairwinds_

fairwinds_images_folder=${fairwinds_images_folder:-"./tmp/images"}
fairwinds_manifests_folder=${fairwinds_manifests_folder:-"./tmp/manifests"}
fairwinds_options_tempFolder=${fairwinds_options_tempFolder:-"./tmp/options"}
fairwinds_options_junitOutput=${fairwinds_options_junitOutput:-"./tmp/junit"}

mkdir -p $fairwinds_images_folder
mkdir -p $fairwinds_manifests_folder
mkdir -p $fairwinds_options_tempFolder
mkdir -p $(dirname $fairwinds_options_junitOutput)
mkdir -p $(dirname $fairwinds_options_junitOutput)
for img in ${fairwinds_images_docker[@]}; do
    echo $img
    docker save $img -o $fairwinds_images_folder/$(basename $img | sed -e 's/[^a-zA-Z0-9]//g').tar
done

docker create --name insights-ci -e FAIRWINDS_TOKEN=$FAIRWINDS_TOKEN quay.io/fairwinds/insights-ci:0.2
docker cp . insights-ci:/insights
failed=0
docker start -a insights-ci || failed=1
docker cp insights-ci:/insights/$fairwinds_options_junitOutput $fairwinds_options_junitOutput
docker rm insights-ci
if [ "$failed" -eq "1" ]; then
    exit 1
fi
 
