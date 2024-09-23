#!/usr/bin/perl
use warnings;
use strict;
use Digest::MD5 qw(md5_hex);
use IO::Compress::Gzip qw(gzip $GzipError);
use POSIX;

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

# Packet formats
my @packets = (
	['cA64A64c',\&handle_login], #0
	[''], #1
	[''], #2
	['na1024c'], #3
	['n3'], #4
	['n3c2',\&handle_blockchange], #5
	['n3c'], #6
	['cA64n3c2'], #7
	['cn3c2',\&handle_input], #8
	['c6'], #9
	['c4'], #10
	['c3'], #11
	['c'], #12
	['cA64',\&handle_chat], #13
	['A64'] #14
);

# Gets the length of a given packet type
sub get_packet_len() {
	# Yes, this DOES actually turn the packet format
	# string into the length of the message itself...!
	my $format = $packets[shift][0];

	$format =~ s/(\D)(\D)/$1.'1'.$2/ge; # No number? Presume 1.
	$format =~ s/(\D)$/$1.'1'/ge;

	$format =~ s/[Aac](\d+)/+$1/g; # 1 byte
	$format =~ s/n(\d+)/+($1*2)/g; # 2 byte
	$format =~ s/N(\d+)/+($1*4)/g; # 4 byte

	# Cut the leading +
	$format =~ s/^\+//g;

	return eval $format || 0; # And finally calculate it.
}

# Takes decoded packet and logs it.
sub raw_log() {
	return unless ($server{'info'}{'rawlog'});
	my ($dst,$type,@args) = @_;
	my $format = $packets[$type][0];
	open RAW,'>>raw.log';
	if ($dst > 0) { print RAW "Recieved $type from ".(abs($dst)-1).":\n"; }
	else { print RAW "Sent $type to ".(abs($dst)-1).":\n"; }
	while ($format =~ /(\D)([<>]?)(\d*)/g) {
		my ($type,$endian,$num) = ($1,$2,$3);
		$num = 1 unless $num ne '';
		if ($type eq 'A') { # Strings
			my $mask = $type.$endian.$num;
			if ($mask eq 'A64') { $mask = 'String'; }
			else { $mask = 'Err'.$mask; }
			print RAW "$mask: ".shift(@args)."\n";
		}
		elsif ($type eq 'a') { # Don't bother to log raw data
			print RAW "raw$num\n";
			shift @args;
		}
		else { # Numbers of numbers
			my $mask = $type.$endian;
			if ($mask eq 'c') { $mask = 'Byte'; }
			elsif ($mask eq 'n') { $mask = 'Short'; }
			elsif ($mask eq 'L>') { $mask = 'Long'; }
			else { $mask = 'Err'.$mask; }
			for (my $i = 0; $i < $num; $i++) {
				print RAW "$mask: ".shift(@args)."\n";
			}
		}
	}
	print RAW "\n";
	close RAW;
}

sub disconnect_sock() {
	my $sock = shift;
	my $found = 0;
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && defined($_->{'sock'}) && $_->{'sock'} == $sock && defined($_->{'id'}));
		die unless defined($_->{'id'});
		&handle_disconnect($_->{'id'});
		$found = 1;
	}
	if (!$found) {
		$server{'socketset'}->remove($sock);
		$sock->close();
	}
}

# Sends a packet to a game client by socket.
sub send_raw() {
	my $sock = shift;
	return unless($sock && $sock->connected);
	#my $id = $server{'id'}{$sock};
	#$id = $server{'config'}{'max_players'} unless (defined($id));
	#&raw_log(-($id+1),@_) if ($_[0] != 1);
	$sock->send(pack('c'.$packets[$_[0]][0],@_)) or &disconnect_sock($sock);
}

sub global_raw() {
	$server{'globalbuffer'} .= pack('c'.$packets[$_[0]][0],@_);
}

# Sends a login packet (Server name/motd)
sub send_login() {
	my ($id) = @_;
	my $adminbreak = ($server{'users'}[$id]{'adminbreak'}||0);
	$adminbreak = 100 if ($adminbreak);
	&send_raw($server{'users'}[$id]{'sock'},0,$server{'info'}{'version'},$server{'config'}{'name'},$server{'config'}{'motd'},$adminbreak);
}

# Sends a packet 1 to everyone on the server to let them know they're still connected.
sub send_ping() {
	foreach (@{$server{'users'}}) {
		next unless defined($_);
		&send_raw($_->{'sock'},1) if ($_->{'active'});
	}
}

# Sends a map change
# TODO: Do this in a seperate thread or take a break after every packet to poll somehow.
sub send_map() {
	my ($id) = @_;
	$server{'users'}[$id]{'active'} = 0;
	my ($sock) = $server{'users'}[$id]{'sock'};
	&send_raw($sock,2);
	my $level = pack('L>c*',$server{'map'}{'size'}[0]*$server{'map'}{'size'}[1]*$server{'map'}{'size'}[2],@{$server{'map'}{'blocks'}});
	my $buffer;
	gzip \$level => \$buffer;
	undef $level;
	my $count = 1;
	my $num_packets = ceil(length($buffer)/1024);
	while ($buffer) {
		my $len = length($buffer);
		$len = 1024 if ($len > 1024);
		my $send;
		($send,$buffer) = unpack("a1024a*",$buffer);
		&send_raw($sock,3,$len,$send,floor($count*100/$num_packets));
		$count++;
	}
	&send_raw($sock,4,@{$server{'map'}{'size'}});
	$server{'users'}[$id]{'pos'} = [
		$server{'map'}{'spawn'}[0]*32+16,
		$server{'map'}{'spawn'}[1]*32+16,
		$server{'map'}{'spawn'}[2]*32+16
	];
	$server{'users'}[$id]{'rot'} = [ $server{'map'}{'spawn'}[3],$server{'map'}{'spawn'}[4] ];
	&send_spawn($id);
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && defined($_->{'sock'}) && $_->{'id'} != $id);
		&send_raw($sock,7,$_->{'id'},$_->{'nick'},@{$_->{'pos'}},@{$_->{'rot'}});
	}
}

sub global_mapchange() {
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		&global_die($_->{'id'});
	}
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		undef $_->{'old_pos'};
		undef $_->{'old_rot'};
		undef $_->{'base_pos'};
		my $adminbreak = ($_->{'adminbreak'}||0);
		$adminbreak = 100 if ($adminbreak);
		&send_raw($_->{'sock'},0,$server{'info'}{'version'},"&cLoading map","Please wait...",$adminbreak);
		&send_raw($_->{'sock'},2);
	}
	my $level = pack('Nc*',$server{'map'}{'size'}[0]*$server{'map'}{'size'}[1]*$server{'map'}{'size'}[2],@{$server{'map'}{'blocks'}});
	my $buffer;
	gzip \$level => \$buffer;
	undef $level;
	my $count = 1;
	my $num_packets = ceil(length($buffer)/1024);
	while ($buffer) {
		my $len = length($buffer);
		$len = 1024 if ($len > 1024);
		my $send;
		($send,$buffer) = unpack("a1024a*",$buffer);
		foreach (@{$server{'users'}}) {
			next unless defined($_) && $_->{'active'};
			&send_raw($_->{'sock'},3,$len,$send,floor($count*100/$num_packets));
		}
		$count++;
	}
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		&send_raw($_->{'sock'},4,@{$server{'map'}{'size'}});
		$_->{'pos'} = [
			$server{'map'}{'spawn'}[0]*32+16,
			$server{'map'}{'spawn'}[1]*32+16,
			$server{'map'}{'spawn'}[2]*32+16
		];
		$_->{'rot'} = [ $server{'map'}{'spawn'}[3],$server{'map'}{'spawn'}[4] ];
		&send_spawn($_->{'id'});
	}
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		&global_spawn($_->{'id'},$_->{'nick'},@{$_->{'pos'}},@{$_->{'rot'}});
	}
	$server{'clear_messages'} = time()+3;
}

# Sends a local block change to one specific id.
sub send_blockchange() {
	my ($id,$x,$y,$z,$t) = @_;
	&send_raw($server{'users'}[$id]{'sock'},6,$x,$y,$z,$t);
}

# Sends a new block type for a given position to everyone.
sub global_blockchange() {
	my ($x,$y,$z,$t) = @_;
	#print "Tile at $x $y $z changing to $t...\n";
	&global_raw(6,$x,$y,$z,$t);
}

# Sends a spawn message to a player about themselves.
sub send_spawn() {
	my ($id) = @_;
	&send_raw($server{'users'}[$id]{'sock'},7,-1,$server{'users'}[$id]{'nick'},@{$server{'users'}[$id]{'pos'}},@{$server{'users'}[$id]{'rot'}});
	$server{'users'}[$id]{'active'} = 1;
	$server{'users'}[$id]{'last_move'} = time();
	@{$server{'users'}[$id]{'old_pos'}} = @{$server{'users'}[$id]{'pos'}};
	@{$server{'users'}[$id]{'old_rot'}} = @{$server{'users'}[$id]{'rot'}};
	@{$server{'users'}[$id]{'base_pos'}} = @{$server{'users'}[$id]{'pos'}};
}

# Sends a spawn message to everyone using the given id, nick, etc.
sub global_spawn() {
	my ($id,$nick,$x,$y,$z,$rx,$ry) = @_;
	#return if ($server{'users'}[$id]{'hide'});
	foreach (@{$server{'users'}}) {
		next unless defined($_) && defined($_->{'sock'});
		my $id = $id;
		next if ($_->{'id'} == $id && !$_->{'showself'});
		&send_raw($_->{'sock'},7,$id,$nick,$x,$y,$z,$rx,$ry) if ($_->{'active'});
	}
}

# Sends a player/bot disconnect message to everyone for the given id.
# This makes the object disappear.
sub global_die() {
	my ($id) = @_;
	#return if ($server{'users'}[$id]{'hide'});
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'} && defined($_->{'sock'});
		next if ($_->{'id'} == $id && !$_->{'showself'});
		&send_raw($_->{'sock'},12,$id);
	}
}

# Relays chat messages
sub send_chat() {
	my ($id,$msg) = @_;
	print $server{'users'}[$id]{'account'}.": ".&strip($msg)."\n";
	if ($server{'users'}[$id]{'nick'} =~ /&[0-9a-f]/) { $msg = $server{'users'}[$id]{'nick'}."&f: $msg"; }
	else { $msg = $server{'users'}[$id]{'nick'}.": $msg"; }
	foreach (@{$server{'users'}}) {
		next unless defined($_);
		&send_raw($_->{'sock'},13,$id,$msg) if ($_->{'active'});
	}
}

# Sends a server message
sub send_msg() {
	my ($id,$msg) = @_;
	print 'Server->'.$server{'users'}[$id]{'account'}.': '.&strip($msg)."\n";
	&send_raw($server{'users'}[$id]{'sock'},13,-1,$msg);
}

# Sends a server message to EVERYONE
sub global_msg() {
	my ($msg) = @_;
	print &strip($msg)."\n";
	foreach (@{$server{'users'}}) {
		next unless defined($_);
		&send_raw($_->{'sock'},13,-1,$msg) if ($_->{'active'});
	}
}

# Sends a kick
sub send_kick() {
	my ($sock,$msg) = @_;
	#if ($server{'id'}{$sock}) {
	#	my $nick = $server{'users'}[$server{'id'}{$sock}]{'account'};
	#	print "Kicking $nick (".&strip($msg).")\n" if (defined($nick));
	#}
	&send_raw($sock,14,$msg);
}

# Handles incoming packets of all kinds of messages...
sub handle_packet() {
	my ($id,$buffer) = @_;
	my $sock = $server{'users'}[$id]{'sock'};
	my $type;
	while ($buffer) {
		($type,$buffer) = unpack("ca*",$buffer); # Get the message type.
		last if ($type < 0);

		# Unknown message type recieved!!
		# This happens when I've made terrible mistakes in my code,
		# a player is trying to cause some mischief with fake packets,
		# or when Notch has updated the client and I haven't caught up yet.
		unless (defined($packets[$type][1])) {
			print "Recieved unhandled packet type $type from $id\n";
			#&kick($id,'Unhandled message.');
			return '';
		}
		return $buffer if (length($buffer) < &get_packet_len($type)); # The whole message isn't there yet.

		my @args = unpack($packets[$type][0].'a*',$buffer); # Unpack the arguments...
		$buffer = pop @args;
		&raw_log($id+1,$type,@args) unless ($type == 8);
		&{$packets[$type][1]}($id,@args); # Call the handler.
		return '' unless ($sock->connected); # User disconnected or was kicked.
	}
	return '';
}

# Handles the login packet
sub handle_login() {
	my ($id,$version,$name,$verify,$type) = @_;
	undef $server{'users'}[$id]{'timeout'};
	if ($server{'bans'}{lc($name)}) {
		print "$name tried to join, but is on the ban list.\n";
		&kick($id,'You are still banned.');
		return;
	}
	if ($version != $server{'info'}{'version'}) {
		print "Unknown client version number $version recieved from $name.\n";
		#&kick($id,'Unknown client version!');
		#return;
	}
	if ($server{'config'}{'heartbeat'} && $server{'config'}{'verify'}) {
		if ($verify eq '--') {
			&kick($id,'This server is secure. The IP URL doesn\'t work.');
			return;
		}
		# Do you know how much harder this would be to do in Java?
		# How many more lines and error checking nonsense?
		$verify = substr($verify,0,32);
		my $md5 = md5_hex($server{'info'}{'salt'},$name);
		$md5 =~ s/^0//g;
		$verify =~ s/^0//g;
		if ($md5 ne $verify) {
			print "$id tried to log in as $name, but $verify didn't match $md5\n";
			my $ip = $server{'users'}[$id]{'sock'}->peerhost;
			$server{'failed_logins'}{$ip} = 0 unless (defined($server{'failed_logins'}{$ip}));
			$server{'failed_logins'}{$ip}++;
			if ($server{'failed_logins'}{$ip} > 3 && !$server{'config'}{'hacks'}) {
				$server{'ipbans'}{$ip} = "Spoofing attempt ('$name')";
				&save_ipbans();
				&kick($id,'IP BANNED: Spoof attempt detected.');
				return;
			}
			&kick($id,'Login failed. (Try again in 45 seconds.)');
			return;
		}
		# Do you?? God, why do you always gotta make things
		# so much harder than they really need to be...
	}
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && $_->{'active'} && lc($_->{'account'}) eq lc($name));
		print "$name tried to join, but is already here!\n";
		&kick($id,'Login failed: You\'re already connected.');
		return;
	}
	$server{'users'}[$id]{'account'} = $name;
	$server{'users'}[$id]{'nick'} = $server{'nick'}{lc($name)} || $name;
	$server{'users'}[$id]{'admin'} = $server{'admin'}{lc($name)} || 0;
	#$server{'users'}[$id]{'adminbreak'} = 1 if ($server{'users'}[$id]{'admin'} >= 100);
	$server{'users'}[$id]{'mute'} = $server{'mute'}{lc($name)} || 0;
	$server{'users'}[$id]{'mute_vote'} = $server{'mute_vote'}{lc($name)} || 0;
	if ($server{'users'}[$id]{'mute'}) {
		$server{'users'}[$id]{'nick'} = '&4[MUTED] '.&strip($server{'users'}[$id]{'nick'});
	}
	$name = $server{'users'}[$id]{'nick'};
	$server{'users'}[$id]{'speeding'} = 0;
	&global_msg("- $name&e is connecting...");
	print "$name is player type $type.\n" if ($type);
	&send_login($id);
	&send_map($id);
	$server{'users'}[$id]{'active'} = 0;
	&global_msg("- $name&e joined the game.");
	$server{'users'}[$id]{'active'} = 1;
	&global_spawn($id,$name,@{$server{'users'}[$id]{'pos'}},@{$server{'users'}[$id]{'rot'}});
	$server{'users'}[$id]{'services_timer'} = time()+10;
}

sub handle_build() {
	my ($id,$pos_x,$pos_y,$pos_z,$type,$dense) = @_;
	if ($server{'users'}[$id]{'tree'} && $type == 17) {
		unless (&map_getblock($pos_x+1,$pos_y,$pos_z) == 0
		&& &map_getblock($pos_x-1,$pos_y,$pos_z) == 0
		&& &map_getblock($pos_x,$pos_y,$pos_z+1) == 0
		&& &map_getblock($pos_x,$pos_y,$pos_z-1) == 0
		&& &map_getblock($pos_x+1,$pos_y,$pos_z+1) == 0
		&& &map_getblock($pos_x+1,$pos_y,$pos_z-1) == 0
		&& &map_getblock($pos_x-1,$pos_y,$pos_z+1) == 0
		&& &map_getblock($pos_x-1,$pos_y,$pos_z-1) == 0
		&& &map_getblock($pos_x,$pos_y+1,$pos_z) == 0
		&& &map_getblock($pos_x,$pos_y+2,$pos_z) == 0
		&& &map_getblock($pos_x,$pos_y+3,$pos_z) == 0
		&& &map_getblock($pos_x,$pos_y+4,$pos_z) == 0) {
			&send_blockchange($id,$pos_x,$pos_y,$pos_z,&map_getblock($pos_x,$pos_y,$pos_z));
			&send_msg($id,"Not enough room, can't build a tree here.");
			return;
		}
		&map_buildtree($pos_x,$pos_y,$pos_z);
	}
	elsif (&get_tileinfo($type)->{'plant'} && &map_getblock($pos_x,$pos_y-1,$pos_z) != 2 && &map_getblock($pos_x,$pos_y-1,$pos_z) != 3) {
		&send_blockchange($id,$pos_x,$pos_y,$pos_z,&map_getblock($pos_x,$pos_y,$pos_z));
		&send_msg($id,"Can't plant there.");
		return;
	}
	else {
		&map_setblock($pos_x,$pos_y,$pos_z,$type,$dense);
		my $atype = &map_getblock($pos_x,$pos_y,$pos_z);
		if ($atype != $type) { &send_blockchange($id,$pos_x,$pos_y,$pos_z,$atype); }
	}
}

# Client creates or destroys a block
sub handle_blockchange() {
	my ($id,$pos_x,$pos_y,$pos_z,$action,$type) = @_;
	my ($rel_x,$rel_y,$rel_z);
	# The muted cannot build.
	if ($server{'users'}[$id]{'mute'}) { &send_blockchange($id,$pos_x,$pos_y,$pos_z,$type); return; }
	if ($type > 49) {
		print "WARNING: Unknown block type $type selected by ".$server{'users'}[$id]{'nick'}.".\n";
		$type = 1;
	}
	# Don't build using the hidden block types
	if (!$server{'config'}{'hacks'}) {
		if ($type <= 0 || ($type >= 7 && $type <= 11)) {
			print "WARNING: Illegal block type $type selected by ".$server{'users'}[$id]{'nick'}.".\n";
			&kick($id,'Hack detected: Block type.');
			return;
		}
	}
	if (!$server{'config'}{'hacks'}) {
		# Don't break blocks that are out of the client's range! >:O
		$rel_x = $pos_x - floor($server{'users'}[$id]{'pos'}[0]/32);
		$rel_y = $pos_y - floor($server{'users'}[$id]{'pos'}[1]/32);
		$rel_z = $pos_z - floor($server{'users'}[$id]{'pos'}[2]/32);
		if (abs($rel_x) > 5 || abs($rel_y) > 5 || abs($rel_z) > 5) {
			&kick($id,'Hack detected: Block distance.');
			return;
		}
	}
	$type = $server{'users'}[$id]{'build'} if (defined($server{'users'}[$id]{'build'}) && $type == 1);
	my $display = &get_tileinfo($type)->{'display'};
	$display = $type unless (defined($display));
	my $dense = $server{'users'}[$id]{'dense'} || 0;
	if ($action == 0) {
		if (!$server{'config'}{'hacks'}) {
			if (&map_getblock($pos_x,$pos_y,$pos_z) == 7 && $server{'users'}[$id]{'admin'} < 20) {
				&kick($id,'Hack detected: Breaking admin blocks.');
				return;
			}
		}
		if ($server{'map'}{'dense'}{"$pos_x $pos_y $pos_z"} && !$server{'users'}[$id]{'adminbreak'}) {
			$type = &map_getblock($pos_x,$pos_y,$pos_z);
			my $display = &get_tileinfo($type)->{'display'};
			$display = $type unless (defined($display));
			&send_blockchange($id,$pos_x,$pos_y,$pos_z,$display);
			return;
		}
		if ($server{'users'}[$id]{'paint'}) {
			if ($type == &map_getblock($pos_x,$pos_y,$pos_z) && $dense == defined($server{'map'}{'dense'}{"$pos_x $pos_y $pos_z"})) { &send_blockchange($id,$pos_x,$pos_y,$pos_z,$display); }
			else { &handle_build($id,$pos_x,$pos_y,$pos_z,$type,$dense); }
		}
		else { &map_clearblock($pos_x,$pos_y,$pos_z); }
	}
	elsif ($action == 1) {
		if (!$server{'config'}{'hacks'}) {
			if (&get_tileinfo($type)->{'solid'} && $rel_x == 0 && ($rel_y == 0 || $rel_y == -1) && $rel_z == 0) {
				&kick($id,'Hack detected: Building on top of self.');
				return;
			}
		}
		if (defined($server{'users'}[$id]{'build'}) && $type == &map_getblock($pos_x,$pos_y,$pos_z) && $dense == defined($server{'map'}{'dense'}{"$pos_x $pos_y $pos_z"})) { &send_blockchange($id,$pos_x,$pos_y,$pos_z,$display); }
		else { &handle_build($id,$pos_x,$pos_y,$pos_z,$type,$dense); }
	}
	else {
		print "Unknown action type $action recieved from ".$server{'users'}[$id]{'nick'}."\n";
		#&kick($id,'Unknown block action.');
		return;
	}
}

# Client input
sub handle_input() {
	my ($id,$this_id,$pos_x,$pos_y,$pos_z,$rot_x,$rot_y) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	if (!$server{'config'}{'hacks'}) {
		if ($this_id != -1) {
			&kick($id,'Invalid id.');
			return;
		}
		if ($rot_y > 64 || $rot_y < -64) {
			&kick($id,'Invalid head rotation.');
			return;
		}
		if ($pos_x < 0 || $pos_y < 0 || $pos_z < 0
		|| $pos_x >= $size_x*32 || $pos_y >= ($size_y+3)*32+16 || $pos_z >= $size_z*32) {
			&kick($id,'Hack detected: Left the map.');
			return;
		}
		if (abs($pos_x-$server{'users'}[$id]{'pos'}[0]) > 8
		|| abs($pos_z-$server{'users'}[$id]{'pos'}[2]) > 8
		|| ($pos_y-$server{'users'}[$id]{'pos'}[1]) > 14) {
			if ($server{'users'}[$id]{'speeding'} > 2) { &kick($id,"Hack detected: Speeding."); } # Second frame, they're speed hacking.
			else { $server{'users'}[$id]{'speeding'}++; } # First frame, give them a warning. (Maybe they just used R to respawn)
		}
		else { $server{'users'}[$id]{'speeding'} = 0; } # Remove warnings if speed hack not detected.
	}
	@{$server{'users'}[$id]{'pos'}} = ($pos_x,$pos_y,$pos_z);
	@{$server{'users'}[$id]{'rot'}} = ($rot_x,$rot_y);
}

# When someone chats, I know!
sub handle_chat() {
	my ($id,$this_id,$msg) = @_;
	if (!$server{'config'}{'hacks'}) {
		if ($this_id != -1) {
			&kick($id,'Invalid id.');
			return;
		}
	}
	return if ($server{'users'}[$id]{'mute'}); # Ignore the muted.

	$msg =~ s/%c([0-9a-f])/&$1/g; # Change %c to proper color codes.
	$msg =~ s/&[0-9a-f](&[0-9a-f])/$1/g; # Remove duplicate/multiple color codes so only the last one takes effect.
	$msg =~ s/&[0-9a-f]$//g; # Remove any color codes at the end of the line.
	if ($msg =~ m|^/(\S+)\s*(.*)|) {
		my $cmd = uc($1);
		my @args = split(/ /,$2);
		if (defined($server{'commands'}{$cmd}) && $server{'users'}[$id]{'admin'} >= $server{'commands'}{$cmd}[1]) {
			print $server{'users'}[$id]{'account'}." admins: $cmd\n" if ($server{'commands'}{$cmd}[1] > 0);
			&{$server{'commands'}{$cmd}[0]}($id,@args);
		}
		else { &send_msg($id,"Unknown command '$cmd'"); }
	}
	elsif ($msg =~ /^xyzzy/) { &send_msg($id,"Nothing happens."); }
	elsif ($msg =~ /^#\s*(.+)/) { # Server-wide messages
		$msg = '&e# '.$server{'users'}[$id]{'nick'}.'&e shouts:&f '.$1;
		foreach (@{$server{'users'}}) {
			next unless defined($_);
			&send_raw($_->{'sock'},13,$id,$msg) if ($_->{'active'});
		}
	}
	elsif ($msg =~ /^@\s*(\S+) (.+)/) { # Message to a specific person
		my $found = 0;
		if (!defined($1) || $1 eq '' || $1 =~ /@/) {
			&send_chat($id,$msg);
			return;
		}
		my $nick = &strip(lc($1));
		my $text = substr($2,0,64-length('&d@'.&strip($server{'users'}[$id]{'nick'}).':&f '));
		$msg = '&d->*'.$nick.'*&f '.$text;
		&send_raw($server{'users'}[$id]{'sock'},13,$id,$msg);
		$msg = '&d@'.&strip($server{'users'}[$id]{'nick'}).':&f '.$text;
		foreach (@{$server{'users'}}) {
			next unless defined($_) && ($_->{'active'}) && (lc($_->{'account'}) eq $nick);
			$found = 1;
			&send_raw($_->{'sock'},13,$id,$msg);
			return;
		}
		unless ($found) { &send_msg($id,"Couldn't find '$1'"); }
	}
	else { &send_chat($id,$msg); } # Normal map chat
}

1;
