#!/bin/bash

main(){

    
     #inputs: 
    local gitToken=
    local helmChartRepo=
    local helmArtifactsRepo=

    #calculated:
    local artifactsFolder
    local charts_dir=charts
    local chartsFolder=

    parse_command_line "$@"


    stripedChartsurl=$(echo "$helmChartRepo" |sed 's/https\?:\/\///')
    stripedArtifactsurl=$(echo "$helmArtifactsRepo" |sed 's/https\?:\/\///')

    IFS='/' 
    read -r -a artifactsUrlArr <<< "$stripedArtifactsurl"
    artifactsFolder=$(echo "${artifactsUrlArr[2]}" | cut -f 1 -d '.')
    echo "Artifacts folder: $artifactsFolder"
    git clone "https://doronjo:${gitToken}@${stripedArtifactsurl}" 

    IFS='/' 
    read -r -a chartsUrlArr <<< "$stripedChartsurl"
    chartsFolder=$(echo "${chartsUrlArr[2]}" | cut -f 1 -d '.')
    echo "Charts folder: $chartsFolder"
    git clone "https://doronjo:${gitToken}@${stripedChartsurl}" 


    cd "$chartsFolder"
    git checkout main


    echo "Discovering changed charts since last commit..."
    local changed_charts=()
    readarray -t changed_charts <<< "$(lookup_changed_charts)"

    if [[ -n "${changed_charts[*]}" ]]; then
        echo "Start processing changes"
        for chart in "${changed_charts[@]}"; do
            if [[ -d "$chart" ]]; then
                 package_chart "$chart"
            else
                echo "Chart '$chart' no longer exists in repo. Skipping it..."
            fi
        done
        push_artifacts
    else
        echo "Nothing to do. No chart changes detected."
    fi

}



lookup_latest_tag() {
     git rev-parse origin/main
}

lookup_changed_charts() {
    local commit="$1"

    local changed_files
    changed_files=$(git diff --find-renames --name-only HEAD^ HEAD -- "$charts_dir")

    local depth=$(( $(tr "/" "\n" <<< "$charts_dir" | sed '/^\(\.\)*$/d' | wc -l) + 1 ))
    local fields="1-${depth}"

    cut -d '/' -f "$fields" <<< "$changed_files" | uniq | filter_charts
}

filter_charts() {
    while read -r chart; do
        [[ ! -d "$chart" ]] && continue
        local file="$chart/Chart.yaml"
        if [[ -f "$file" ]]; then
            echo "$chart"
        else
           echo "WARNING: $file is missing, assuming that '$chart' is not a Helm chart. Skipping." 1>&2
        fi
    done
}

package_chart() {
    local chart="$1"
    IFS='/' 
    read -r -a destArr <<< "$chart"

    echo "source ./${destArr[0]}/${destArr[1]}"
    echo "dest ../${artifactsFolder}/${destArr[1]}"

    echo "Packaging chart '$destArr'..."
    helm package "./${destArr[0]}/${destArr[1]}"  -d "../${artifactsFolder}/${destArr[1]}/"
    helm repo index "../${artifactsFolder}"
}


push_artifacts(){

    cd "../${artifactsFolder}"
    git add .
    git commit -m "${destArr[1]} new helm pack"
    git push
}



show_help() {
cat << EOF
Usage: $(basename "$0") <options>
    -h, --help               Display help
    -c, --charts-repo        The chart repo
    -a, --artifacts-repo     The charts artfiactory repo, helm packages repo
    -g, --git-token          The Github repo user token, should be the same for both repos 
EOF
}


parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -c|--charts-repo)
                if [[ -n "${2:-}" ]]; then
                    helmChartRepo="$2"
                    shift
                else
                    echo "ERROR: '-c|--charts-repo' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -a|--artifacts-repo)
                if [[ -n "${2:-}" ]]; then
                    helmArtifactsRepo="$2"
                    shift
                else
                    echo "ERROR: '-a|--artifacts-repo' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -g|--git-token)
                if [[ -n "${2:-}" ]]; then
                    gitToken="$2"
                    shift
                else
                    echo "ERROR: '-t|--git-token' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done

    if [[ -z "$helmChartRepo" ]]; then
        echo "ERROR: '-c|--chart-repo' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$helmArtifactsRepo" ]]; then
        echo "ERROR: '-a|--artifacts-repo' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$gitToken" ]]; then
        echo "ERROR: '-g|--git-token' is required." >&2
        show_help
        exit 1
    fi

}


main "$@"