#!/bin/bash
# A collection of functions to interact with Minecraft servers running in screen

BASHCRAFT_VERSION="0.1"

# = Raw functions ==============================================================

# Run external commands with sudo?
# Set via function use_screen_sudo
_USE_SUDO=""

# Associative arrays to store server screen related data
declare -A server_names
declare -A server_working_dir
declare -A server_latest_log_file
declare -A server_pid
declare -A server_aliases

# Set screen commands to use sudo
function use_screen_sudo() {
	local state=${1:-"true"}
	if [[ "${state}" == "true" ]]; then
		_USE_SUDO="sudo"
	else
		_USE_SUDO=""
	fi
}

# Looks for screens running java and papermc.jar
# Fetch and store all associated data
function fetch_screen_servers() {
	# Store in an array
	screens=($(${_USE_SUDO} ps aux | grep -E 'SCREEN.*java.*papermc.jar' | awk '{
		for(i=1;i<=NF;i++) {
			if($i ~ /SCREEN/) {
				for(j=i+1;j<=NF;j++) {
					if($j !~ /^-/) {
						print $j
						break
					}
				}
				break
			}
		}
	}'))
	
	# Cache the server screen names
	for screen in "${screens[@]}"; do
		server_names[$screen]=$screen
	done
	
	# Cache the working directory for each server screen
	for screen in "${screens[@]}"; do
		_cache_server_working_dir $screen
	done
	
	# Cache the latest log file path for each server screen
	for screen in "${screens[@]}"; do
		_cache_server_latest_log_file $screen
	done
}

# Internal function to cache the working directory for a server screen
function _cache_server_working_dir() {
	# Look for the screen name in the associative array
	if [[ ! -n "${server_working_dir[$1]}" ]]; then
		local pid=$(${_USE_SUDO} screen -ls | grep "${1}" | awk '{print $1}' | cut -d. -f1)
		if [ -n "$pid" ]; then
			server_pid[$1]=$pid
			server_working_dir[$1]=$(${_USE_SUDO} pwdx "$pid" | awk '{print $2}')
		fi
	fi
}

# Internal function to cache the latest log file path for a server screen
function _cache_server_latest_log_file() {
	# Just get the working directory and append "log/latest.log"
	server_latest_log_file[$1]="${server_working_dir[$1]}/logs/latest.log"
}

# Set an alias for a server screen name
function set_server_alias() {
	server_aliases[$1]=$2
}

# Get the server screen name from an alias
function get_server_alias() {
	echo "${server_aliases[$1]}"
}

# Returns the total server count
function get_server_count() {
	echo "${#server_names[@]}"
}

# Returns an array of all server screen names
function get_server_names() {
	echo "${server_names[@]}"
}

# Returns the working directory for the specified server screen name
function get_server_working_dir() {
	echo "${server_working_dir[$1]}"
}

# Returns the latest log file path for the specified server screen name
function get_server_latest_log_file() {
	# Get it from the associative array
	echo "${server_latest_log_file[$1]}"
}

# Verify if a server screen name exists
function server_name_exists() {
	${_USE_SUDO} screen -ls | grep -q "$1"
}

# Cleans the output from the server log file
function clean_log_output() {
	local log_line="$1"
	local in_brackets=false
	local output=""
	local skip_section=false 
	
	# Iterate through each character in the log line
	for ((i=0; i<${#log_line}; i++)); do
		char="${log_line:$i:1}"  # Get the current character
		if [[ "$char" == "[" ]]; then
			in_brackets=true  # Entering a bracketed section
		elif [[ "$char" == "]" ]]; then
			in_brackets=false  # Exiting a bracketed section
		elif [[ "$char" == ":" && "${log_line:$((i+1)):1}" == " " ]]; then
			skip_section=true  # Entering a section starting with ": "
		elif [[ "$char" == " " && "$skip_section" == true ]]; then
			skip_section=false  # Exiting a section starting with ": "
		elif [[ "$char" != " " && "$in_brackets" == false && "$skip_section" == false ]]; then
			output="${log_line:$i}"  # Found the start of the output
			break
		fi
	done

	# Return the output, trimming leading spaces
	echo "$output" | sed 's/^ *//'
}

# Cleans the data types of Minecraft and converts [I; ] arrays to Bash arrays
function clean_minecraft_data_type() {
	local data="$1"
	
	# Minecraft returns entity data with an appended entity type, like "f", "d", "b", "s", and "L"
	data=$(echo "$data" | sed -E 's/([0-9]+\.[0-9]+)[fd]/\1/g; s/([0-9]+)[bsL]/\1/g')
	
	# Convert [I; ] arrays to Bash arrays
	if [[ "$data" =~ \[I\;([0-9,\ -]+)\] ]]; then
		local array_elements="${BASH_REMATCH[1]}"
		IFS=', ' read -r -a bash_array <<< "$array_elements"
		echo "${bash_array[@]}"
	else
		echo "$data"
	fi
}

# Turns an array into a string with the specified separator (optional, defaults to comma)
function array_to_string() {
	local separator=","
	if [[ $# -gt 1 ]]; then
		separator="${!#}"
		set -- "${@:1:$#-1}"
	fi
	local IFS="$separator"
	echo "$*"
}

# Sends a command to the specified server screen name and returns nothing
function send_server_command() {
	# Check if the server screen name exists
	if ! server_name_exists $1; then
		echo ""
		return
	fi
	
	# Execute the command
	${_USE_SUDO} screen -S $1 -X stuff "$2^M"
}

# Sends a command to the specified server screen name and returns the output
# Arguments:
# 1: Server screen name
# 2: Command to send
# 3: Match regex to filter output
# 4: End regex to stop reading output
# 5: Retry regex to retry reading output
function send_server_command_await_output() {
	# Check if the server screen name exists
	if ! server_name_exists $1; then
		echo ""
		return
	fi
	
	# Which log file are we reading from?
	local log_file="${server_latest_log_file[$1]}"
	
	# Do we have a regex to match the output?
	local match_regex=${3:-""}
	
	# Do we have an expected end line regex?
	local end_regex=${4:-""}
	
	# Do we have an expected retry line regex?
	local retry_regex=${5:-""}
	
	# Store the length of the log file currently
	local current_line_count=$(wc -l < "$log_file")
	
	# Execute the command
	${_USE_SUDO} screen -S $1 -X stuff "$2^M"
	
	# Wait for the log file to have MORE lines
	while [[ $(wc -l < "$log_file") -le $current_line_count ]]; do
		sleep 0.0005
	done
	
	# While we have to try, do a try
	local needs_retry=true
	local skip_next_line=false
	local found_lines=()
	while [[ "$needs_retry" == true ]]; do
		needs_retry=false
		found_lines=()
		
		# Get the new lines since the last check
		new_lines=$(tail -n $(( $(wc -l < "$log_file") - $current_line_count )) "$log_file")
		newest_line=$(clean_log_output "$(tail -n 1 <<< "$new_lines")")
		
		#echo "DEBUG: Newest line: $newest_line" >&2
		
		# Check if the newest line is the retry line
		if [[ -n "$retry_regex" ]]; then
			if [[ "$newest_line" =~ $retry_regex ]]; then
				skip_next_line=true
				needs_retry=true
				continue
			fi
		fi
		
		# DEBUG, print the new lines!
		#echo "====NEW LINES $(( $(wc -l < "$log_file") - $current_line_count ))====" >&2
		#echo "$new_lines" >&2
		#echo "====END NEW LINES====" >&2
		
		while IFS= read -r line; do
			# Clean the line
			cleaned_line=$(clean_log_output "$line")
			
			# Skip the next line if needed
			# This is used to skip any retry lines
			if [[ "$skip_next_line" == false ]]; then
				
				# Check if the line matches the regex if provided
				if [[ -n "$match_regex" ]]; then
					if [[ "$cleaned_line" =~ $match_regex ]]; then
						found_lines+=("$cleaned_line")
					fi
				else
					found_lines+=("$cleaned_line")
				fi
				
				# Check if the line matches the end regex if provided
				if [[ -n "$end_regex" && "$cleaned_line" =~ $end_regex ]]; then
					break
				#else
				#	echo "DEBUG: Line $cleaned_line does not match end regex $end_regex" >&2
				fi
			else
				skip_next_line=false
			fi
		done <<< "$new_lines"
	done
	
	# Return the filtered lines
	if [[ ${#found_lines[@]} -gt 0 ]]; then
		for found_line in "${found_lines[@]}"; do
			echo "$found_line"
		done
	fi
}

# = Minecraft wrapper functions ================================================

# Send the "say" command to a server
function minecraft_say() {
	send_server_command $1 "minecraft:say $2"
}

# Send a "notice" to a server
# This uses tellraw to send a notice to all players
function minecraft_notice() {
	local color=${3:-"gold"}
	send_server_command $1 "minecraft:tellraw @a {\"text\":\"$2\",\"color\":\"$color\"}"
}

# Send a "save" command to a server
# Waits for the save to complete
function minecraft_save_all() {
	local result=$(send_server_command_await_output $1 "minecraft:save-all" '' 'Saved the game' 'Saving the game .*')
}

# Send a "list" command to a server
# Returns an array of players online
function minecraft_list() {
	local result=$(send_server_command_await_output $1 "minecraft:list" 'There are [0-9]+ of a max of [0-9]+ players online: ')
	# Extract the player names after "online: " and split by spaces
	players=($(echo "$result" | sed 's/.*online: //'))
	
	# Return the array
	echo "${players[@]}"
}

# Send a "playsound" command to a server
# Arguments:
# 1: Server screen name
# 2: Sound to play
# 3: Source of the sound
# 4: Targets to play the sound to
# 5: X position
# 6: Y position
# 7: Z position
# 8: Volume (1 is 100%, values above 1 makes the sound travel further)
# 9: Pitch (1 is normal, 2.0 is max and double speed)
# 10: Minimum volume (increase to force the sound to be audible from any distance)
function minecraft_playsound() {
	local sound=$2
	local source=${3:-"master"}
	local targets=${4:-"@a"}
	local pos_x=${5:-"~"}
	local pos_y=${6:-"1000"}
	local pos_z=${7:-"~"}
	local volume=${8:-1000000}
	local pitch=${9:-1}
	local min_volume=${10:-1}
	send_server_command $1 "minecraft:playsound $sound $source $targets $pos_x $pos_y $pos_z $volume $pitch $min_volume"
}

# Send a "summon" command to a server
function minecraft_summon() {
	local entity=$2
	local pos_x=${3:-"~"}
	local pos_y=${4:-"~"}
	local pos_z=${5:-"~"}
	local nbts=${6:-""}
	send_server_command $1 "minecraft:summon $entity $pos_x $pos_y $pos_z $nbts"
}

# Send a "kill" command to a server
function minecraft_kill() {
	local target=${2:-"@e"}
	local selector=$(IFS=','; echo "${*:3}")
	send_server_command $1 "minecraft:kill $target[$selector]"
}

# Send a "data get entity" command to a server
function minecraft_data_get_entity() {
	local target=${2:-"@n"}
	local selector=$(IFS=','; echo "${*:3:$#-3}") # This takes every item except the last one
	local path=${@: -1} # This takes the last item
	local result=$(send_server_command_await_output $1 "minecraft:data get entity $target[$selector] $path" '.* has the following entity data: ')
	local processed_result=$(echo "$result" | sed 's/.*entity data: //')
	local cleaned_result=$(clean_minecraft_data_type "$processed_result")
	echo "$cleaned_result"
}

# Send an "effect" command to a server
function minecraft_effect() {
	local state=${2:-"give"}
	local target=${3:-"@a"}
	local effect=${@: -4:1}
	local duration=${@: -3:1}
	local amplifier=${@: -2:1}
	local hidden=${@: -1}
	local selector=$(IFS=','; echo "${*:4:$#-7}")
	send_server_command $1 "minecraft:effect $state $target[$selector] $effect $duration $amplifier $hidden"
}

# Send a "particle" command to a server
function minecraft_particle() {
	local particle=${2:-"minecraft:poof"}
	local pos_x=${3:-"~"}
	local pos_y=${4:-"~"}
	local pos_z=${5:-"~"}
	local delta_x=${6:-"0"}
	local delta_y=${7:-"0"}
	local delta_z=${8:-"0"}
	local speed=${9:-"0.1"}
	local count=${10:-"50"}
	local mode=${11:-"normal"}
	local viewers=${12:-"@a"}
	send_server_command $1 "minecraft:particle $particle $pos_x $pos_y $pos_z $delta_x $delta_y $delta_z $speed $count $mode $viewers"
}