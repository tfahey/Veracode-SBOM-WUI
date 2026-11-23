#!/usr/bin/env bash
#  Author: Ben Halpern
#  Version: v2.1.2
#  Veracode 2024
#  LICENSE: MIT
#  SBOM Utility to generate an SBOM using Veracode SCA Information from an Upload and Scan or Agent-Based Scan
#  Inspired by the work done by:
#    Alexander Klimetschek : https://unix.stackexchange.com/questions/146570/arrow-key-enter-menu
#    gilmore867 : https://github.com/gilmore867/Veracode-SBOM-GUI
# This version does not use docker containers

IFS=$'\n\t'

readonly VERSION="v2.1.2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OUTPUT_DIR="${SCRIPT_DIR}/.sbom"
readonly VERACODE_API_BASE="https://api.veracode.com"
DEBUG="${DEBUG:-0}"


##################################################################
#
# Menu function
#
##################################################################

# Renders a text based list of options that can be selected by the
# user using up, down and enter keys and returns the chosen option.
#
#   Arguments   : list of options, maximum of 256
#                 "opt1" "opt2" ...
#   Return value: selected index (0 for opt1, 1 for opt2 ...)
function select_option {
    # Menu function from this post, with modifications as needed: https://unix.stackexchange.com/questions/146570/arrow-key-enter-menu
    # It was either this one or one using dialog, but didn't want to have to install anything on the system to get it to work
    # little helpers for terminal print control and key input
    ESC=$( printf "\033")
    cursor_blink_on()  { 
      printf "$ESC[?25h"; 
    }
    cursor_blink_off() { 
      printf "$ESC[?25l"; 
    }
    cursor_to()        { 
      printf "$ESC[$1;${2:-1}H"; 
    }
    print_option()     { 
      printf "   %s""$1"  2>/dev/null; 
    }
    print_selected()   { 
      printf "  $ESC[7m $1 $ESC[27m"  2>/dev/null; 
    }
    get_cursor_row()   { 
      IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; 
    }
    key_input()        { 
      read -s -n3 key 2>/dev/null >&2
      if [[ $key = $ESC[A ]]; then echo up;    fi
      if [[ $key = $ESC[B ]]; then echo down;  fi
      if [[ $key = ""     ]]; then echo enter; fi; 
    }

    # initially print empty new lines (scroll down if at bottom of screen)
    for opt; do printf "\n"; done

    # determine current screen position for overwriting the options
    local lastrow=`get_cursor_row`
    local startrow=$(($lastrow - $#))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
        # print options by overwriting the last lines
        local idx=0
        for opt; do
            cursor_to $(($startrow + $idx))
            if [ $idx -eq $selected ]; then
                print_selected "$opt"
            else
                print_option "$opt"
            fi
            ((idx++))
        done

        # user key control
        case `key_input` in
            enter) break;;
            up)    ((selected--));
                   if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi;;
            down)  ((selected++));
                   if [ $selected -ge $# ]; then selected=0; fi;;
        esac
    done

    # cursor position back to normal
    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $selected
}

##################################################################
#
# Error handling and utility functions
#
##################################################################

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

SBOM Generator using Veracode SCA Information

OPTIONS:
  -p, --profile NAME              Use credential profile NAME
  -h, --help                      Show this help message
  --debug                         Enable debug output

EXAMPLES:
  $0
  $0 --profile production
  VERACODE_API_PROFILE=production $0

For more information, see README.md
EOF
}

die() {
	local msg="$1"
	echo "Error: $msg" >&2
	exit 1
}

cleanup_terminal() {
	printf "\033[?25h"
	stty echo 2>/dev/null || true
}

require_command() {
	local cmd="$1"
	if ! command -v "$cmd" &>/dev/null; then
		die "Required command not found: $cmd"
	fi
}

check_dependencies() {
	require_command "http"
	require_command "jq"
	require_command "stty"
	require_command "python3"
}

initialize_output_dir() {
	if [[ ! -d "$OUTPUT_DIR" ]]; then
		mkdir -p "$OUTPUT_DIR" || die "Failed to create output directory: $OUTPUT_DIR"
	fi
}

setup_trap() {
	trap 'cleanup_terminal; exit 130' INT TERM
}

parse_arguments() {
	local profile=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-p | --profile)
				profile="$2"
				if [[ -z "$profile" ]]; then
					die "Option $1 requires a non-empty argument"
				fi
				shift 2
				;;
			--debug)
				DEBUG=1
				shift
				;;
			-h | --help)
				usage
				exit 0
				;;
			-*)
				die "Unknown option: $1"
				;;
			*)
				die "Unexpected argument: $1"
				;;
		esac
	done

	if [[ -z "$profile" ]]; then
		profile="${VERACODE_API_PROFILE:-}"
	fi

	if [[ -n "$profile" ]]; then
		export VERACODE_API_PROFILE="$profile"
		if [[ "$DEBUG" == "1" ]]; then
			echo "Using credential profile: $profile" >&2
		fi
	fi
}

##################################################################
#
# API and data loading functions
#
##################################################################

load_applications() {
	local json_file="$OUTPUT_DIR/applications.json"
	local app_ids=()
	local app_names=()

	http --auth-type=veracode_hmac -o "$json_file" "$VERACODE_API_BASE/appsec/v1/applications" || die "Failed to fetch: $VERACODE_API_BASE/appsec/v1/applications"

	local idoutput
	idoutput=$(cat "$json_file" | jq -r '._embedded.applications[].guid' )

	while IFS= read -r line; do
		app_ids+=("$line")
	done <<< "$idoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Application IDs:" >&2
		for id in "${app_ids[@]}"; do
			echo "  $id" >&2
		done
	fi

	local nameoutput
	nameoutput=$(cat "$json_file" | jq -r '._embedded.applications[].profile.name')

	while IFS= read -r line; do
		app_names+=("$line")
	done <<< "$nameoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Application names:" >&2
		for name in "${app_names[@]}"; do
			echo "  $name" >&2
		done
	fi

	printf '%s\n' "${app_ids[@]}" > "$OUTPUT_DIR/.app_ids.tmp"
	printf '%s\n' "${app_names[@]}" > "$OUTPUT_DIR/.app_names.tmp"
}

load_workspaces() {
	local json_file="$OUTPUT_DIR/workspaces.json"
	local workspace_ids=()
	local workspace_names=()

	http --auth-type=veracode_hmac -o "$json_file" "$VERACODE_API_BASE/srcclr/v3/workspaces" || die "Failed to fetch: $VERACODE_API_BASE/srcclr/v3/workspaces"

	local idoutput
	idoutput=$(cat "$json_file" | jq -r '._embedded.workspaces' | grep -i '"id":' | cut -d '"' -f4)

	while IFS= read -r line; do
		workspace_ids+=("$line")
	done <<< "$idoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Workspace IDs:" >&2
		for id in "${workspace_ids[@]}"; do
			echo "  $id" >&2
		done
	fi

	local nameoutput
	nameoutput=$(cat "$json_file" | jq -r '._embedded.workspaces' | grep -i '"name":' | cut -d '"' -f4)

	while IFS= read -r line; do
		workspace_names+=("$line")
	done <<< "$nameoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Workspace names:" >&2
		for name in "${workspace_names[@]}"; do
			echo "  $name" >&2
		done
	fi

	printf '%s\n' "${workspace_ids[@]}" > "$OUTPUT_DIR/.workspace_ids.tmp"
	printf '%s\n' "${workspace_names[@]}" > "$OUTPUT_DIR/.workspace_names.tmp"
}

load_projects() {
	local workspace_id="$1"
	local json_file="$OUTPUT_DIR/projects.json"
	local project_ids=()
	local project_names=()

	http --auth-type=veracode_hmac -o "$json_file" "$VERACODE_API_BASE/srcclr/v3/workspaces/$workspace_id/projects?type=agent" || die "Failed to fetch projects for workspace"

	if [[ "$DEBUG" == "1" ]]; then
		cat "$json_file" | jq -r '._embedded.projects' | grep -i '"name":' -F | cut -d '"' -f4
	fi

	local idoutput
	idoutput=$(cat "$json_file" | jq -r '._embedded.projects' | grep -i '"id":' | cut -d '"' -f4)

	while IFS= read -r line; do
		project_ids+=("$line")
	done <<< "$idoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Project IDs:" >&2
		for id in "${project_ids[@]}"; do
			echo "  $id" >&2
		done
	fi

	local nameoutput
	nameoutput=$(cat "$json_file" | jq -r '._embedded.projects' | grep -i '"name":' | cut -d '"' -f4)

	while IFS= read -r line; do
		project_names+=("$line")
	done <<< "$nameoutput"

	if [[ "$DEBUG" == "1" ]]; then
		echo "Project names:" >&2
		for name in "${project_names[@]}"; do
			echo "  $name" >&2
		done
	fi

	printf '%s\n' "${project_ids[@]}" > "$OUTPUT_DIR/.project_ids.tmp"
	printf '%s\n' "${project_names[@]}" > "$OUTPUT_DIR/.project_names.tmp"
}

generate_application_sbom() {
	local app_id="$1"

	http --auth-type=veracode_hmac -o "$OUTPUT_DIR/$app_id.json" "$VERACODE_API_BASE/srcclr/sbom/v1/targets/$app_id/cyclonedx?type=application" || die "Failed to generate SBOM for application"
	echo "CycloneDx SBOM written to $OUTPUT_DIR/$app_id.json"
}

generate_agent_sbom() {
	local project_id="$1"

	http --auth-type=veracode_hmac -o "$OUTPUT_DIR/$project_id.json" "$VERACODE_API_BASE/srcclr/sbom/v1/targets/$project_id/cyclonedx?type=agent" || die "Failed to generate SBOM for project"
	echo "CycloneDx SBOM written to $OUTPUT_DIR/$project_id.json"
}

##################################################################
#
# Main script execution
#
##################################################################

parse_arguments "$@"
check_dependencies
setup_trap
initialize_output_dir

if [[ "$DEBUG" == "1" ]]; then
	echo "SBOM Generator v$VERSION" >&2
	echo "Output directory: $OUTPUT_DIR" >&2
fi

clear

#pip install httpie
#pip install veracode-api-signing
# TODO: Add option to ask if they want to use a docker container or not and then use the necessary one based on that
shopt -s expand_aliases
# alias
alias 'veracode-http'='http --auth-type=veracode_hmac'
DEBUG=0

sbom_type_options[0]="Application Profile SBOM"
sbom_type_options[1]="Agent Based SBOM"

select_option "${sbom_type_options[@]}"
choice=$?

echo "Chosen index = $choice"
echo "        value = ${sbom_type_options[$choice]}"

if [ "$choice" == "0" ]; then
	echo "Application Profile SBOM"

	load_applications

	app_ids=()
	while IFS= read -r line; do
		app_ids+=("$line")
	done < "$OUTPUT_DIR/.app_ids.tmp"

	app_names=()
	while IFS= read -r line; do
		app_names+=("$line")
	done < "$OUTPUT_DIR/.app_names.tmp"

	options=()
	for i in "${!app_names[@]}"; do
		options+=("${app_names[$i]} : ${app_ids[$i]}")
	done

	echo "Select an application"
	echo "Select one option using up/down keys and enter to confirm:"
	echo

	select_option "${options[@]}"
	app_choice=$?

	echo "Chosen index = $app_choice"
	echo "        value = ${options[$app_choice]}"

	generate_application_sbom "${app_ids[$app_choice]}"

	rm -f "$OUTPUT_DIR/.app_ids.tmp" "$OUTPUT_DIR/.app_names.tmp"

elif [ "$choice" == "1" ]; then
	echo "Agent Based SBOM"

	load_workspaces

	workspace_ids=()
	while IFS= read -r line; do
		workspace_ids+=("$line")
	done < "$OUTPUT_DIR/.workspace_ids.tmp"

	workspace_names=()
	while IFS= read -r line; do
		workspace_names+=("$line")
	done < "$OUTPUT_DIR/.workspace_names.tmp"

	options=()
	for i in "${!workspace_names[@]}"; do
		options+=("${workspace_names[$i]} : ${workspace_ids[$i]}")
	done

	echo "Select a workspace"
	echo "Select one option using up/down keys and enter to confirm:"
	echo

	select_option "${options[@]}"
	workspace_choice=$?

	echo "Chosen index = $workspace_choice"
	echo "        value = ${options[$workspace_choice]}"

	load_projects "${workspace_ids[$workspace_choice]}"

	project_ids=()
	while IFS= read -r line; do
		project_ids+=("$line")
	done < "$OUTPUT_DIR/.project_ids.tmp"

	project_names=()
	while IFS= read -r line; do
		project_names+=("$line")
	done < "$OUTPUT_DIR/.project_names.tmp"

	options=()
	for i in "${!project_names[@]}"; do
		if [[ -z "${project_names[$i]}" ]]; then
			echo "No Project Found"
			continue
		fi
		options+=("${project_names[$i]} : ${project_ids[$i]}")
	done

	if [[ ${#options[@]} -eq 0 ]]; then
		die "No projects found in workspace"
	fi

	echo "Select a project"

	select_option "${options[@]}"
	project_choice=$?

	echo "Chosen index = $project_choice"
	echo "        value = ${options[$project_choice]}"

	generate_agent_sbom "${project_ids[$project_choice]}"

	rm -f "$OUTPUT_DIR/.workspace_ids.tmp" "$OUTPUT_DIR/.workspace_names.tmp"
	rm -f "$OUTPUT_DIR/.project_ids.tmp" "$OUTPUT_DIR/.project_names.tmp"
fi
