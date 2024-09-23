#!/usr/bin/perl
use warnings;
use strict;
use IO::Socket;
use IO::Select;
use Time::HiRes qw( time );
require 'heartbeat.pl';
require 'packet.pl';
require 'map.pl';
require 'command.pl';
require 'serverinfo.pl';

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

# Internal stuff (Leave this alone)
$server{'info'} = {
	version => 7,
	salt => int(rand(0xFFFFFFFF))-0x80000000,
	rawlog => 0
};

# Gets ready to wait for connections
sub open_sock() {
	$server{'socketset'} = new IO::Select();
	$server{'lsock'} = IO::Socket::INET->new(
		Listen    => 5,
		Timeout   => 1,
		LocalPort => $server{'config'}{'port'},
		Proto     => 'tcp'
	) or die("Socket error: $!\n");
	# We won't make the same mistake the official server does:
	# Keep one EXTRA slot open for accepting (in order to deny) requests over the limit.
	# Dumbasses...
	$server{'lsock'}->listen($server{'config'}{'max_players'}+1);
	$server{'socketset'}->add($server{'lsock'});
}

# Handles new connections
sub handle_connection() {
	my $sock = shift;
	# Find an open player slot.
	my $id;
	for ($id = 0; $id < $server{'config'}{'max_players'}; $id++) {
		last unless defined($server{'users'}[$id]{'active'});
	}
	my $ip = $sock->peerhost;
	if ($server{'ipbans'}{$ip}) {
		print "$ip tried to join, but is on the ban list.\n";
		&send_kick($sock,'You are still banned.');
		$sock->close();
		return;
	}
	# None found.
	if ($id >= $server{'config'}{'max_players'}) {
		print "Connection refused: Server is full.\n";
		&send_kick($sock,'Server is full.');
		$sock->close();
		return;
	}
	$sock->timeout(1);
	# Add the new player and wait for their login.
	print "Client $id connected.\n";
	$server{'users'}[$id]{'timeout'} = time()+15;
	$server{'users'}[$id]{'active'} = 0;
	$server{'users'}[$id]{'sock'} = $sock;
	$server{'users'}[$id]{'id'} = $id;
	$server{'socketset'}->add($sock);
}

# Handles dead connections
sub handle_disconnect() {
	my $id = shift;
	die unless defined($id);
	my $nick = $server{'users'}[$id]{'nick'};
	my $sock = $server{'users'}[$id]{'sock'};
	$server{'users'}[$id]{'active'} = 0;
	#if (!$server{'users'}[$id]{'kicked'}) { &map_save(0); }
	&global_die($id);
	delete $server{'users'}[$id];
	$server{'socketset'}->remove($sock);
	$sock->close();
	if (!$server{'users'}[$id]{'kicked'}) {
		if (defined($nick)) { &global_msg("- $nick&e disconnected."); }
		else { print "$id disconnected.\n"; };
	}
}

# Strips color codes from a message;
sub strip() {
	my $msg = shift;
	$msg =~ s/&[0-9a-f]//g;
	return $msg;
}

# Disconnects a user.
sub kick() {
	my ($id,$msg) = @_;
	die unless defined($id);
	&send_kick($server{'users'}[$id]{'sock'},$msg);
	print $server{'users'}[$id]{'account'}." has been kicked (".$msg.")\n" if ($server{'users'}[$id]{'account'});
	&global_msg("- ".$server{'users'}[$id]{'account'}." has been kicked (".$msg.")") if ($server{'users'}[$id]{'account'});
	$server{'users'}[$id]{'kicked'} = 1;
	&handle_disconnect($id);
}

sub update_position() {
	my ($user) = @_;
	return unless (defined($user->{'old_pos'}) && defined($user->{'old_rot'}) && defined($user->{'base_pos'}));
	my @old_pos = @{$user->{'old_pos'}};
	my @old_rot = @{$user->{'old_rot'}};
	my @base_pos = @{$user->{'base_pos'}};
	my @pos = @{$user->{'pos'}};
	my @rot = @{$user->{'rot'}};
	my $id = $user->{'id'};

	my $changed = 0;
	$changed |= 1 if ($old_pos[0] != $pos[0] || $old_pos[1] != $pos[1] || $old_pos[2] != $pos[2]);
	$changed |= 2 if ($old_rot[0] != $rot[0] || $old_rot[1] != $rot[1]);
	$changed |= 4 if (abs($pos[0]-$base_pos[0]) > 32 || abs($pos[1]-$base_pos[1]) > 32 || abs($pos[2]-$base_pos[2]) > 32);
	$changed |= 4 if (($pos[0] == $old_pos[0] && $pos[1] == $old_pos[1] && $pos[2] == $old_pos[2])
					&& ($pos[0] != $base_pos[0] || $pos[1] != $base_pos[1] || $pos[2] != $base_pos[2]));
	$changed = 0 if ($user->{'hide'});

	if ($changed & 4) {
		foreach (@{$server{'users'}}) {
			next unless defined($_);
			next if ($user == $_ && !$user->{'showself'});
			&send_raw($_->{'sock'},8,$id,@pos,@rot);
			$user->{'base_pos'} = \@pos;
		}
	}
	elsif ($changed == 1) {
		foreach (@{$server{'users'}}) {
			next unless defined($_) && $_->{'active'};
			next if ($user == $_ && !$user->{'showself'});
			&send_raw($_->{'sock'},10,$id,$pos[0]-$old_pos[0],$pos[1]-$old_pos[1],$pos[2]-$old_pos[2]);
		}
	}
	elsif ($changed == 2) {
		foreach (@{$server{'users'}}) {
			next unless defined($_) && $_->{'active'};
			next if ($user == $_ && !$user->{'showself'});
			&send_raw($_->{'sock'},11,$id,@rot);
		}
	}
	elsif ($changed == 3) {
		foreach (@{$server{'users'}}) {
			next unless defined($_) && $_->{'active'};
			next if $user == $_ && !$user->{'showself'};
			&send_raw($_->{'sock'},9,$id,$pos[0]-$old_pos[0],$pos[1]-$old_pos[1],$pos[2]-$old_pos[2],@rot);
		}
	}

	@{$user->{'old_pos'}} = @{$user->{'pos'}};
	@{$user->{'old_rot'}} = @{$user->{'rot'}};
	$user->{'last_move'} = floor(time);
}

# Main function
sub main() {
	print "Echidna Tribe Standard Server\n";
	if ($server{'info'}{'rawlog'}) { open FILE,'>raw.log'; close FILE; }
	&load_serverinfo();
	&heartbeat(1);
	$server{'map_name'} = $server{'config'}{'map'};
	unless (&map_load("maps/$server{'map_name'}.gz")) {
		&map_new(1,128,64,128);
		&map_save(1);
	}
	&open_sock();
	my $time = floor(time);
	$server{'save_time'} = $time;
	$server{'backup_time'} = $time;
	$server{'ping'} = $time;
	$server{'globalbuffer'} = '';
	print "Ready.\n\n";
	while(1) {
		my ($ready) = IO::Select->select($server{'socketset'}, undef, undef, 0.2);

		foreach my $sock (@{$ready}) {
			if ($sock == $server{'lsock'}) { &handle_connection($sock->accept()); next; }
			my $id;
			foreach (@{$server{'users'}}) {
				next unless (defined($_) && defined($_->{'sock'}) && $sock == $_->{'sock'});
				$id = $_->{'id'};
				last;
			}
			unless (defined($id)) {
				$server{'socketset'}->remove($sock);
				$sock->close();
			}
			my $buffer;
			unless ($sock->recv($buffer,0xFFFF)) { die unless defined($id); &handle_disconnect($id); next; }
			if ($server{'clear_messages'}) { $server{'users'}[$id]{'buffer'} = ''; }
			else { $server{'users'}[$id]{'buffer'} = &handle_packet($id,($server{'users'}[$id]{'buffer'}||'').$buffer); }
		}
		undef $server{'clear_messages'} if (defined($server{'clear_messages'}) && time() >= $server{'clear_messages'});

		# Ping the players every half a second
		if (time() >= $server{'ping'}+0.5) {
			&send_ping();
			$server{'ping'} = time();
		}

		# Update the player's positions and orientations only once every so often.
		foreach (@{$server{'users'}}) {
			if (defined($_->{'timeout'}) && floor(time) > $_->{'timeout'}) {
				&kick($_->{'id'},"You must send a login.");
				next;
			}
			next unless (defined($_) && $_->{'active'});
			if (defined($_->{'services_timer'}) && floor(time) > $_->{'services_timer'}) {
				&send_msg($_->{'id'},'This server is running on Echidna Tribe services.');
				&send_msg($_->{'id'},'Type &f/help&e for commands.');
				undef $_->{'services_timer'};
			}
			#next unless (time() >= $_->{'last_move'}+0.1);
			&update_position($_);
		}

		&map_think();

		if ($server{'globalbuffer'}) {
			foreach (@{$server{'users'}}) {
				next unless (defined($_) && $_->{'active'} && $_->{'sock'} && defined($_->{'id'}));
				die unless defined($_->{'id'});
				$_->{'sock'}->send($server{'globalbuffer'}) or &handle_disconnect($_->{'id'});
			}
		}
		$server{'globalbuffer'} = '';

		&map_save(0) if (floor(time) > $server{'save_time'}+60);
		&heartbeat(0) if (floor(time) > $server{'heartbeat'}+45); # Update the heartbeat every 45 seconds.
	}
}

&main();
