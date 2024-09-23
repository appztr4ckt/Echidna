#!/usr/bin/perl
use warnings;
use strict;
use POSIX;
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

my (@tiles) = (
	{ # Air
		light => 1
	},
	{ # Stone
		solid => 1
	},
	{ # Grass
		solid => 1
		#on_think => \&grass_think
		#think_time => 2
	},
	{ # Dirt
		solid => 1
	},
	{ # Cobblestone
		solid => 1
	},
	{ # Wood
		solid => 1
	},
	{ # Plant
		light => 1,
		plant => 1,
		on_think => \&plant_think,
		think_time => 2
	},
	{ # Solid Admin Rock
		solid => 1
	},
	{ # Water (Active)
		on_think => \&water_think,
		think_time => 0.2,
		liquid => 1
	},
	{ # Water (Passive)
		on_breaktouch => \&still_liquid_think,
		liquid => 1
	},
	{ # Lava (Active)
		on_think => \&lava_think,
		think_time => 1.2,
		liquid => 1
	},
	{ # Lava (Passive)
		on_breaktouch => \&still_liquid_think,
		liquid => 1
	},
	{ # Sand
		solid => 1,
		on_build => \&sand_think,
		on_breaktouch => \&sand_think
	},
	{ # Gravel
		solid => 1,
		on_build => \&sand_think,
		on_breaktouch => \&sand_think
	},
	{ # Gold ore
		solid => 1
	},
	{ # Iron ore
		solid => 1
	},
	{ # Coal
		solid => 1
	},
	{ # Tree Trunk/Stump
		solid => 1
	},
	{ # Tree Leaves
		solid => 1,
		light => 1
	},
	{ # Sponge
		solid => 1,
		on_build => \&sponge_build,
		on_break => \&sponge_break
	},
	{ # Glass
		solid => 1,
		light => 1
	},
	{ # Red Cloth
		solid => 1
	},
	{ # Orange Cloth
		solid => 1
	},
	{ # Yellow Cloth
		solid => 1
	},
	{ # Yellow-Green Cloth
		solid => 1
	},
	{ # Green Cloth
		solid => 1
	},
	{ # Green-Blue Cloth
		solid => 1
	},
	{ # Cyan Cloth
		solid => 1
	},
	{ # Blue Cloth
		solid => 1
	},
	{ # Blue-Purple Cloth
		solid => 1
	},
	{ # Purple Cloth
		solid => 1
	},
	{ # Indigo Cloth
		solid => 1
	},
	{ # Violet Cloth
		solid => 1
	},
	{ # Pink Cloth
		solid => 1
	},
	{ # Dark-Grey Cloth
		solid => 1
	},
	{ # Grey Cloth
		solid => 1
	},
	{ # White Cloth
		solid => 1
	},
	{ # Yellow flower
		light => 1,
		plant => 1,
		on_think => \&plant_think,
		think_time => 2
	},
	{ # Red flower
		light => 1,
		plant => 1,
		on_think => \&plant_think,
		think_time => 2
	},
	{ # Brown mushroom
		light => 1,
		plant => 1,
		on_think => \&shroom_think,
		think_time => 2
	},
	{ # Red mushroom
		light => 1,
		plant => 1,
		on_think => \&shroom_think,
		think_time => 2
	},
	{ # Gold
		solid => 1
	},
	{ # Iron
		solid => 1
	},
	{ # Double-Halfblock
		solid => 1
	},
	{ # Halfblock
		solid => 1,
		halfblock => 43
	},
	{ # Brick
		solid => 1
	},
	{ # TNT
		solid => 1
	},
	{ # Bookshelf
		solid => 1
	},
	{ # Mossy Cobblestone
		solid => 1
	},
	{ # Obsidian
		solid => 1
	}
);

my (@specials) = (
	{ # Lava Sponge
		display => 19,
		solid => 1,
		on_build => \&lavasponge_build,
		on_break => \&lavasponge_break
	},
	{ # Dynamite
		display => 46,
		solid => 1,
		on_think => \&dynamite_think,
		think_time => 1.0
	},
	{ # Super Sponge
		display => 19,
		solid => 1,
		on_build => \&supersponge_build,
		on_break => \&supersponge_break
	},
	{ # Watervator
		display => 9,
		liquid => 1
	},
	{ # Soccer ball
		display => 19,
		solid => 1,
		on_think => \&soccer_think,
		think_time => 0.2,
		on_break => \&soccer_break
	},
);

sub get_tileinfo() {
	my ($type) = @_;
	$type = 0 unless (defined($type));
	return $specials[abs($type)-1] if ($type < 0);
	return $tiles[$type];
}

sub scale2x() {
	my ($w,$h,@map) = @_;
	my @newmap;
	foreach my $x (0 .. $w-1) {
		foreach my $y (0 .. $h-1) {
			my $p = $map[$x][$y];
			$newmap[$x*2][$y*2] = $p;
			if (defined($map[$x+1][$y])) { $newmap[$x*2+1][$y*2] = $p+($map[$x+1][$y]-$p)/2; }
			else { $newmap[$x*2+1][$y*2] = $p; }
			if (defined($map[$x][$y+1])) { $newmap[$x*2][$y*2+1] = $p+($map[$x][$y+1]-$p)/2; }
			else { $newmap[$x*2][$y*2+1] = $p; }
			if (defined($map[$x+1][$y+1])) { $newmap[$x*2+1][$y*2+1] = $p+($map[$x+1][$y+1]-$p)/2; }
			else { $newmap[$x*2+1][$y*2+1] = $p; }
		}
	}
	return \@newmap;
}

sub simple2x() {
	my ($w,$h,@map) = @_;
	my @newmap;
	foreach my $x (0 .. $w-1) {
		foreach my $y (0 .. $h-1) {
			my $p = $map[$x][$y];
			$newmap[$x*2][$y*2] = $p;
			$newmap[$x*2+1][$y*2] = $p;
			$newmap[$x*2][$y*2+1] = $p;
			$newmap[$x*2+1][$y*2+1] = $p;
		}
	}
	return \@newmap;
}

sub spread_plant() {
	my ($x,$y,$z,$type) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};

	# Reasons to not appear
	return if (rand(1) < 0.1); # Random death
	return unless (&map_getblock($x,$y,$z) == 0);
	return unless (&map_getblock($x,$y-1,$z) == 2);

	# Change type
	if ($type == 37 || $type == 38) { $type = floor(37+rand(2)); } # Flowers
	elsif ($type == 39 || $type == 40) { $type = floor(39+rand(2)); } # Mushrooms

	# Create self
	&map_setblock($x,$y,$z,$type);

	# Recurse more plants
	foreach (0..1) {
		my $spread = floor(rand(8));
		&spread_plant(($x+1),$y,$z,$type) if ($spread == 0);
		&spread_plant(($x+1),($y+1),$z,$type) if ($spread == 0);
		&spread_plant(($x+1),($y-1),$z,$type) if ($spread == 0);
		&spread_plant(($x-1),$y,$z,$type) if ($spread == 1);
		&spread_plant(($x-1),($y+1),$z,$type) if ($spread == 1);
		&spread_plant(($x-1),($y-1),$z,$type) if ($spread == 1);
		&spread_plant($x,$y,($z+1),$type) if ($spread == 2);
		&spread_plant($x,($y+1),($z+1),$type) if ($spread == 2);
		&spread_plant($x,($y-1),($z+1),$type) if ($spread == 2);
		&spread_plant($x,$y,($z-1),$type) if ($spread == 3);
		&spread_plant($x,($y+1),($z-1),$type) if ($spread == 3);
		&spread_plant($x,($y-1),($z-1),$type) if ($spread == 3);
		&spread_plant(($x+1),$y,($z+1),$type) if ($spread == 4);
		&spread_plant(($x-1),$y,($z-1),$type) if ($spread == 5);
		&spread_plant(($x-1),$y,($z+1),$type) if ($spread == 6);
		&spread_plant(($x+1),$y,($z-1),$type) if ($spread == 7);
	}

	# TODO: Ensure lone plants do not survive.
}

sub spread_air() {
	my ($x,$y,$z,$type,$life) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};

	# Reasons to not appear
	$life -= 1;
	return if ($life <= 0);
	return unless (&map_getblock($x,$y,$z) == 1 || &map_getblock($x,$y,$z) == 0);

	&map_setblock($x,$y,$z,$type);

	# Recurse more
	&spread_air(($x+1),$y,$z,$type,$life);
	&spread_air(($x-1),$y,$z,$type,$life);
	&spread_air($x,$y,($z+1),$type,$life);
	&spread_air($x,$y,($z-1),$type,$life);
	&spread_air($x,($y+1),$z,$type,$life);
	&spread_air($x,($y-1),$z,$type,$life);
}

sub spread_mineral() {
	my ($x,$y,$z,$type,$life) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};

	# Reasons to not appear
	$life -= (floor(rand(3))+1);
	return if ($life <= 0);
	return unless (&map_getblock($x,$y,$z) == 1);

	&map_setblock($x,$y,$z,$type);

	# Recurse more
	&spread_mineral(($x+1),$y,$z,$type,$life);
	&spread_mineral(($x-1),$y,$z,$type,$life);
	&spread_mineral($x,($y+1),$z,$type,$life);
	&spread_mineral($x,($y-1),$z,$type,$life);
	&spread_mineral($x,$y,($z+1),$type,$life);
	&spread_mineral($x,$y,($z-1),$type,$life);
}

sub spread_fluid() {
	my ($x,$y,$z,$type) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};

	# Reasons to not appear
	return unless (&map_getblock($x,$y,$z) == 0);

	&map_setblock($x,$y,$z,$type);

	# Recurse more
	&spread_fluid($x,($y-1),$z,$type) if (&map_getblock($x,$y-1,$z) == 0);
	&spread_fluid(($x+1),$y,$z,$type) if (&map_getblock($x+1,$y,$z) == 0);
	&spread_fluid(($x-1),$y,$z,$type) if (&map_getblock($x-1,$y,$z) == 0);
	&spread_fluid($x,$y,($z+1),$type) if (&map_getblock($x,$y,$z+1) == 0);
	&spread_fluid($x,$y,($z-1),$type) if (&map_getblock($x,$y,$z-1) == 0);
}

sub map_generate() {
	my ($w,$d,$h) = @_;
	print "Generating map...\n";
	my $start_time = time();
	$server{'map'} = {
		size => [$w,$d,$h],
		spawn => [floor($w/2),floor($d/2)+2,floor($h/2),1,1]
	};
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	my $layer = $size_x * $size_z;
	my @blocks;
	print "Raising...\n";

	# Start with a small COMPLETELY random noise heightmap
	# restricted to 1/4th of the map's height up or down
	# and 1/4th of the resolution.
	my @heightmap;
	foreach my $z (0 .. floor($size_z/16)) {
		foreach my $x (0 ..floor($size_x/16)) {
			my $y = rand($size_y/8);
			$y = -$y if (rand(1) < 0.5);
			$y += $size_y/2;
			$heightmap[$z][$x] = $y;
		}
		select(undef, undef, undef, 0.01);
	}
	#foreach my $z (0 .. floor($size_z/16)-1) {
	#	foreach my $x (0 .. floor($size_x/16)-1) {
	#		my $y = $heightmap[$z][$x];
	#		$y = $y + ($heightmap[$z-1][$x]-$y)/2 if ($z > 0);
	#		$y = $y + ($heightmap[$z+1][$x]-$y)/2 if ($z < floor($size_z/16)-1);
	#		$y = $y + ($heightmap[$z][$x-1]-$y)/2 if ($x > 0);
	#		$y = $y + ($heightmap[$z][$x+1]-$y)/2 if ($x < floor($size_x/16)-1);
	#		$heightmap[$z][$x] = $y;
	#	}
	#}
	# Now smooth scale it up to par. ;o
	@heightmap = @{&scale2x(floor($size_z/16),floor($size_x/16),@heightmap)}; # 16->8
	select(undef, undef, undef, 0.01);
	@heightmap = @{&scale2x(floor($size_z/8),floor($size_x/8),@heightmap)}; # 8->4
	select(undef, undef, undef, 0.01);
	@heightmap = @{&simple2x(floor($size_z/4),floor($size_x/4),@heightmap)}; # 4->2
	select(undef, undef, undef, 0.01);
	@heightmap = @{&simple2x(floor($size_z/2),floor($size_x/2),@heightmap)}; # 2->1
	select(undef, undef, undef, 0.01);

	print "Smoothing...\n";
	# Smooth the heightmap out a few times
	foreach (0 .. 1) {
		foreach my $z (0 .. $size_z-1) {
			foreach my $x (0 .. $size_x-1) {
				my $y = $heightmap[$z][$x];
				$y = $y + ($heightmap[$z-1][$x]-$y)/2 if ($z > 0);
				$y = $y + ($heightmap[$z+1][$x]-$y)/2 if ($z < $size_z-1);
				$y = $y + ($heightmap[$z][$x-1]-$y)/2 if ($x > 0);
				$y = $y + ($heightmap[$z][$x+1]-$y)/2 if ($x < $size_x-1);
				$heightmap[$z][$x] = $y;
			}
			select(undef, undef, undef, 0.01);
		}
	}

	print "Translating heightmap...\n";
	# This turns the heightmap 3D.
	foreach my $z (0 .. $size_z-1) {
		foreach my $x (0 .. $size_x-1) {
			my $type = 1;
			my $off = $z * $size_x + $x;
			my $height = floor($heightmap[$z][$x]);
			foreach my $y (0 .. $size_y-1) {
				$type = 0 if ($height == $y);
				$type = 9 if ($type == 0 && $y < floor($size_y/2));
				$type = 0 if ($type == 9 && $y >= floor($size_y/2));
				$blocks[$y * $layer + $off] = $type;
			}
		}
		select(undef, undef, undef, 0.01);
	}

	print "Planting grass...\n";
	foreach my $x (0 .. $size_x-1) {
		foreach my $z (0 .. $size_z-1) {
			my $off = $z * $size_x + $x;
			my $y = floor($heightmap[$z][$x]);
			my $light = ($y >= floor($size_y/2));
			my $type = 12;
			if ($light && $y >= floor($size_y/2)) { $type = 2; }
			elsif ($y < floor($size_y/2)-1) { $type = 13; }
			$blocks[$y-- * $layer + $off] = $type;
			$type = 3 if ($type == 2);
			$blocks[$y-- * $layer + $off] = $type;
			$blocks[$y-- * $layer + $off] = 3;
			$blocks[$y * $layer + $off] = 3;
		}
		select(undef, undef, undef, 0.01);
	}

	print "Adding adminium edging...\n";
	foreach (0 .. $layer-1) {
		$blocks[$_] = 7;
	}
	for (my $x = 0; $x < $size_x; $x++) {
		for (my $y = 1; $y < floor($size_y/2)-2; $y++) {
			$blocks[$y * $layer + $x] = 7;
			$blocks[$y * $layer + ($size_z-1) * $size_x + $x] = 7;
		}
		select(undef, undef, undef, 0.01);
	}
	for (my $z = 1; $z < $size_z-1; $z++) {
		for (my $y = 1; $y < floor($size_y/2)-2; $y++) {
			$blocks[$y * $layer + $z * $size_x] = 7;
			$blocks[$y * $layer + $z * $size_x + $size_x-1] = 7;
		}
		select(undef, undef, undef, 0.01);
	}

	$server{'map'}{'blocks'} = \@blocks;
	$server{'map'}{'specials'} = {};

	print "Digging caves...\n";
	my @caves;
	foreach (0 .. floor($size_x*($size_y/2)*$size_z)/4096) {
		my $x = floor(rand($size_x-8)+4);
		my $z = floor(rand($size_z-8)+4);
		my $y = floor(rand(floor($heightmap[$z][$x])-10))+4;
		my $exists = 0;
		my ($sx,$sy,$sz) = ($x,$y,$z);
		foreach (0 .. 30+floor(rand(30))) {
			my $r = floor(rand(6));
			my ($last_x,$last_y,$last_z);
			#foreach (0 .. 1+floor(rand(2))) {
				my $size = 2+floor(rand(4));
				if ($x < $size) { $x = $size; }
				if ($x > $size_x-$size-1) { $x = $size_x-$size-1; }
				if ($y < $size) { $y = $size; }
				if ($y > $size_y-$size-1) { $y = $size_y-$size-1; }
				if ($z < $size) { $z = $size; }
				if ($z > $size_z-$size-1) { $z = $size_z-$size-1; }
				last if (defined($last_x) && $last_x == $x && $last_y == $y && $last_z == $z);
				&spread_air($x,$y,$z,0,$size);
				$exists = 1;
				($last_x,$last_y,$last_z) = ($x,$y,$z);
				if ($r == 0) { $x++; }
				elsif ($r == 1) { $x--; }
				elsif ($r == 2) { $z++; }
				elsif ($r == 3) { $z--; }
				elsif ($r == 4) { $y++; }
				elsif ($r == 5) { $y--; }
			#}
		}
		select(undef, undef, undef, 0.01);
		if ($exists) { push @caves,[$sx,$sy,$sz]; }
	}
	print int(@caves)." caves were generated.\n";

	print "Pumping lava...\n";
	foreach (@caves) {
		if (rand(1) < 0.35) {
			my @pos = @{$_};
			my $off = $pos[2] * $size_x + $pos[0];
			while ($blocks[$pos[1] * $layer + $off] == 0) { $pos[1]--; }
			$pos[1]++;
			#if (rand(1) < 0.5) { &spread_fluid(@pos,8); }
			#else { &spread_fluid(@pos,11); }
			$blocks[$pos[1] * $layer + $off] = 10;
			$server{'map'}{'block_thinkers'}{10}{"@pos"} = 1;
		}
		select(undef, undef, undef, 0.01);
	}

	#print "Embedding minerals...\n";
	#foreach (0 .. ($size_x*$size_z)/128) {
	#	my $x = floor(rand($size_x));
	#	my $z = floor(rand($size_z));
	#	my $y = floor(rand(floor($heightmap[$z][$x])-5))+1;
	#	&spread_mineral($x,$y,$z,14+floor(rand(3)),16);
	#}

	print "Planting trees...\n";
	foreach (0 .. ($size_x*$size_z)/512) {
		my $tries = 0;
		foreach (0 .. 100) {
			$tries = $_;
			my $x = floor(rand($size_x));
			my $z = floor(rand($size_z));
			my $y = floor($heightmap[$z][$x]);
			if ($blocks[$y * $layer + $z * $size_x + $x] == 2
			&& $blocks[$y * $layer + $z * $size_x + ($x+1)] == 2
			&& $blocks[$y * $layer + $z * $size_x + ($x-1)] == 2
			&& $blocks[$y * $layer + ($z+1) * $size_x + $x] == 2
			&& $blocks[$y * $layer + ($z-1) * $size_x + $x] == 2
			&& $blocks[$y * $layer + ($z+1) * $size_x + ($x+1)] == 2
			&& $blocks[$y * $layer + ($z-1) * $size_x + ($x+1)] == 2
			&& $blocks[$y * $layer + ($z+1) * $size_x + ($x-1)] == 2
			&& $blocks[$y * $layer + ($z-1) * $size_x + ($x-1)] == 2) {
				&map_buildtree($x,$y+1,$z);
				$blocks[$y * $layer + $z * $size_x + $x] = 3;
				last;
			}
		}
		last if ($tries == 100);
		select(undef, undef, undef, 0.01);
	}

	print "Planting flowers, mushrooms, and bushes...\n";
	foreach (0 .. ($size_x*$size_z)/256) {
		my $tries = 0;
		foreach (0 .. 100) {
			$tries = $_;
			my $x = floor(rand($size_x));
			my $z = floor(rand($size_z));
			my $y = floor($heightmap[$z][$x]);
			my $type = floor(rand(5));
			if ($type == 0) { $type = 6; }
			else { $type = 36+$type; }
			if ($blocks[$y * $layer + $z * $size_x + $x] == 2
			&& $blocks[($y+1) * $layer + $z * $size_x + $x] == 0) {
				&spread_plant($x,$y+1,$z,$type);
				last;
			}
		}
		last if ($tries == 100);
		select(undef, undef, undef, 0.01);
	}

	print "Relocating spawn point...\n";
	my $off = floor($size_z/2) * $size_x + floor($size_x/2);
	for (my $y = floor($size_y/2); $y < $size_y; $y++) {
		next if (&get_tileinfo($blocks[$y * $layer + $off])->{'solid'});
		next if (&get_tileinfo($blocks[($y+1) * $layer + $off])->{'solid'});
		$server{'map'}{'spawn'}[1] = $y+1;
		last;
	}

	printf("Complete. Operations took %.3f seconds.\n",time()-$start_time);
	&global_mapchange();
}

sub map_new() {
	my ($type,$w,$d,$h) = @_;
	my $typename;
	if ($type == 0) { $typename = 'empty'; }
	elsif ($type == 1) { $typename = 'flatgrass'; }
	elsif ($type == 2) { $typename = 'ocean'; }
	print "Generating new $typename $w".'x'."$d".'x'."$h map...\n";
	my $start_time = time();
	my $layer = $w * $h;
	$server{'map'} = {
		size => [$w,$d,$h],
		spawn => [floor($w/2),floor($d/2)+3,floor($h/2),1,1],
	};

	if ($type == 0) {
		$server{'map'}{'blocks'} = [
			(7) x ($layer * 1), # Bedrock
			(0) x ($layer * ($d-1)) # Air, and lots of it.
		];
	}
	elsif ($type == 1) {
		$server{'map'}{'blocks'} = [
			(7) x ($layer * 1), # Bedrock
			(1) x ($layer * (floor($d/2)-4)), # Underground rock
			(3) x ($layer * 4), # 3 layers of dirt
			(2) x ($layer * 1), # A layer of grass
			(0) x ($layer * (ceil($d/2)-1)) # Upper half air
		];
	}
	elsif ($type == 2) {
		$server{'map'}{'blocks'} = [
			(7) x ($layer * 1), # Bedrock
			(9) x ($layer * (floor($d/2)-1)), # Lower half water
			(0) x ($layer * ceil($d/2)) # Upper half air
		];
	}

	print "Adding adminium edging...\n";
	my $blocks = $server{'map'}{'blocks'};
	for (my $x = 0; $x < $w; $x++) {
		for (my $y = 1; $y < floor($d/2); $y++) {
			$blocks->[$y * $layer + $x] = 7;
			$blocks->[$y * $layer + ($h-1) * $w + $x] = 7;
		}
	}
	for (my $z = 1; $z < $h-1; $z++) {
		for (my $y = 1; $y < floor($d/2); $y++) {
			$blocks->[$y * $layer + $z * $w] = 7;
			$blocks->[$y * $layer + $z * $w + $w-1] = 7;
		}
	}

	printf("Complete. Operations took %.3f seconds.\n",time()-$start_time);

	&global_mapchange();
}

sub map_clearblock() {
	my ($x,$y,$z) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	my $type = 0;
	$type = 8 if (($x == 0 || $x == $size_x-1 || $z == 0 || $z == $size_z-1) && $y < floor($size_y/2) && $y >= floor($size_y/2)-2);
	&map_setblock($x,$y,$z,$type);
}

sub map_setblock() {
	my ($x,$y,$z,$type,$dense) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	return if ($x < 0 || $x >= $size_x || $y < 0 || $y >= $size_y || $z < 0 || $z >= $size_z);
	my $old_type = &map_getblock($x,$y,$z);
	return if ($old_type == $type);

	# Water can't go in range of sponge
	# (Dirty hack, add a callback for block spawns later)
	if ($type == 8 || $type == 9) {
		foreach my $sx (-2 .. 2) {
			foreach my $sy (-2 .. 2) {
				foreach my $sz (-2 .. 2) {
					return if (&map_getblock($x+$sx,$y+$sy,$z+$sz) == 19);
				}
			}
		}
		foreach my $sx (-4 .. 4) {
			foreach my $sy (-4 .. 4) {
				foreach my $sz (-4 .. 4) {
					return if (&map_getblock($x+$sx,$y+$sy,$z+$sz) == -3);
				}
			}
		}
	}

	# Lava can't go in range of lava sponge
	# (Dirty hack, add a callback for block spawns later)
	if ($type == 10 || $type == 11) {
		foreach my $sx (-2 .. 2) {
			foreach my $sy (-2 .. 2) {
				foreach my $sz (-2 .. 2) {
					return if (&map_getblock($x+$sx,$y+$sy,$z+$sz) == -1);
				}
			}
		}
		foreach my $sx (-4 .. 4) {
			foreach my $sy (-4 .. 4) {
				foreach my $sz (-4 .. 4) {
					return if (&map_getblock($x+$sx,$y+$sy,$z+$sz) == -3);
				}
			}
		}
	}

	# Change active thinkers
	delete $server{'map'}{'block_thinkers'}{$old_type}{"$x $y $z"};
	if (&get_tileinfo($type)->{'on_think'}) { $server{'map'}{'block_thinkers'}{$type}{"$x $y $z"} = -1; }

	# Change block
	my $display = $type;
	$display = &get_tileinfo($type)->{'display'} if (&get_tileinfo($type)->{'display'});
	$server{'map'}{'blocks'}[($y * $size_z + $z) * $size_x + $x] = $display;
	&global_blockchange($x,$y,$z,$display);
	undef $display if ($display == $type);

	if (defined($display)) { $server{'map'}{'specials'}{"$x $y $z"} = $type; }
	else { delete $server{'map'}{'specials'}{"$x $y $z"}; }

	if ($dense) { $server{'map'}{'dense'}{"$x $y $z"} = 1; }
	else { delete $server{'map'}{'dense'}{"$x $y $z"}; }

	# Trigger build events
	my $func = &get_tileinfo($type)->{'on_build'};
	&{$func}($x,$y,$z,$type) if (defined($func));

	# Trigger break events
	if (!&get_tileinfo($type)->{'solid'} && !&get_tileinfo($type)->{'liquid'}) {
		my $func = &get_tileinfo($old_type)->{'on_break'};
		&{$func}($x,$y,$z,$old_type) if (defined($func));
		&trigger_breaktouch($x+1,$y,$z);
		&trigger_breaktouch($x-1,$y,$z);
		&trigger_breaktouch($x,$y+1,$z);
		&trigger_breaktouch($x,$y-1,$z);
		&trigger_breaktouch($x,$y,$z+1);
		&trigger_breaktouch($x,$y,$z-1);
	}
}

sub map_getblock() {
	my ($x,$y,$z) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	return 0 if ($x < 0 || $x >= $size_x || $y < 0 || $y >= $size_y || $z < 0 || $z >= $size_z);
	my $special = $server{'map'}{'specials'}{"$x $y $z"};
	return $special if (defined($special));
	return $server{'map'}{'blocks'}[($y * $size_z + $z) * $size_x + $x];
}

my @tree = (
	[ 0,0, 0,17],
	[ 0,1, 0,17],
	[ 0,2, 0,17],
	[ 0,3, 0,17],
	[ 1,3, 0,18],
	[-1,3, 0,18],
	[ 0,3, 1,18],
	[ 0,3,-1,18],
	[ 1,3, 1,18],
	[-1,3, 1,18],
	[ 1,3,-1,18],
	[-1,3,-1,18],
	[ 0,4, 0,17],
	[ 1,4, 0,18],
	[-1,4, 0,18],
	[ 0,4, 1,18],
	[ 0,4,-1,18],
	[ 1,4, 1,18],
	[-1,4, 1,18],
	[ 1,4,-1,18],
	[-1,4,-1,18],
	[ 2,4, 0,18],
	[-2,4, 0,18],
	[ 0,4, 2,18],
	[ 0,4,-2,18],
	[ 2,4, 1,18],
	[ 2,4,-1,18],
	[-2,4, 1,18],
	[-2,4,-1,18],
	[ 1,4, 2,18],
	[-1,4, 2,18],
	[ 1,4,-2,18],
	[-1,4,-2,18],
	[ 0,5, 0,17],
	[ 1,5, 0,18],
	[-1,5, 0,18],
	[ 0,5, 1,18],
	[ 0,5,-1,18],
	[ 1,5, 1,18],
	[ 1,5,-1,18],
	[-1,5, 1,18],
	[-1,5,-1,18],
	[ 2,5, 0,18],
	[-2,5, 0,18],
	[ 0,5, 2,18],
	[ 0,5,-2,18],
	[ 0,6, 0,18],
	[ 1,6, 0,18],
	[-1,6, 0,18],
	[ 0,6, 1,18],
	[ 0,6,-1,18]
);

sub map_buildtree() {
	my ($x,$y,$z) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	foreach (@tree) {
		my @pos = ($x+$_->[0],$y+$_->[1],$z+$_->[2]);
		next if ($pos[0] < 0 || $pos[1] < 0 || $pos[2] < 0);
		next if ($pos[0] >= $size_x || $pos[1] >= $size_y || $pos[2] >= $size_z);
		&map_setblock(@pos,$_->[3]) if (&map_getblock(@pos) == 0);
	}
}

sub map_think() {
	foreach my $type (keys %{$server{'map'}{'block_thinkers'}}) {
		next unless $type;
		next unless &get_tileinfo($type)->{'think_time'};
		if (time() >= (&get_tileinfo($type)->{'last_think'}||0)+&get_tileinfo($type)->{'think_time'}) {
			my $think_count = 0;
			my $blocks = $server{'map'}{'block_thinkers'}{$type};
			foreach (keys %{$blocks}) {
				next unless (defined($_) && $blocks->{$_});
				my @pos = split / /,$_;
				next if ($blocks->{$_} == -1);
				&{&get_tileinfo($type)->{'on_think'}}(@pos,$type);
				$think_count++;
				#select(undef,undef,undef,0.01);
				last if ($think_count > 20); # Grey goo fence
			}
			foreach (keys %{$blocks}) {
				$blocks->{$_} = 1 if (defined($blocks->{$_}) && $blocks->{$_} == -1);
			}
			&get_tileinfo($type)->{'last_think'} = time();
		}
	}
}

sub map_save() {
	my $backup = shift;
	$server{'save_time'} = floor(time);

	my $empty = 1;
	foreach (@{$server{'users'}}) {
		next unless defined($_) && $_->{'active'};
		$empty = 0;
		last;
	}
	return if ($empty && !$backup);

	my $size = $server{'map'}{'size'}[0]*$server{'map'}{'size'}[1]*$server{'map'}{'size'}[2];
	my @blocks = @{$server{'map'}{'blocks'}};
	my @dense;
	foreach (keys %{$server{'map'}{'dense'}}) {
		/(\d+) (\d+) (\d+)/;
		push @dense,$1;
		push @dense,$2;
		push @dense,$3;
	}
	#print "@dense\n";
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	foreach (keys %{$server{'map'}{'specials'}}) {
		/(\d+) (\d+) (\d+)/;
		$blocks[($2 * $size_z + $3) * $size_x + $1] = $server{'map'}{'specials'}{$_};
	}
	my $data = pack("cn3c2n3c$size"."n*",2,@{$server{'map'}{'spawn'}},@{$server{'map'}{'size'}},@blocks,@dense);
	my $buffer;
	gzip \$data => \$buffer;
	if (open(FILE,">maps/$server{'map_name'}.gz")) {
		binmode FILE;
		print FILE $buffer;
		close FILE;
		print "Level saved as maps/$server{'map_name'}.gz\n";
	}

	my $time = '';
	if ($backup || $server{'save_time'} >= $server{'backup_time'}+(60*$server{'config'}{'backup_time'})) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($server{'save_time'});
		$time = sprintf("%02d-%03d[%02d%02d]",($year%100),$yday,$hour,$min);
		if (open(FILE,">maps/backup/$server{'map_name'}/$time.gz")) {
			binmode FILE;
			print FILE $buffer;
			close FILE;
			&global_msg("Map backup created: &f$server{'map_name'}/$time");
		}
		else { $time = ''; }
		$server{'backup_time'} = $server{'save_time'};
	}
}

sub map_find() {
	if (open FILE,'<',"@_") {
		close FILE;
		return 1;
	}
	return 0;
}

sub map_load() {
	my ($file) = "@_";
	my $data;
	print "Decompressing map '$file'...\n";
	gunzip $file => \$data;
	return 0 unless $data;
	print "Loading map data...\n";
	my ($version,$spawn_x,$spawn_y,$spawn_z,$spawn_rx,$spawn_ry,$size_x,$size_y,$size_z,@blocks,%dense);
	%dense = ();
	($version,$data) = unpack("ca*",$data);
	print "Map format version $version.\n";
	if ($version == 1) {
		($spawn_x,$spawn_y,$spawn_z,$spawn_rx,$spawn_ry,$size_x,$size_y,$size_z,$data) = unpack("n3c2n3a*",$data);
		#print "Map spawn: $spawn_x,$spawn_y,$spawn_z\n";
		print "Map size: $size_x,$size_y,$size_z\n";
		my $size = $size_x*$size_y*$size_z;
		print "Loading $size blocks...\n";
		@blocks = unpack("c$size",$data);
	}
	elsif ($version == 2) {
		($spawn_x,$spawn_y,$spawn_z,$spawn_rx,$spawn_ry,$size_x,$size_y,$size_z,$data) = unpack("n3c2n3a*",$data);
		#print "Map spawn: $spawn_x,$spawn_y,$spawn_z\n";
		print "Map size: $size_x,$size_y,$size_z\n";
		my $size = $size_x*$size_y*$size_z;
		print "Loading $size blocks...\n";
		@blocks = unpack("c$size",$data);
		$data = substr($data,$size);
		my @dlist = unpack("n*",$data);
		print "There are ".floor(int(@dlist)/3)." dense blocks in the map.\n";
		foreach (0 .. floor(int(@dlist)/3)-1) {
			my $i = $_*3;
			next unless (defined($dlist[$i]) && defined($dlist[$i+1]) && defined($dlist[$i+2]));
			$dense{$dlist[$i].' '.$dlist[$i+1].' '.$dlist[$i+2]} = 1;
		}
	}
	else {
		print "Map version number $version is unsupported!\n";
		return 0;
	}
	$server{'map'}{'spawn'} = [$spawn_x,$spawn_y,$spawn_z,$spawn_rx,$spawn_ry];
	$server{'map'}{'size'} = [$size_x,$size_y,$size_z];
	$server{'map'}{'blocks'} = \@blocks;
	$server{'map'}{'block_thinkers'} = {};
	$server{'map'}{'specials'} = {};
	$server{'map'}{'dense'} = \%dense;
	print "Finding special block types and setting thinkers...\n";
	my $specials = 0;
	my $thinkers = 0;
	foreach my $x (0 .. $size_x-1) {
		foreach my $y (0 .. $size_y-1) {
			foreach my $z (0 .. $size_z-1) {
				$_ = ($y * $size_z + $z) * $size_x + $x;
				my $info = &get_tileinfo($blocks[$_]);
				if ($info->{'display'}) {
					$server{'map'}{'specials'}{"$x $y $z"} = $blocks[$_];
					$blocks[$_] = $info->{'display'};
					$specials++;
				}
				next unless ($info->{'on_think'});
				$server{'map'}{'block_thinkers'}{$blocks[$_]}{"$x $y $z"} = 1;
				$thinkers++;
			}
		}
		#select(undef,undef,undef,0.02);
	}
	print "Found $specials special blocks types.\n";
	print "Found $thinkers block thinkers.\n";
	print "Map load complete.\n";
	return 1;
}

sub trigger_breaktouch() {
	my ($x,$y,$z) = @_;
	my ($size_x,$size_y,$size_z) = @{$server{'map'}{'size'}};
	my $type = &map_getblock($x,$y,$z);
	my $func = &get_tileinfo($type)->{'on_breaktouch'};
	&{$func}($x,$y,$z,$type) if (defined($func));
}

my @water_spread = (
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 0, 1],
	[ 0, 0,-1]
);

sub water_think() {
	my ($x,$y,$z,$type) = @_;
	# Determine antitypes
	my $antitype = 0;
	if ($type == 8 || $type == 9) { $antitype = 10; }
	elsif ($type == 10 || $type == 11) { $antitype = 8; }

	# Try to go down first.
	my $found = 0;
	for (my $oy = $y-1; $oy > 0; $oy--) {
		foreach my $sx (-2..2) {
			foreach my $sy (-2..2) {
				foreach my $sz (-2..2) {
					last if (&map_getblock($x+$sx,$oy+$sy,$z+$sz) == 19);
				}
			}
		}
		foreach my $sx (-4..4) {
			foreach my $sy (-4..4) {
				foreach my $sz (-4..4) {
					last if (&map_getblock($x+$sx,$oy+$sy,$z+$sz) == -3);
				}
			}
		}

		my @pos = ($x,$oy,$z);
		my $this = &map_getblock(@pos);
		next if ($this == $type || $this == $type+1);
		if ($this == $antitype || $this == $antitype+1) { &map_setblock(@pos,1); } # Turn to stone
		elsif (!&get_tileinfo($this)->{'solid'} && !&get_tileinfo($this)->{'liquid'}) {
			&map_setblock(@pos,$type);
			$found = 1;
		}
		else { last; }
	}
	#return if ($found); # If you moved downwards, don't move outwards this tick.

	foreach (@water_spread) {
		my @pos = ($x+$_->[0],$y+$_->[1],$z+$_->[2]);
		my $this = &map_getblock(@pos);
		if ($this == $antitype || $this == $antitype+1) { &map_setblock(@pos,1); } # Turn to stone
		elsif (!&get_tileinfo($this)->{'solid'} && !&get_tileinfo($this)->{'liquid'}) { &map_setblock(@pos,$type); }
	}
	&map_setblock($x,$y,$z,$type+1); # Become inactive
}

my @lava_spread = (
	[ 0,-1, 0],
	[ 1, 0, 0],
	[-1, 0, 0],
	[ 0, 0, 1],
	[ 0, 0,-1]
);

sub lava_think() {
	my ($x,$y,$z,$type) = @_;
	# Determine antitypes
	my $antitype = 0;
	if ($type == 8 || $type == 9) { $antitype = 10; }
	elsif ($type == 10 || $type == 11) { $antitype = 8; }

	foreach (@lava_spread) {
		my @pos = ($x+$_->[0],$y+$_->[1],$z+$_->[2]);
		my $this = &map_getblock(@pos);
		if ($this == $antitype || $this == $antitype+1) { &map_setblock(@pos,1); } # Turn to stone
		elsif (!&get_tileinfo($this)->{'solid'} && !&get_tileinfo($this)->{'liquid'}) { &map_setblock(@pos,$type); }
	}
	&map_setblock($x,$y,$z,$type+1); # Become inactive
}

sub still_liquid_think() {
	my ($x,$y,$z,$type) = @_;
	&map_setblock($x,$y,$z,$type-1); # Become active
}

sub sand_think() {
	my ($x,$y,$z,$type) = @_;
	my $old_y = $y;
	my $under_type = &map_getblock($x,$y-1,$z);
	return if (&get_tileinfo($under_type)->{'solid'});
	until (&get_tileinfo(&map_getblock($x,$y-1,$z))->{'solid'}) { $y--; }
	&map_setblock($x,$y,$z,$type);
	&map_setblock($x,$old_y,$z,0);
}

sub sponge_build() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-2..2) {
		foreach my $sy (-2..2) {
			foreach my $sz (-2..2) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,0) if ($type == 8 || $type == 9);
			}
		}
	}
}

sub sponge_break() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-3..3) {
		foreach my $sy (-3..3) {
			foreach my $sz (-3..3) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,8) if ($type == 9);
			}
		}
	}
}

sub lavasponge_build() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-2..2) {
		foreach my $sy (-2..2) {
			foreach my $sz (-2..2) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,0) if ($type == 10 || $type == 11);
			}
		}
	}
}

sub lavasponge_break() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-3..3) {
		foreach my $sy (-3..3) {
			foreach my $sz (-3..3) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,10) if ($type == 11);
			}
		}
	}
}

sub supersponge_build() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-4..4) {
		foreach my $sy (-4..4) {
			foreach my $sz (-4..4) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,0) if ($type >= 8 && $type <= 11);
			}
		}
	}
}

sub supersponge_break() {
	my ($x,$y,$z,$type) = @_;
	foreach my $sx (-5..5) {
		foreach my $sy (-5..5) {
			foreach my $sz (-5..5) {
				my $type = &map_getblock($x+$sx,$y+$sy,$z+$sz);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,8) if ($type == 9);
				&map_setblock($x+$sx,$y+$sy,$z+$sz,10) if ($type == 11);
			}
		}
	}
}

sub plant_think() {
	my ($x,$y,$z,$type) = @_;
	my $size_y = $server{'map'}{'size'}[1];
	for (my $cy = $y+1; $cy < $size_y; $cy++) {
		next if (&get_tileinfo(&map_getblock($x,$cy,$z))->{'light'});
		&map_setblock($x,$y,$z,0) if (rand(1) < 0.2); # No light? No plant. :(
		return;
	}
	my $soil = &map_getblock($x,$y-1,$z);
	&map_setblock($x,$y,$z,0) if ($soil != 2 && $soil != 3); # No soil? No plant!
}

sub shroom_think() {
	my ($x,$y,$z,$type) = @_;
	my $soil = &map_getblock($x,$y-1,$z);
	&map_setblock($x,$y,$z,0) if ($soil != 2 && $soil != 3); # No soil? No plant!
}

sub dynamite_think() {
	my ($x,$y,$z,$type) = @_;
	&map_setblock($x,$y,$z,0);
	foreach my $sx (-2..2) {
		foreach my $sy (-2..2) {
			foreach my $sz (-2..2) {
				my ($px,$py,$pz) = ($x+$sx,$y+$sy,$z+$sz);
				$type = &map_getblock($px,$py,$pz);
				next if ($type == 7);
				next if ($server{'map'}{'dense'}{"$px $py $pz"});
				my $info = &get_tileinfo($type);
				next unless ($info->{'solid'} || $info->{'liquid'});
				&map_setblock($px,$py,$pz,0);
			}
		}
	}
}

sub soccer_think() {
	my ($x,$y,$z,$type) = @_;
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && $_->{'active'} && $_->{'pos'});
		next unless (abs($x - floor($_->{'pos'}[0]/32)) < 2 && abs($y - floor($_->{'pos'}[1]/32)) < 2 && abs($z - floor($_->{'pos'}[2]/32)) < 2);
	}
}

sub soccer_break() {
}

1;
