#!/usr/bin/perl
use warnings;
use strict;

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

sub load_serverinfo() {
	print "Loading configuration...\n";

	$server{'config'} = {};
	if (open FILE,'<config.txt') {
		foreach (<FILE>) {
			next if (/^\s*#/);
			if (/(\S+) ?([^#\n\r]*)/) {
				my ($name,$data) = (lc($1),$2);
				$data = 1 unless (defined($data) && $data ne '');
				$server{'config'}{$name} = $data;
				#print "Admin: $name $level\n";
			}
		}
		close FILE;
	}

	print "Loading information on accounts...\n";

	$server{'admin'} = {};
	if (open FILE,'<admins.txt') {
		foreach (<FILE>) {
			if (/(\S+) ?(.*)/) {
				my ($name,$level) = (lc($1),$2);
				$level = 100 unless (defined($level) && $level ne '');
				$server{'admin'}{$name} = $level;
				#print "Admin: $name $level\n";
			}
		}
		close FILE;
	}

	$server{'bans'} = {};
	if (open FILE,'<banned.txt') {
		foreach (<FILE>) {
			if (/(\S+)/) { $server{'bans'}{lc($1)} = 1; }
		}
		close FILE;
	}

	$server{'ipbans'} = {};
	if (open FILE,'<banned-ip.txt') {
		foreach (<FILE>) {
			if (/(\S+) ?(.*)/) { $server{'ipbans'}{$1} = ($2 || '(unknown)'); }
		}
		close FILE;
	}

	$server{'nick'} = {};
	if (open FILE,'<nicks.txt') {
		foreach (<FILE>) {
			if (/(\S+) ?(.*)/) {
				my ($name,$nick) = (lc($1),$2);
				$server{'nick'}{$name} = $nick;
			}
		}
		close FILE;
	}

	$server{'mute_vote'} = {};
	if (open FILE,'<mute_vote.txt') {
		foreach (<FILE>) {
			if (/(\S+) ?(.*)/) {
				my ($name,$vote) = (lc($1),$2);
				$server{'mute_vote'}{$name} = $vote;
			}
		}
		close FILE;
	}

	$server{'mute'} = {};
	if (open FILE,'<muted.txt') {
		foreach (<FILE>) {
			if (/(\S+)/) { $server{'mute'}{lc($1)} = 1; }
		}
		close FILE;
	}
}

sub save_admins() {
	return unless(open FILE,'>admins.txt');
	foreach (keys %{$server{'admin'}}) {
		next unless defined($server{'admin'}{$_});
		print FILE "$_ ".$server{'admin'}{$_}."\n";
	}
	close FILE;
}

sub save_bans() {
	return unless(open FILE,'>banned.txt');
	foreach (keys %{$server{'bans'}}) {
		next unless defined($server{'bans'}{$_});
		print FILE "$_\n";
	}
	close FILE;
}

sub save_ipbans() {
	return unless(open FILE,'>banned-ip.txt');
	foreach (keys %{$server{'ipbans'}}) {
		next unless defined($server{'ipbans'}{$_});
		print FILE "$_ $server{'ipbans'}{$_}\n";
	}
	close FILE;
}

sub save_nicks() {
	return unless(open FILE,'>nicks.txt');
	foreach (keys %{$server{'nick'}}) {
		next unless defined($server{'nick'}{$_});
		print FILE "$_ ".$server{'nick'}{$_}."\n";
	}
	close FILE;
}

sub save_mutevote() {
	return unless(open FILE,'>mute_vote.txt');
	foreach (keys %{$server{'mute_vote'}}) {
		next unless (defined($server{'mute_vote'}{$_}) && $server{'mute_vote'}{$_} > 0);
		print FILE "$_ ".$server{'mute_vote'}{$_}."\n";
	}
	close FILE;
}

sub save_muted() {
	return unless(open FILE,'>muted.txt');
	foreach (keys %{$server{'mute'}}) {
		next unless defined($server{'mute'}{$_});
		print FILE "$_\n";
	}
	close FILE;
}
