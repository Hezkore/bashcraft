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
declare -A server_bossbars

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
# Text seen by all players
# Arguments:
# 1: Server
# 2: Message
function minecraft_say() {
	send_server_command $1 "minecraft:say $2"
}

# Send a custom notice to a server
# This uses tellraw to send a notice to all players
# Arguments:
# 1: Server
# 2: Message
# 3: Color (optional, defaults to "gold")
function minecraft_notice() {
	local color=${3:-"gold"}
	send_server_command $1 "minecraft:tellraw @a {\"text\":\"$2\",\"color\":\"$color\"}"
}

# Send a custom notice to a specific player on a server
# This is the same as minecraft_notice but with a target selector
# Arguments:
# 1: Server
# 2: Target selector
# 3: Message
# 4: Color (optional, defaults to "gold")
function minecraft_notice_to() {
	local color=${4:-"gold"}
	send_server_command $1 "minecraft:tellraw $2 {\"text\":\"$3\",\"color\":\"$color\"}"
}

# Send a "save" command to a server
# Waits for the save to complete
# Arguments:
# 1: Server
function minecraft_save_all() {
	local result=$(send_server_command_await_output $1 "minecraft:save-all" '' 'Saved the game' 'Saving the game .*')
}

# Send a "list" command to a server
# Returns an array of players online
# Arguments:
# 1: Server
function minecraft_list() {
	local result=$(send_server_command_await_output $1 "minecraft:list" 'There are [0-9]+ of a max of [0-9]+ players online: ')
	# Extract the player names after "online: " and split by spaces
	players=($(echo "$result" | sed 's/.*online: //'))
	
	# Return the array
	echo "${players[@]}"
}

# Send a "playsound" command to a server
# Arguments:
# 1: Server
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
# Arguments:
# 1: Server
# 2: Entity to summon
# 3: X position (optional, defaults to "~")
# 4: Y position (optional, defaults to "~")
# 5: Z position (optional, defaults to "~")
# 6: NBTs (optional, defaults to "")
function minecraft_summon() {
	local entity=$2
	local pos_x=${3:-"~"}
	local pos_y=${4:-"~"}
	local pos_z=${5:-"~"}
	local nbts="${@:6}"
	send_server_command $1 "minecraft:summon $entity $pos_x $pos_y $pos_z $nbts"
}

# Send a "kill" command to a server
# Arguments:
# 1: Server
# 2: Target selector (optional, defaults to "@e")
function minecraft_kill() {
	local target=${2:-"@e"}
	send_server_command $1 "minecraft:kill $target"
}

# Send a "data get entity" command to a server
# Arguments:
# 1: Server
# 2: Target selector (optional, defaults to "@n")
# 3: Path to the data
function minecraft_data_get_entity() {
	local target=${2:-"@n"}
	local path=$3
	local result=$(send_server_command_await_output $1 "minecraft:data get entity $target $path" '.* has the following entity data: ')
	local processed_result=$(echo "$result" | sed 's/.*entity data: //')
	local cleaned_result=$(clean_minecraft_data_type "$processed_result")
	echo "$cleaned_result"
}

# Send an "effect" command to a server
# Arguments:
# 1: Server
# 2: State (optional, defaults to "give")
# 3: Target selector (optional, defaults to "@a")
# 4: Effect
# 5: Duration (optional, defaults to "infinite")
# 6: Amplifier (optional, defaults to 0)
# 7: Hidden (optional, defaults to false)
function minecraft_effect() {
	local state=${2:-"give"}
	local target=${3:-"@a"}
	local effect=$4
	local duration=${5:-"infinite"}
	local amplifier=${6:-0}
	local hidden=${7:-false}
	send_server_command $1 "minecraft:effect $state $target $effect $duration $amplifier $hidden"
}

# Send a "particle" command to a server
# Arguments:
# 1: Server
# 2: Particle name (optional, defaults to "minecraft:poof")
# 3: X position (optional, defaults to "~")
# 4: Y position (optional, defaults to "~")
# 5: Z position (optional, defaults to "~")
# 6: Delta X (optional, defaults to 0)
# 7: Delta Y (optional, defaults to 0)
# 8: Delta Z (optional, defaults to 0)
# 9: Speed (optional, defaults to 0.1)
# 10: Count (optional, defaults to 50)
# 11: Mode (optional, defaults to "normal")
# 12: Viewers (optional, defaults to "@a")
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

# Send "forceload" command to a server
# Arguments:
# 1: Server
# 2: State add/remove
# 3: [from] Block X position
# 4: [from] Block Z position
# 5: To Block X position (optional)
# 6: To Block Z position (optional)
function minecraft_forceload() {
	local state=$2
	local pos_x=$3
	local pos_z=$4
	local to_pos_x=$5
	local to_pos_z=$6
	
	send_server_command $1 "minecraft:forceload $state $pos_x $pos_z $to_pos_x $to_pos_z"
}

# Send "forceload remove all" command to a server
# Removes all chunks loaded with the forceload command
# Arguments:
# 1: Server
function minecraft_forceload_remove_all() {
	send_server_command $1 "minecraft:forceload remove all"
}

# Send "set block" command to a server
# Will forceload the chunk if needed
# Arguments:
# 1: Server
# 2: X position
# 3: Y position
# 4: Z position
# 5: Block (optional, defaults to "minecraft:dirt")
# 6: Mode destroy/keep/replace (optional, defaults to "replace")
function minecraft_set_block() {
	local pos_x=$2
	local pos_y=$3
	local pos_z=$4
	local block=${5:-"minecraft:dirt"}
	local mode=${6:-"replace"}
	local result
	local need_retry=true
	
	while [[ "$need_retry" == true ]]; do
		need_retry=false
		
		result=$(send_server_command_await_output $1 "minecraft:setblock $pos_x $pos_y $pos_z $block $mode")
		
		# If the result is "That position is not loaded" we load the position and try again
		if [[ "$result" = "That position is not loaded" ]]; then
			minecraft_forceload $1 "add" $pos_x $pos_z
			need_retry=true
		#elif [[ "$result" = "Could not set the block" ]]; then
			# 99% of the time this means that the block is the same as the one already there
		fi
	done
}

# Send "fill" command to a server
# Arguments:
# 1: Server
# 2: From X position
# 3: From Y position
# 4: From Z position
# 5: To X position
# 6: To Y position
# 7: To Z position
# 8: Block
# 9: Mode destroy/hollow/keep/outline/replace (optional, defaults to "replace")
# 10: Filter (when using mode "replace")
function minecraft_fill() {
	local from_pos_x=$2
	local from_pos_y=$3
	local from_pos_z=$4
	local to_pos_x=$5
	local to_pos_y=$6
	local to_pos_z=$7
	local block=$8
	local mode=${9:-"replace"}
	local filter_block=${10:-""}
	local result
	local need_retry=true
	
	while [[ "$need_retry" == true ]]; do
		need_retry=false
		
		result=$(send_server_command_await_output $1 "minecraft:fill $from_pos_x $from_pos_y $from_pos_z $to_pos_x $to_pos_y $to_pos_z $block $mode $filter_block" '' '(Successfully filled \d+ block(s)|No blocks were filled)' '')
		
		# If the result is "That position is not loaded" we load the position and try again
		if [[ "$result" = "That position is not loaded" ]]; then
			minecraft_forceload $1 "add" $from_pos_x $from_pos_z $to_pos_x $to_pos_z
			need_retry=true
		fi
	done
}

# Send a "kick" command to a server
# Arguments:
# 1: Server
# 2: Target selector
# 3: Reason (optional)
function minecraft_kick() {
	local target=$2
	local reason=${3:-""}
	send_server_command $1 "minecraft:kick $target $reason"
}

# Send a "teleport" command to a server
# Arguments:
# 1: Server
# 2: Target selector
# 3: X position
# 4: Y position
# 5: Z position
# 6: Yaw (optional)
# 7: Pitch (optional)
function minecraft_teleport() {
	local target=$2
	local pos_x=${3:-"~"}
	local pos_y=${4:-"~"}
	local pos_z=${5:-"~"}
	local facing=${@:6}
	send_server_command $1 "minecraft:teleport $target $pos_x $pos_y $pos_z $facing"
}

# Send a "bossbar" command to a server
# Locally stores the bossbar ID in an associative array
# Arguments:
# 1: Server
# 2: State add/remove/set/get
# 3: ID
# 4: Name
# 5: Max Value
# 6: Target selector
# 7: Value
# 8: Visible (optional, defaults to true)
function minecraft_bossbar() {
	local state=$2
	local id=$3
	local name=$4
	local max_value=$5
	local target=$6
	local value=$7
	local visible=$8
	local result=$(send_server_command $1 "minecraft:bossbar $state $id \"$name\" $max_value $target $value $visible")
	
	# Add to the bossbar list
	if [[ "$state" == "add" ]]; then
		server_bossbars[$1]+="$id "
	fi
	
	# Remove from the bossbar list
	if [[ "$state" == "remove" ]]; then
		server_bossbars[$1]=$(echo "${server_bossbars[$1]}" | sed "s/$id //")
	fi
}

# Returns the cached bossbars for a server
function minecraft_bossbar_list() {
	# Get from associative array
	echo "${server_bossbars[$1]}"
}

# Send a "bossbar remove" command to a server
# Optionally removes all bossbars
# Arguments:
# 1: Server
# 2: ID (optional, defaults to all)
function minecraft_bossbar_remove() {
	local id=$2
	# Do we have an ID?
	if [[ -n "$id" ]]; then
		send_server_command $1 "minecraft:bossbar remove $id"
	else
		# Remove all bossbars
		local bossbars=($(minecraft_bossbar_list $1))
		for bossbar in "${bossbars[@]}"; do
			send_server_command $1 "minecraft:bossbar remove $bossbar"
		done
	fi
}

# Send a "weather" command to a server
# Arguments:
# 1: Server
# 2: State clear/rain/thunder
# 3: Duration #(default: ticks)/#d(in-game days)/#s(real-time seconds) (optional)
function minecraft_weather() {
	local state=$2
	local duration=$3
	send_server_command $1 "minecraft:weather $state $duration"
}