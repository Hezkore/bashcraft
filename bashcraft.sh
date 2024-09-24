#!/bin/bash
# A collection of functions to interact with Minecraft servers running in screen

BASHCRAFT_VERSION="0.1"
READ_SLEEP_TIME=0.0001
LOG_FILE_PATH="/logs/latest.log"

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
		add_screen_server "$screen"
	done
}

# Manually add a server screen
function add_screen_server() {
	local screen=$1

	# Check if a screen name is provided
	if [[ -z "$screen" ]]; then
		# If not, print an error message and return 1 (Error)
		echo "No screen name specified"
		return 1
	fi
	
	# Store the screen name in the server_names array
	server_names[$screen]="$screen"
	
	# Cache the working directory for this screen
	_cache_server_working_dir "$screen"
	
	# Cache the latest log file for this screen
	_cache_server_latest_log_file "$screen"
}

# Internal function to cache the working directory for a server screen
function _cache_server_working_dir() {
	# Look for the screen name in the associative array
	if [[ -z "${server_working_dir[$1]}" ]]; then
		local pid=$(${_USE_SUDO} screen -ls | grep "${1}" | awk '{print $1}' | cut -d. -f1)
		if [ -n "$pid" ]; then
			server_pid[$1]=$pid
			server_working_dir[$1]=$(${_USE_SUDO} pwdx "$pid" | awk '{print $2}')
		fi
	fi
}

# Internal function to cache the latest log file path for a server screen
function _cache_server_latest_log_file() {
	server_latest_log_file[$1]="${server_working_dir[$1]}${LOG_FILE_PATH}"
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
	if ${_USE_SUDO} screen -ls | grep -q "$1"; then
		return 0  # Server name exists
	else
		return 1  # Server name does not exist
	fi
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

# Trims a string by removing leading/trailing whitespace and carriage returns/newlines
function clean_trim() {
	echo "$1" | tr -d '\r' | tr '\n' ' ' | sed 's/^ *//; s/ *$//'
}

# Takes a decimal value and returns an integer value
function int_of() {
	echo "${1%%.*}"
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
		#echo ""
		return 1
	fi
	
	# Execute the command
	${_USE_SUDO} screen -S $1 -X stuff "$2^M"
	return 1
}

# Send a command to the specified server screen name and return the output
# Uses POSIX extended regular expressions (ERE) in Bash
# Arguments:
# 1: Server
# 2: Command to send
# 3: Regex for lines that must be returned; reloads file until found (optional, returns to eof by default)
# 4: Regex for lines that may only be returned (optional, returns everything by default, set to || to match 'must return' regex)
# 5: Regex for newest line retry; checks the newest line and reloads file if match (optional)
# 6: Regex for line that instantly ends the file read (optional)
# 7: Regex for lines that will be ignored (optional)
function send_server_command_await_output() {
	# Check if the server screen name exists
	if ! server_name_exists $1; then
		return 1
	fi
	
	# Which log file are we reading from?
	local log_file="${server_latest_log_file[$1]}"
	
	# Must return and retry until we match the must regex
	local must_regex=${3:-""}
	
	# Return only lines matching the regex
	local match_regex=${4:-""}
	
	# Retry reading when we match the retry regex
	local retry_regex=${5:-""}
	
	# Stop reading when we match the end regex
	local end_regex=${6:-""}
	
	# Ignore lines matching this regex
	local ignore_regex=${7:-""}
	
	# Store the length of the log file currently
	local current_line_count=$(wc -l < "$log_file")
	
	# Check if match regex is "||"
	if [[ "$match_regex" == "||" ]]; then
		match_regex=$must_regex
	fi
	
	# Execute the command
	${_USE_SUDO} screen -S $1 -X stuff "$2^M"
	
	# Wait for the log file to have MORE lines
	while [[ $(wc -l < "$log_file") -le $current_line_count ]]; do
		sleep $READ_SLEEP_TIME
	done
	
	# While we have to try, do a try
	local needs_retry=true
	local skip_next_line=false
	local found_lines=()
	local loop_count=0
	while [[ "$needs_retry" == true ]]; do
		loop_count=$((loop_count + 1))
		needs_retry=false
		found_lines=()
		
		# Get the new lines since the last check
		new_lines=$(tail -n $(( $(wc -l < "$log_file") - $current_line_count )) "$log_file")
		newest_line=$(clean_log_output "$(tail -n 1 <<< "$new_lines")")
		
		# If the loop count is higher than 100, display new lines
		if [[ $loop_count -gt 100 ]]; then
			echo "Command $2 stuck in a loop" >&2
			echo "====NEW LINES ====" >&2
			echo "$new_lines" >&2
			echo "====END NEW LINES====" >&2
		fi
		#echo "DEBUG: New lines: $new_lines" >&2
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
				
				# Check if the line matches the must regex if provided
				if [[ -n "$must_regex" ]]; then
					# If the line matches, we do not need to retry and we can stop
					if [[ "$cleaned_line" =~ $must_regex ]]; then
						needs_retry=false
						must_regex=""
					else
						needs_retry=true
					fi
				fi
				
				# Check if the line matches the ignore regex if provided
				if [[ -n "$ignore_regex" ]]; then
					if [[ "$cleaned_line" =~ $ignore_regex ]]; then
						continue
					fi
				fi
				
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
	local result=$(send_server_command_await_output $1 "minecraft:save-all" "Saved the game")
}

# Send a "list" command to a server
# Returns an array of players online
# Arguments:
# 1: Server
function minecraft_list() {
	local result=$(send_server_command_await_output $1 "minecraft:list" "There are [0-9]+ of a max of [0-9]+ players online: " "||")
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

# Send a "data get entity" command to a server
# Arguments:
# 1: Server
# 2: Target selector (optional, defaults to "@n")
# 3: Entity data path
function minecraft_data_get_entity() {
	local target=${2:-"@n"}
	local path=$3
	local result=$(send_server_command_await_output $1 "minecraft:data get entity $target $path" ".* has the following entity data: " "||")
	local processed_result=$(echo "$result" | sed 's/.*entity data: //')
	local cleaned_result=$(clean_minecraft_data_type "$processed_result")
	echo "$cleaned_result"
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
	local result=$(send_server_command_await_output $1 "minecraft:summon $entity $pos_x $pos_y $pos_z $nbts" "(^Summoned new .*|^Can't find element '$entity' of type '.*)" "||")
	
	# Did we successfully summon an entity?
	if [[ "$result" = "Summoned new "* ]]; then
		# Get the UUID of the entity
		local entity_uuid=($(minecraft_data_get_entity $1 "@e[type=$entity,x=$pos_x,y=$pos_y,z=$pos_z,limit=1,sort=nearest]" "UUID"))
		entity_uuid="$(array_to_string "${entity_uuid[@]}" ",")"
		echo "$entity_uuid"
		return
	else
		echo "ERROR: Failed to summon entity $entity" >&2
		echo ""
		return
	fi
}

# Send a "kill" command to a server
# Arguments:
# 1: Server
# 2: Target selector (optional, defaults to "@e")
function minecraft_kill() {
	local target=${2:-"@e"}
	send_server_command $1 "minecraft:kill $target"
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
		
		# TODO: regex for must return
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
		
		result=$(send_server_command_await_output $1 "minecraft:fill $from_pos_x $from_pos_y $from_pos_z $to_pos_x $to_pos_y $to_pos_z $block $mode $filter_block" "(Successfully filled [0-9]+ block\(s\)|No blocks were filled|Unknown block type '$block'|That position is not loaded)" "||")
		
		# If the result is "That position is not loaded" we load the position and try again
		if [[ "$result" = "That position is not loaded" ]]; then
			minecraft_forceload $1 "add" $from_pos_x $from_pos_z $to_pos_x $to_pos_z
			need_retry=true
			continue
		fi
		
		# If it was "Unknown block type ..." we return an error
		if [[ "$result" = "Unknown block type '$block'" ]]; then
			return 1
		fi
	done
	
	return 0
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

# Send a "bossbar add" command to a server
# Arguments:
# 1: Server
# 2: ID
# 3: Name
function minecraft_bossbar_add() {
	local id=$2
	local name=$3
	local result=$(send_server_command_await_output $1 "minecraft:bossbar add $id \"$name\"" "(A bossbar already exists with the ID 'minecraft:$id'|Created custom bossbar \[$name\])")
	
	server_bossbars[$1]+="$id "
	echo "$id"
}

# Send a "bossbar get " command to a server
# Arguments:
# 1: Server
# 2: ID
# 3: (max|players|value|visible)
function minecraft_bossbar_get() {
	local id=$2
	local property=$3
	# TODO: regex for must return
	local result=$(send_server_command_await_output $1 "minecraft:bossbar get $id $property")
	
	echo "$result"
	return
}

# Send a "bossbar set" command to a server
# Arguments:
# 1: Server
# 2: ID
# 3: Property
# 4..: Data
function minecraft_bossbar_set() {
	local id=$2
	local property=$3
	local data=${@:4}
	local result=$(send_server_command_await_output $1 "minecraft:bossbar set $id $property $data")
}

# Send a "bossbar remove" command to a server
# Arguments:
# 1: Server
# 2: ID
function minecraft_bossbar_remove() {
	local id=$2
	# TODO: update regex must to match fail
	local result=$(send_server_command_await_output $1 "minecraft:bossbar remove $id" "Removed custom bossbar .*" "||")
	
	if [[ "$result" = "Removed custom bossbar $id" ]]; then
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
		local bossbars=("$(minecraft_bossbar_list $1)")
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

# Send a "spreadplayers" command to a server
# Arguments:
# 1: Server
# 2: X position
# 3: Z position
# 4: Spread distance
# 5: Max range
# 6: Respect teams (optional, defaults to false)
# 7: Target selector (optional, defaults to "@a")
function minecraft_spreadplayers() {
	local pos_x=$2
	local pos_z=$3
	local spread_distance=$4
	local max_range=$5
	local respect_teams=$6
	local target=$7
	send_server_command $1 "minecraft:spreadplayers $pos_x $pos_z $spread_distance $max_range $respect_teams $target"
}

# Send a "spreadplayers under" command to a server
# Arguments:
# 1: Server
# 2: X position
# 3: Z position
# 4: Spread distance
# 5: Max range
# 6: maxHeight
# 7: Respect teams (optional, defaults to false)
# 8: Target selector (optional, defaults to "@a")
function minecraft_spreadplayers_under() {
	local pos_x=$2
	local pos_z=$3
	local spread_distance=$4
	local max_range=$5
	local respect_teams=$6
	local target=$7
	send_server_command $1 "minecraft:spreadplayers $pos_x $pos_z $spread_distance $max_range under $respect_teams $target"
}

# = Bukkit wrapper functions ===================================================

# Send a "bukkit:plugins" command to a server
function bukkit_plugins() {
	# Get the result from the server command
	local result=$(send_server_command_await_output "$1" "bukkit:plugins" "Server Plugins \([0-9]+\):" "" "" "" "(Server Plugins \([0-9]+\):|.* Plugins:)")
	result=$(clean_trim "$result")
	result=$(tr -d ',' <<< "$result")
	local plugins=${result#*- }
	echo "${plugins[@]}"
}