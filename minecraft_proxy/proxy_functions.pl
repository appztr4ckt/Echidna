#!/usr/bin/perl
use warnings;
use strict;

our (%map,@clients);

# Convinience functions
sub set_block() {
	my ($x,$y,$z,$t) = @_;
	$map{'blocks'}[($z * $map{'size'}{'y'} + $y) * $map{'size'}{'x'} + $x] = $t;
}

sub get_block() {
	my ($x,$y,$z) = @_;
	return $map{'blocks'}[($z * $map{'size'}{'y'} + $y) * $map{'size'}{'x'} + $x] || 0;
}

sub send_block() {
	my ($sock,$pos_x,$pos_y,$pos_z,$type) = @_;
	&send_raw($sock,pack("cS>3c",6,$pos_x,$pos_z,$pos_y,$type));
}

sub send_msg() {
	my ($sock,$msg,$id) = @_;
	$id = -1 unless(defined($id));
	&send_raw($sock,pack("c2A64",13,$id,$msg));
}

sub global_msg() {
	my ($msg,$id) = @_;
	$id = -1 unless(defined($id));
	foreach(@clients) {
		&send_raw($_,pack("c2A64",13,$id,$msg));
	}
}

sub find_account() {
	my ($name) = @_;
	foreach(@clients) {
		return $_ if (&get_account($_) eq $name);
	}
	return undef;
}

1;
