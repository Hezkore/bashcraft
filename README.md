# Bashcraft

Talk to your Minecraft Paper server via screen and logs.

## What, Why, How?

Bashcraft is a lightweight bash library that allows you to interact with your Minecraft Paper server via screen sessions and log outputs.

Not everything needs to be a complex Java plugin with numerous dependencies. Sometimes, you just need a simple way to get the player count or send a message to everyone on the server using crontab. Bashcraft provides a simple and straightforward solution for these tasks without requiring any installation or non-standard Unix dependencies.

Just source Bashcraft in your bash script and send any Minecraft commands to your Minecraft Paper screen.\
Bashcraft will automatically read the log output and process it for you.

## Features
* **Send Commands**: Easily send commands to your Minecraft Paper server running in a screen session.
* **Read Output**: Automatically read and process the log output from the server.
* **Wrapped Functions**: Get going quickly with wrapped functions for common commands.

## Usage
1. Clone the repository `git clone https://github.com/hezkore/bashcraft.git`
2. Source the script in your bash script `source bashcraft.sh`

Done!

Check out the `examples` directory to see how to use Bashcraft.