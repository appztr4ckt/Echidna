# Echidna

This server requires a Perl distribution (ActivePerl or Strawberry Perl will both work fine for Windows) to run. The command is: perl core.pl
The console is non-interactive (sorry) but you can use the /hide command in-game to accurately pretend you're not connected anyway if you like.
Check config.txt to configure the server, command.pl to change the admin levels required to use certain commands.
Level 200 admins have access to everything by defualt, including the /admin <person> <level> command which can be used to set others to any specific level. /op and /deop are considered level 100.
Some commands allow different things to different admin levels, most notably the /build command allows different things to be built. (Only level 200 admins can build active water and lava by default, though watervator is available to all.)

To port a server_level.dat for use with this server, run mapconv.jar by double-clicking it with a server_level.dat in the same folder. It should dump the necessary .gz file for you to put into the maps folder and exit, you will have to make a folder in the maps/backup folder by the same name for automatic backups to work.
