#!/usr/bin/perl
use warnings;
use strict;
use Net::HTTP;

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

# Sends a heartbeat to minecraft.net if the configuration allows.
# Gets a URL for you to use to connect either way.
sub heartbeat() {
	my $first = shift;
	$server{'heartbeat'} = time();

	# Not to be listed on the minecraft master list server?
	# No problem, let's negotiate an IP-based URL instead.
	unless ($server{'config'}{'heartbeat'}) {
		return unless ($first);
		my $ip = '127.0.0.1';
		# Attempt to get IP address from www.EchidnaTribe.org/ip.php in order to generate a proper URL.
		# Don't worry, it's safe. It'll just go back to 127.0.0.1 if for any reason this fails.
		my $sock = Net::HTTP->new(Host => "www.echidnatribe.org");
		return &ip_url($ip) unless ($sock); # Couldn't connect (Website down or dead)
		$sock->write_request('GET', "/ip.php");
		my $code = $sock->read_response_headers();
		return &ip_url($ip) unless ($code == 200); # Didn't get an OK (Probably a 404 or something)
		# Read in the page...
		my ($n,$page,$buf);
		while ($n = $sock->read_entity_body($buf)) {
			next if ($n < 0);
			$page .= $buf;
		}
		$sock->close();
		# And now we finally have our actual IP.
		$ip = $page;
		&ip_url($ip);
		return;
	}

	# Web-ify the server name
	my $name = &strip($server{'config'}{'name'}); # Get the server name
	#$name =~ s/ /+/g; # Turn spaces into +
	$name =~ s/(\W)/sprintf("%%%02x",ord($1))/ge; # Turn everything else into %3F-type stuff.

	# Convert public to string.
	my $public = 'false';
	$public = 'true' if ($server{'config'}{'public'});

	my $user_count = 0;
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		$user_count++;
	}

	# Generate our post URL string thing.
	my $info = "port=$server{'config'}{'port'}";
	$info .= "&users=$user_count";
	$info .= "&max=$server{'config'}{'max_players'}";
	$info .= "&name=$name";
	$info .= "&public=$public";
	$info .= "&version=$server{'info'}{'version'}";
	$info .= "&salt=$server{'info'}{'salt'}";

	# Connect!
	my $sock = Net::HTTP->new(
		Host => "www.minecraft.net",
		KeepAlive => 1,
		MaxLineLength => 0,
		MaxHeaderLines => 0
	);
	unless ($sock) { die ("Could not connect to minecraft.net: $@\n") if ($first); return; }

	# Write our request
	$sock->write_request('POST', "/heartbeat.jsp", (
		# All of these are an attempt to make our query indistinguishable from Java servers.
		# Just in case.
		'Content-Type' => 'application/x-www-form-urlencoded',
		'User-Agent' => 'Java/1.6.0_13',
		Accept => 'text/html, image/gif, image/jpeg, *; q=.2, */*; q=.2',
	), $info);

	# If this isn't the first time, that's all we need to do here.
	unless ($first) { return; }

	# Otherwise, get the result.
	my ($code, $mess) = $sock->read_response_headers();
	die("Heartbeat response: $code $mess\n") unless ($code == 200);

	# Read page into buffer
	my ($n,$page,$buf);
	while ($n = $sock->read_entity_body($buf)) {
		next if ($n < 0);
		$page .= $buf;
	}
	my @lines = split(/\r\n/,$page); # Split the page into lines
	$sock->close();

	# This page just shows our URL.
	my $url = $lines[0];

	# Output to stdout so we know everything's okay
	print "My connect URL is:\n$url\n";
	# Output to text file for copying
	if (open(FILE,'>externalurl.txt')) {
		print FILE "$url\n";
		close FILE;
		print "(Has been copied to externalurl.txt)\n";
	}
}

# All this does is print an IP-based URL.
sub ip_url() {
	my $ip = shift;
	my $port = $server{'config'}{'port'};

	# Encode the address in escape codes.
	# ... This does nothing useful, I know.
	# ... In fact, it's completely useless because the server automatically de-encrypts it. Damn.
	#$ip =~ s/(.)/sprintf("%%%02x",ord($1))/ge;
	#$port =~ s/(.)/sprintf("%%%02x",ord($1))/ge;

	my $url = "http://www.minecraft.net/play.jsp?ip=$ip&port=$port";
	print "My connect URL is:\n$url\n";
	if (open(FILE,'>externalurl.txt')) {
		print FILE "$url\n";
		close FILE;
		print "(Has been copied to externalurl.txt)\n";
	}
}

1;
