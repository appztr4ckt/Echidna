#!/usr/bin/perl
use warnings;
use strict;
use Net::HTTP;
use IO::Socket;
use IO::Select;
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
require "proxy_functions.pl";
require "proxy_game.pl";

# Some configuration stuff for you.
# Leave verify-names to false.
# TODO: Read most of this from server.properties @.@;
my %serverinfo = (
	name => 'Echidna Tribe', # Server name. (For the public listing only)
	port => 27015, # Port number the proxy will listen on
	server_port => 27016, # Port of the actual server (Preferrably, firewall this from internet connections so only the proxy can connect)
	max_players => 15, # Set the actual server's max-players and max-connections to one more than this, to prevent horrible errors.
		# max-connections gets reset to 3 every time you run the server, so be sure to add it to your startup script to compensate.
	public => 0, # Set to 1 to let anyone see it in the server list; Always keep the actual server's public set to false either way.
	version => 6 # Leave this, for now.
);

# Big fancey mess of Perl follows.
my ($socketset,$lsock,%proxsocks,%nicks,$raw_map,$sock_buffer,$pair_buffer,$current_sock);
our (%map,%game,@commands,@clients);

# Packet lengths
my (@packets) = (
	1+64+64+1, # 0 Login: version, name, verification/motd, premium/admin Level
	0, # 1 Ping
	0, # 2 Login accepted
	2+1024+1, # 3 Map blocks
	2+2+2, # 4 Map dimensions
	2+2+2+1+1, # 5 Client block change: pos, place/remove flag, type
	2+2+2+1, # 6 Server block change: pos, new type
	1+64+2+2+2+1+1, # 7 New player: id, name, pos, rot
	1+2+2+2+1+1, # 8 Player position+rotation: id, pos, rot
	1+1+1+1+1+1, # 9 movement+rotation: id, mom, rot
	1+1+1+1, # 10 movement: id, mom
	1+1+1, # 11 Player rotation: id, rot
	1, # 12 Player disconnect: id
	1+64, # 13 Message: id, string
	64 # 14 Kick message (You were kicked)
);

# Gets ready to wait for connections
sub open_sock() {
	$socketset = new IO::Select();
	$raw_map = '';
	print "Opening listen socket...\n";
	$lsock = IO::Socket::INET->new(
		Listen    => 5,
		LocalPort => $serverinfo{'port'},
		Proto     => 'tcp'
	) or die("Socket error: $!\n");
	$lsock->listen(16);
	$socketset->add($lsock);
}

# Connects a user to the server
sub proxy_connect() {
	my $client = shift;
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => $serverinfo{'server_port'},
		Proto => 'tcp'
	) or die("Socket error: $!\n");
	#$raw_map = ''; # Prepare to re-synchronise map?
	$proxsocks{"$sock"} = {
		type => 1,
		pair => $client,
		buffer => ''
	};
	$proxsocks{"$client"} = {
		type => 0,
		pair => $sock,
		buffer => ''
	};
	$socketset->add($sock);
	push(@clients,$client);
}

# Sends a heartbeat to minecraft.net
sub heartbeat() {
	my $first = shift;
	#print "Connecting to minecraft.net...\n";
	my $name = $serverinfo{'name'};
	$name =~ s/ /+/g;
	my $public = 'false';
	$public = 'true' if ($serverinfo{'public'});
	my $heart = Net::HTTP->new(
		Host => "www.minecraft.net",
		KeepAlive => 1,
		MaxLineLength => 0,
		MaxHeaderLines => 0
	) or die("Could not connect to minecraft.net: $@\n");
	#print "Posting request...\n";
	my $info = "port=$serverinfo{'port'}&users=0&max=$serverinfo{'max_players'}&name=$name&public=$public&version=$serverinfo{'version'}&salt=0";
	$heart->write_request('POST', "/heartbeat.jsp", (
		'Content-Type' => 'application/x-www-form-urlencoded',
		'Content-Language' => 'en-US',
		'User-Agent' => 'Java/1.6.0_13',
		Host => 'www.minecraft.net',
		Accept => 'text/html, image/gif, image/jpeg, *; q=.2, */*; q=.2',
		Connection => 'keep-alive'
	), $info);
	my ($code, $mess) = $heart->read_response_headers();
	unless ($first) {
		#print "Heartbeat.\n";
		#exit 0;
		return;
	}
	die("Heartbeat response: $code $mess\n") unless ($code eq '200');

	# Read page into buffer
	my ($n,$page,$buf);
	while ($n = $heart->read_entity_body($buf)) {
		next if ($n < 0);
		$page .= $buf;
	}
	my @lines = split(/\r\n/,$page); # Split the page into lines
	$heart->close();

	# This page just shows our URL.
	my $url = $lines[0];

	# Output to text file for copying
	open FILE,'>proxyurl.txt';
	print FILE "$url\n";
	close FILE;

	# Output to stdout so we know everything's okay
	print "My connect URL is:\n$url\n(Has been copied to proxyurl.txt)\n";
}

# Resets connections
sub disconnect() {
	foreach(@_) {
		undef $proxsocks{"$_"};
		$socketset->remove($_);
		$_->close();
		for(my $i = 0; $i < @clients; $i++) {
			if ($clients[$i] == $_) {
				splice(@clients,$i,1);
				last;
			}
		}
	}
}

# Add command hooks at runtime
sub add_command() {
	my ($cmd,$func,$lv,$desc) = @_;
	push(@commands, [uc($cmd), $func, $lv || 0, $desc || '']);
}

# Functions to get more information about a client socket
sub get_pair() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'pair'};
}

sub set_nick() {
	my ($sock,$nick) = @_;
	my $real_nick = $proxsocks{"$sock"}{'name'} || "$sock";
	$nicks{$real_nick} = $nick;
}

# Ugh. Find a better way to do this...
sub get_nick() {
	my ($sock) = @_;
	my $real_nick = $proxsocks{"$sock"}{'name'} || "$sock";
	return $nicks{$real_nick};
}

sub get_account() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'name'};
}

sub set_adminlevel() {
	my ($sock,$level) = @_;
	$proxsocks{"$sock"}{'adminlevel'} = $level;
}

sub get_adminlevel() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'adminlevel'};
}

sub get_id() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'id'};
}

sub get_pos() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'pos'} || [0,0,0];
}

sub get_rot() {
	my ($sock) = @_;
	return $proxsocks{"$sock"}{'rot'} || [1,1];
}

sub send_raw() {
	my ($sock,$msg) = @_;
	if ($sock == $current_sock) { $sock_buffer .= $msg; }
	elsif ($sock == &get_pair($current_sock)) { $pair_buffer .= $msg; }
	else { print $sock $msg; }
}

sub send_map() {
	my ($sock) = @_;
	my $file = pack("L>c*",$map{'size'}{'x'}*$map{'size'}{'y'}*$map{'size'}{'z'},@{$map{'blocks'}});
	my $buffer;
	#my $gz = new IO::Compress::Gzip \$buffer;
	#print $gz $file;
	gzip \$file => \$buffer;
	undef $file;

	my $count = 1;
	my $total = ceil(length($buffer) / 1024);
	while ($buffer) {
		my ($packet,$remainder) = unpack("a1024a*",$buffer);
		my ($length);
		if (length($buffer) >= 1024) { $length = 1024; }
		else { $length = length($buffer); }
		my $percent = floor($count*100/$total);
		$percent = 100 if ($percent > 100);
		#print "Sending $length, $percent%: $packet\n";
		&send_raw($sock,pack("cS>a1024c",3,$length,$packet,$percent));
		$buffer = $remainder;
		$count += 1;
	}
	#open FILE,'>>RAW_MAP';
	#binmode FILE;
	#print FILE $msg;
	#close FILE;
}

# Parses messages recieved
sub parse_msg() {
	my ($sock,$data) = @_;
	my $msg_type;
	($msg_type,$data) = unpack("ca*",$data);
	my $pair = $proxsocks{"$sock"}{'pair'};
	my ($sock_type) = ($proxsocks{"$sock"}{'type'});

	my $raw = '';
	my @a = split(//,$data);
	foreach (@a) {
		$raw .= ord($_).' ';
	}

	my $name;
	$name = $proxsocks{"$sock"}{'name'} || 'Client' if ($sock_type == 0);
	$name = 'Server ('.$proxsocks{"$pair"}{'name'}.')' || 'Server' if ($sock_type == 1);
	unless ($msg_type == 1 || $msg_type == 3 || $msg_type == 8 || $msg_type == 9 || $msg_type == 10 || $msg_type == 11 || $msg_type == 13) {
		if (open(FILE,'>>raw.log')) {
			print FILE "$name => $msg_type $raw\n";
			close FILE;
		}
	}

	if ($msg_type == 0) {
		if ($sock_type == 0) {
			my ($version,$name,$verify,$premium) = unpack("cA64A64c",$data);
			if ($version != $serverinfo{'version'}) {
				print "Oh dear. $name is using client version $version, but the proxy was only made to handle $serverinfo{'version'}\n";
			}
			$proxsocks{"$sock"}{'name'} = $name;
			$name="&c$name"if($name eq'JTE');
			&set_nick($sock,$name);
			print "$name logged in.\n";
		}
		else {
			my ($version,$name,$motd,$admin) = unpack("cA64A64c",$data);
			$proxsocks{"$pair"}{'adminlevel'} = $admin;
		}
	}
	elsif ($msg_type == 1) {
		# Ping.
	}
	elsif ($msg_type == 2) {
		# Login successful.
	}
	elsif ($msg_type == 3) {
		return 1 unless (defined($raw_map));
		#open(FILE,'>>SERVER_MAP');
		#binmode(FILE);
		#print FILE $data;
		#close FILE;
		my ($packet_size,$map_data,$percent) = unpack("S>a1024c",$data);
		#$raw_map .= unpack("a$packet_size",$map_data);
		$raw_map .= $map_data;
		return 1;
	}
	elsif ($msg_type == 4) {
		#return 0 unless (defined($raw_map));
		if (defined($raw_map)) {
			($map{'size'}{'x'},$map{'size'}{'z'},$map{'size'}{'y'}) = unpack("S>3",$data);
			print "Loading map blocks...\n";
			my $buffer;
			gunzip(\$raw_map => \$buffer) or die "Unzip map data failed: $GunzipError\n";
			undef $raw_map;
			my $len;
			$map{'blocks'} = [unpack("c*",$buffer)];
			shift(@{$map{'blocks'}});
			shift(@{$map{'blocks'}});
			shift(@{$map{'blocks'}});
			shift(@{$map{'blocks'}});
			if (defined($game{'hooks'}{'map_filter'})) {
				&{$game{'hooks'}{'map_filter'}}($map{'blocks'});
			}
			print "Map blocks have been loaded from the server.\n";
		}
		&send_map($pair);
		return 0;
	}
	elsif ($msg_type == 5) {
		my ($pos_x,$pos_z,$pos_y,$op,$type) = unpack("S>3c2",$data);
		if ($op == 0) {
			if (defined($game{'hooks'}{'on_break'})) {
				return &{$game{'hooks'}{'on_break'}}($sock,&get_block($pos_x,$pos_y,$pos_z),$pos_x,$pos_y,$pos_z);
			}
		}
		else {
			if (defined($game{'hooks'}{'on_build'})) {
				return &{$game{'hooks'}{'on_build'}}($sock,$type,$pos_x,$pos_y,$pos_z);
			}
		}
	}
	elsif ($msg_type == 6) {
		my ($pos_x,$pos_z,$pos_y,$type) = unpack("S>3c",$data);
		my $override;
		if (defined($game{'hooks'}{'on_block_type'})) {
			$override = &{$game{'hooks'}{'on_block_type'}}($sock,$type,$pos_x,$pos_y,$pos_z);
		}
		&set_block($pos_x,$pos_y,$pos_z,$type) unless ($override);
		return $override;
	}
	elsif ($msg_type == 7) {
		# Player's initial spawn
		my ($id,$name,$pos_x,$pos_z,$pos_y,$rotx,$roty) = unpack("cA64S>3c2",$data);
		my $ignore = 0;
		if ($id < 0) {
			print "Waiting for id on ".&get_nick($pair)."\n";
			$proxsocks{"$pair"}{'pos'} = [$pos_x,$pos_z,$pos_y];
			$proxsocks{"$pair"}{'rot'} = [$rotx,$roty];
			&send_msg($sock,"|MyID|$pair");
			if (defined($game{'hooks'}{'on_spawn'})) {
				$ignore = &{$game{'hooks'}{'on_spawn'}}($pair,$pos_x,$pos_y,$pos_z,$rotx,$roty);
			}
		}
		if ($name eq 'JTE') { $name = "&cJTE"; }
		&send_raw($pair,pack("c2A64S>3c2",7,$id,$name,$pos_x,$pos_z,$pos_y,$rotx,$roty)) if (!$ignore);
		return 1;
	}
	elsif ($msg_type == 8) {
		# Player position+rotation
		my ($id,$pos_x,$pos_z,$pos_y,$rotx,$roty) = unpack("cS>3c2",$data);
		if ($sock_type == 0) {
			$proxsocks{"$sock"}{'pos'} = [$pos_x,$pos_z,$pos_y];
			$proxsocks{"$sock"}{'rot'} = [$rotx,$roty];
		}
		elsif ($sock_type == 1 && $id < 0) {
			$proxsocks{"$pair"}{'pos'} = [$pos_x,$pos_z,$pos_y];
			$proxsocks{"$pair"}{'rot'} = [$rotx,$roty];
		}
	}
	elsif ($msg_type == 9) {
		# Player movement+rotation
	}
	elsif ($msg_type == 10) {
		# Player movement
	}
	elsif ($msg_type == 11) {
		# Player rotation
	}
	elsif ($msg_type == 12) {
		# Player disconnect
	}
	elsif ($msg_type == 13) {
		if ($sock_type == 0) {
			my ($type,$message) = unpack("cA64",$data);
			if ($message =~ m|^/(.+)|) {
				my @args = split(/ /,$1);
				my $cmd = uc(shift(@args));
				foreach (@commands) {
					if ($cmd eq $_->[0] && &get_adminlevel($sock) >= $_->[2]) {
						return $_->[1]($sock,@args);
					}
				}
			}
			else {
				if (defined($game{'hooks'}{'on_say'})) {
					return &{$game{'hooks'}{'on_say'}}($sock,$message);
				}
			}
		}
		else {
			my ($id,$message) = unpack("cA64",$data);
			if ($id < 0) {
				if (defined($game{'hooks'}{'on_server_text'})) {
					return &{$game{'hooks'}{'on_server_text'}}($pair,$message);
				}
			}
			elsif ($message =~ /([^:]+): \|MyID\|(.+)$/) {
				my ($nick,$sock) = ($1,$2);
				return 1 if ($proxsocks{$sock}{'id'} || $id < 0);
				print "Got id $id for $nick\n";
				$proxsocks{$sock}{'id'} = $id;
				return 1;
			}
			elsif ($message =~ /([^:]+): (.+)/) {
				my $nick = &get_nick(&find_account($1));
				my $msg = $2;
				if (defined($game{'hooks'}{'on_player_text'})) {
					return &{$game{'hooks'}{'on_player_text'}}($pair,$nick,$msg,$id);
				}
				else { &send_msg($pair,"$nick: $msg",$id); }
				return 1;
			}
		}
	}
	elsif ($msg_type == 14) {
		# Player was kicked.
		print(($proxsocks{"$sock"}{'name'} || 'Player') . " was kicked from the server.\n");
		&send_raw($pair,pack("cA64",14,$data));
		&disconnect($sock,$pair);
		return 1;
	}
	else {
		&send_msg($sock,"Client $msg_type: $raw") if ($sock_type == 0);
		&send_msg($pair,"Server $msg_type: $raw") if ($sock_type == 1);
	}
	return 0;
}

# Does everything.
sub main() {
	print "MineCraft Proxy Server\n";
	if (open(FILE,'>raw.log')) {
		close FILE;
	}
	&open_sock();
	my $last_heartbeat = 0;
	&heartbeat(1);
	print "Waiting for connections...\n";
	while (1) {
		my ($ready) = IO::Select->select($socketset, undef, undef, 3);
		foreach my $sock (@{$ready}) {
			if ($sock == $lsock) {
				print "Player connected.\n";
				my $ns = $lsock->accept();
				$socketset->add($ns);
				&proxy_connect($ns);
				next;
			}
			my $data;
			my $pair = $proxsocks{"$sock"}{'pair'};
			unless ($sock->recv($data,0xFFFF)) {
				print(($proxsocks{"$sock"}{'name'} || $proxsocks{"$pair"}{'name'} || 'Player') . " disconnected.\n");
				&disconnect($sock,$pair);
				next;
			}
			$sock_buffer = '';
			$pair_buffer = '';
			$current_sock = $sock;

			$data = $proxsocks{"$sock"}{'buffer'}.$data;
			$proxsocks{"$sock"}{'buffer'} = '';
			my $data_len = length($data);
			while ($data && $sock->connected && $pair->connected) {
				my $msg_len = $packets[ord($data)];
				$msg_len = -1 unless(defined($msg_len));
				if ($msg_len != -1) { $msg_len += 1; }
				else { $msg_len = length($data); }
				my $msg;
				if ($msg_len <= length($data)) {
					$msg = substr($data,0,$msg_len);
					$data = substr($data,$msg_len,length($data));
				}
				else {
					$proxsocks{"$sock"}{'buffer'} .= $data;
					$data = '';
					next;
				}
				my $ignore = &parse_msg($sock,$msg);
				&send_raw($pair,$msg) unless ($ignore);
			}
			if ($sock->connected && $pair->connected) {
				print $sock $sock_buffer;
				print $pair $pair_buffer;
			}
			unless ($sock->connected && $pair->connected) {
				print(($proxsocks{"$sock"}{'name'} || $proxsocks{"$pair"}{'name'} || 'Player') . " disconnected.\n");
				&disconnect($sock,$pair);
			}
		}
		my ($current) = time();
		if ($current >= $last_heartbeat+45) {
			$last_heartbeat = $current;
			#my $fork = fork();
			#if(!defined($fork)) { &heartbeat(1); } # fork() failed us. This happens rarely.
			#elsif ($fork == 0) { &heartbeat(0); }
			&heartbeat(0);
		}
	}
}

# And of course, you have to turn the key...
&main();
