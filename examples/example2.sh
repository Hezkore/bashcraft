#!/bin/bash
# This example demonstrates how to use some of the wrapper functions
# Every vanilla Minecraft function is prefixed with "minecraft_"

# This example is expected to be ran from the examples directory
source ./../bashcraft.sh

# Are the screens running with sudo?
# Not recommended, but available if needed
use_screen_sudo true

# Fetch all running servers
# This checks for any SCREEN processes running java with papermc.jar
fetch_screen_servers

# Did we find any servers?
server_count=$(get_server_count)
if [[ $server_count -eq 0 ]]; then
	echo "No Minecraft Paper servers found"
	echo "Make sure you have a Paper server running in a screen session"
	exit 1
else
	echo "Found $server_count Minecraft Paper servers"
fi

# Get the server names
servers=($(get_server_names))

# Get the last server
server=${servers[-1]}

# Set an alias for the server
set_server_alias $server "My Test Server"

echo "Using \"$(get_server_alias $server)\" ($server) as test server"

# Send a "say" command to the server
echo "Sending a 'say' command to the server"
minecraft_say $server "Hello! The current date is $(date '+%Y-%m-%d %H:%M:%S')"

# Send a notice to the server
echo "Sending a notice to the server"
minecraft_notice $server "I'm using Bashcraft v$BASHCRAFT_VERSION" "green"

# Save the server world and wait for completion
echo "Saving the server world"
minecraft_save_all $server
echo "Save complete"

# Get online players
echo "Players online:"
players=("$(minecraft_list "$server")")
for player in "${players[@]}"; do
	echo " - $player"
done

# Play a sound to all players
# By default, the sound is played centered to all players at max volume on the master channel
echo "Playing a sound to all players"
minecraft_playsound $server "minecraft:entity.experience_orb.pickup"

# Play a directional sound to all players close to the center of the world
# Full volume, pitch twice as high, minimum volume at 0
# Increase volume to make the sound audible from further away
# Increase minimum volume to force the sound to be heard from any distance
minecraft_playsound $server "minecraft:entity.player.levelup" "master" "@a" "0" "80" "0" 1 2 0

# Create a poof cloud
echo "Spawning particle effects"
minecraft_particle $server "minecraft:poof" "0" "82" "0"

# Summon a zombie in the poof cloud
echo "Summoning a zombie"
zombie_uuid=$(minecraft_summon $server "minecraft:zombie" "0" "80" "0" "{CustomName:'\"My Zombie\"'}")
echo "UUID of the zombie: $zombie_uuid"

# Get the health of the zombie
zombie_health=$(minecraft_data_get_entity $server "@n[nbt={UUID:[I;$zombie_uuid]}]" "Health")
echo "Health of the zombie: $zombie_health"

# Create a bossbar for the zombie
echo "Creating a bossbar for the zombie"
bossbar=$(minecraft_bossbar_add $server "my_zombie_health" "My Zombie Health")

# Show the bossbar to everyone
echo "Configuring the bossbar"
minecraft_bossbar_set $server $bossbar "max" $(int_of $zombie_health)
minecraft_bossbar_set $server $bossbar "value" $(int_of $zombie_health)
minecraft_bossbar_set $server $bossbar "players" "@a"
sleep 2

# Make the zombie invisible forever with an amplifier of 0, effect is hidden, based on UUID
echo "Making the zombie invisible"
minecraft_effect $server "give" "@n[nbt={UUID:[I;$zombie_uuid]}]" "minecraft:invisibility" "infinite" 0 true

# Kill the zombie based on UUID
echo "Killing the zombie"
minecraft_kill $server "@e[nbt={UUID:[I;$zombie_uuid]}]"

# Remove the bossbar
echo "Removing the bossbar"
minecraft_bossbar_remove $server $bossbar

# Done
exit 0