#!/usr/bin/perl
use warnings;
use strict;
use POSIX;

# This is the special part:
# This file is all of the hooks that get called from the raw events,
# all of the unique commands and action responses, the stuff that
# makes a server running this proxy connection SPECIAL.
our (%game,%map,@clients);

$game{'modes'} = {
	resources => 0,
	archaeology => 1
};

# Add the game hooks
$game{'hooks'} = {
	map_filter => \&map_filter,
	on_say => \&on_say,
	#on_server_text => \&on_server_text, # Yellow server message recieved, $sock, $message
	on_player_text => \&on_player_text, # White player message recieved, $sock, $sender_nick, $message, $sender_id
	on_break => \&on_break, # When breaking a block: $sock, $type, $pos_x, $pos_y, $pos_z
	on_build => \&on_build, # When building a block: $sock, $type, $pos_x, $pos_y, $pos_z
	on_spawn => \&on_spawn, # When a player first spawns: $sock, $pos_x, $pos_y, $pos_z, $rotx, $roty
	on_block_type => \&on_block_type # When the server changes a block: $sock, $type, $pos_x, $pos_y, $pos_z
};

# Official command tracking
&add_command('solid',\&cmd_solid,100);
&add_command('op',\&cmd_op,100);
&add_command('deop',\&cmd_deop,100);

# Essentials
&add_command('me',\&cmd_me,0,'Roleplaying actions.');
&add_command('fetch',\&cmd_fetch,100,'Teleport another player to you.');
&add_command('recall',\&cmd_fetch,100,'Teleport another player to you.');

# Silly stuff
&add_command('nick',\&cmd_nick,100,'Disguise yourself with a name (and skin) of your choosing.');
&add_command('spawn',\&cmd_spawn,100,'Spawn a ghost of yourself or someone else.');

# Building stuff
&add_command('build',\&cmd_build,100,'Build using the un-buildable block types.');
&add_command('record',\&cmd_record,0,'WIP');

# The values and types of various resources.
# Uncomment this to turn it on, for each type of block individually if you prefer.
# It's a work in progress. :]
$game{'resources'} = {
	14 => { break => {'Gold',10} },
	15 => { break => {'Iron',10} },
	16 => { break => {'Coal',10} },
	41 => { build => {'Gold',100} }
};

sub set_fake() {
	my ($x,$y,$z,$type) = @_;
	$game{'fake_blocks'}{($z * $map{'size'}{'y'} + $y) * $map{'size'}{'x'} + $x} = $type;
}

sub remove_fake() {
	my ($x,$y,$z) = @_;
	undef $game{'fake_blocks'}{($z * $map{'size'}{'y'} + $y) * $map{'size'}{'x'} + $x};
}

sub get_fake() {
	my ($x,$y,$z) = @_;
	return $game{'fake_blocks'}{($z * $map{'size'}{'y'} + $y) * $map{'size'}{'x'} + $x};
}

# /help: Commands list.
sub cmd_help() {
	my $sock = shift;
	&send_msg($sock,"This server supports an extended set of commands.");
	&send_msg($sock,"These are the commands you can use:");
	my $level = &get_adminlevel($sock);
	foreach (@commands) {
		&send_msg($sock,'/'.$_->[0].' - '.$_->[3]) if ($_->[3] && $level >= $_->[2]);
	}
	return 1;
}

# /me: Roleplaying actions ala IRC.
sub cmd_me() {
	my $sock = shift;
	my $pair = &get_pair($sock);
	if (defined($_[0])) { &send_msg($pair,"|ACTION @_|"); }
	else { &send_msg($sock,"No text to send."); }
	return 1;
}

# /nick: Change your chat name!
sub cmd_nick() {
	my $sock = shift;
	my $id = &get_id($sock);
	unless (defined($id)) {
		&send_msg($sock,"Your id has not been gathered yet, please wait.");
		return 1;
	}
	if (defined($_[0])) {
		my $old_name = &get_nick($sock);
		my $name = join(' ',@_);
		$name =~ s/%c(.)/&$1/g; # Colors in names!!
		$name =~ s/&.$//g; # No colors at the end of the name kthx. (Horrible crash avoiding.)
		&set_nick($sock,$name);
		&global_msg("* $old_name&e is now $safe_name&e.");
		my $msg = pack("c2",12,$id).pack("c2A64S>3c2",7,$id,$name,@{&get_pos($sock)},@{&get_rot($sock)});
		foreach (@clients) {
			if ($_ != $sock) { &send_raw($_,$msg); } # Tell everyone but me that I die and respawn as a new person.
		}
	}
	else {
		my $name = &get_nick($sock);
		&send_msg($sock,"Your nick is $name&e.");
	}
	return 1;
}

# /fetch: Teleport someone to you.
sub cmd_fetch() {
	my $sock = shift;
	my @matches;
	foreach (@clients) {
		if (lc(&get_account($_)) eq lc("@_")) {
			my $nick = &get_account($_);
			&send_msg($sock,"Found $nick for you.");
			&send_msg($_,"You were fetched by ".&get_nick($sock)."&e.");
			&send_raw($_,pack("c2S>3c2",8,-1,@{&get_pos($sock)},@{&get_rot($sock)}));
			return 1;
		}
		elsif (lc(&get_nick($_)) eq lc("@_")) {
			push(@matches,&get_account($_));
		}
	}
	&send_msg($sock,"@_ not found.");
	&send_msg($sock,"@matches are using this identity, however.") if (@matches);
	return 1;
}

# /spawn: Spawn a dummy.
sub cmd_spawn() {
	my $sock = shift;
	my $name = "@_" || &get_nick($sock);
	$name =~ s/&.$//g;
	my $pos = &get_pos($sock);
	&send_msg($sock,"Spawning a dummy at @{$pos}");
	foreach (@clients) {
		&send_raw($_,pack("c2A64S>3c2",7,127,$name,@{$pos},@{&get_rot($sock)}));
	}
	return 1;
}

# /solid; Reset building material for server command.
sub cmd_solid() {
	my $sock = shift;
	undef $game{'fake_build'}{&get_account($sock)};
	return 0;
}

# /op and /deop: Keep track of user levels in realtime.
sub cmd_op() {
	my $sock = shift;
	&set_adminlevel(&find_account("@_"),100);
	return 0;
}
sub cmd_deop() {
	my $sock = shift;
	&set_adminlevel(&find_account("@_"),0);
	return 0;
}

# /build: Build things you normally can't.
sub cmd_build() {
	my $sock = shift;
	if (defined($_[0])) {
		my $type = lc($_[0]);
		if ($type eq 'water') { $game{'fake_build'}{&get_account($sock)} = 9; }
		elsif ($type eq 'lava') { $game{'fake_build'}{&get_account($sock)} = 11; }
		elsif ($type eq 'gold') { $game{'fake_build'}{&get_account($sock)} = 14; }
		elsif ($type eq 'iron') { $game{'fake_build'}{&get_account($sock)} = 15; }
		elsif ($type eq 'coal') { $game{'fake_build'}{&get_account($sock)} = 16; }
		else {
			&send_msg($sock,"Unknown mineral type.");
			return 1;
		}
		&send_msg($sock,"Now building $type blocks.");
	}
	else {
		if ($game{'fake_build'}{&get_account($sock)}) {
			undef $game{'fake_build'}{&get_account($sock)};
			&send_msg($sock,"Now building normally.");
		}
		else { &send_msg($sock,"Use &f/build &cwater&e, &f/build &clava&e, &f/build &cgold&e, &f/build &ciron&e, or &f/build &ccoal&e."); }
	}
	return 1;
}

# /record: Keep track of every block broken, and save it for building later.
sub cmd_record() {
	my $sock = shift;
	my $account = &get_account($sock);
	$game{'recording'}{$account} = !$game{'recording'}{$account};
	if ($game{'recording'}{$account}) {
		&send_msg($sock,"Now recording. Break blocks to save them, then use &f/record&e again.");
	}
	elsif (lc($_[0]) eq 'cancel') {
		&send_msg($sock,"Cancelled.");
	}
	elsif (defined($_[0])) {
		&send_msg($sock,"Finished saving '@_'.");
	}
	else {
		$game{'recording'}{$account} = 1;
		&send_msg($sock,"Use '&f/record &aname&e' to save a prefab, or '&f/record cancel&e' to stop without saving.");
	}
	return 1;
}

sub map_filter() {
	my ($blocks) = @_;
	foreach (keys %{$game{'fake_blocks'}}) {
		$blocks->[$_] = $game{'fake_blocks'}{$_};
	}
}

# When a message is being sent from a player (i.e. "hello")
sub on_say() {
	my ($sock,$message) = @_;
	if ($message =~ /^xyzzy/) {
		&send_msg($sock,"Nothing happens.");
		return 1;
	}
	else { # Replace color codes
		$message =~ s/%c(.)/&$1/g;
		$message =~ s/&.$//g;
		if (!length($message)) { return 1; }
		&send_msg(&get_pair($sock),$message);
		return 1;
	}
	return 0;
}

# When another player says something and I'm recieving it (i.e. "JTE: hello")
sub on_player_text() {
	my ($sock,$nick,$msg,$id) = @_;
	if ($msg =~ /^\|ACTION (.+)\|$/) {
		$msg = $1;
		&send_msg($sock,"* $nick&f $msg",$id);
	}
	else { &send_msg($sock,"$nick&f: $msg",$id); }
	return 1;
}

# When a player spawns
sub on_spawn() {
	my ($sock,$pos_x,$pos_y,$pos_z,$rotx,$roty) = @_;
	&send_msg($sock, "This server is running JTE's services. Type &f/help&e for info.");
	return 0;
}

# When a player wants to build a block
sub on_build() {
	my ($sock,$type,$pos_x,$pos_y,$pos_z) = @_;
	my $resource = $game{'resources'}{$type};
	if (defined($game{'fake_build'}{&get_account($sock)}) && $type == 1) {
		&set_fake($pos_x,$pos_y,$pos_z,$game{'fake_build'}{&get_account($sock)});
		return 0;
	}
	if (defined($resource) && &get_adminlevel($sock) < 100) {
		my $account = &get_account($sock);
		if (($game{'inventory'}{$account}{lc($resource->[1])} || 0) >= $resource->[0]) {
			$game{'inventory'}{$account}{lc($resource->[1])} -= $resource->[0];
			&send_msg($sock,$game{'inventory'}{$account}{lc($resource->[1])}.' '.$resource->[1].' remaining.');
		}
		else {
			&send_msg($sock,'Need '.$resource->[0].' '.$resource->[1].' to build that.');
			&send_block($sock,$pos_x,$pos_y,$pos_z,&get_block($pos_x,$pos_y,$pos_z)); # Revert the build
			return 1;
		}
	}
	&remove_fake($pos_x,$pos_y,$pos_z);
	return 0;
}

# When a player wants to break a block
sub on_break() {
	my ($sock,$type,$pos_x,$pos_y,$pos_z) = @_;
	#&send_block($sock,$pos_x,$pos_y,$pos_z,$type); # Revert the break
	#return 1;
	&remove_fake($pos_x,$pos_y,$pos_z);
	my $resource = $game{'resources'}{$type};
	if (defined($resource)) {
		my $account = &get_account($sock);
		$game{'inventory'}{$account}{lc($resource->[1])} += $resource->[0];
		&send_msg($sock,'Gained &f'.$resource->[0].'&e '.$resource->[1].' (You have &c'.$game{'inventory'}{$account}{lc($resource->[1])}.'&e '.$resource->[1].')');
	}
	return 0;
}

# When the server changes a block
sub on_block_type() {
	my ($sock,$type,$pos_x,$pos_y,$pos_z) = @_;
	my $mineral = &get_fake($pos_x,$pos_y,$pos_z);
	if (defined($mineral)) {
		my $pair = &get_pair($sock);
		&set_block($pos_x,$pos_y,$pos_z,$mineral);
		&send_block($pair,$pos_x,$pos_y,$pos_z,$mineral);
		return 1;
	}
	return 0;
}

1;
