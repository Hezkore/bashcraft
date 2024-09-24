#!/bin/bash
# This example demonstrates how to use the raw bashcraft.sh functions
# It's recommended to use the wrapper functions instead of these

# This example is expected to be ran from the examples directory
source ./../bashcraft.sh

# Are the screens running with sudo?
# Not recommended, but available if needed
use_screen_sudo true

# Fetch all running servers
# This checks for any SCREEN processes running java with papermc.jar
fetch_screen_servers

# Did we find any servers?
if [[ $(get_server_count) -eq 0 ]]; then
	echo "No Minecraft Paper servers found"
	echo "Make sure you have a Paper server running in a screen session"
	exit 1
fi

# Get the server names
# This returns an array, so remember to call it () encapsulated!
# echo "Minecraft Paper servers running: $(get_server_screen_names)"
servers=($(get_server_names))
for server in "${servers[@]}"; do
	echo "Minecraft Paper server found: $server"
done

# Get the working directory for each server
for server in "${servers[@]}"; do
	echo "Working directory for $server: $(get_server_working_dir $server)"
done

# Get the latest log file for each server
for server in "${servers[@]}"; do
	echo "Latest log file for $server: $(get_server_latest_log_file $server)"
done

# Send a command to each server, expect no response
echo "Sending Hello, world! to each server"
for server in "${servers[@]}"; do
	send_server_command $server "say Hello, world!"
done

# Send a command to each server and wait for any response
echo "Sending Hello, world! to each server and wait for response"
for server in "${servers[@]}"; do
	echo "Response from $server: $(send_server_command_await_output $server "say Hello, world!")"
done

# Send a command to each server and wait for a specific response
for server in "${servers[@]}"; do
	echo "Response from $server: $(send_server_command_await_output $server "minecraft:playsound minecraft:entity.player.levelup master @a ~ ~ ~ 1 1 1" "(Played sound .*|No player was found)")"
done

# Send a command to each server and get a multi-line response
# Retry if we get "Checking version, please wait..."
echo "Sending multi-lined \"paper version\" command to each server, wait for response and retry if we get a specific response"
for server in "${servers[@]}"; do
	response=$(send_server_command_await_output "$server" "paper version" "" "" "Checking version, please wait..." )
	IFS=$'\n' read -r -d '' -a lines <<< "$response"
	for line in "${lines[@]}"; do
		echo "Response from $server: $line"
	done
done

# Send a command to a server that does not exist
server="non-existent-server"
if server_name_exists "$server"; then
    echo "Server \"$server\" exists!"
else
    echo "Server \"$server\" does not exist"
fi
echo "Response from non-existent server: $(send_server_command_await_output "$server" "say Hello, world!")"

# Done
exit 0