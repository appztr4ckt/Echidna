#!/usr/bin/perl
use warnings;
use strict;

# This program was originally written by The Echidna Tribe (JTE@KidRadd.org)

our (%server);

$server{'commands'} = {
	HELP => [\&cmd_help,0],
	SHOWSELF => [\&cmd_showself,0], # Shows your own character, for debugging player movement.
	COLORS => [\&cmd_color,0,'Shows color codes.'],
	COLOR => [\&cmd_color,0],
	ME => [\&cmd_me,0,'Roleplaying action message.'],
	SAY => [\&cmd_say,50,'Send a global message.'],
	BUILD => [\&cmd_build,0,'Build special block types.'],
	SOLID => [\&cmd_solid,20], # Alias for '/build solid', analogous to the official server command.
	ADMINBREAK => [\&cmd_adminbreak,20,'Toggles if you can break the unbreakable.'],
	HIDE => [\&cmd_hide,100,'Become invisible to everyone else.'],
	NICK => [\&cmd_nick,200,'Change your visible name and skin on this server.'],
	ONICK => [\&cmd_onick,200,'Change someone else\'s visible name and skin.'],
	OP => [\&cmd_op,100,'Grant a user admin status.'],
	DEOP => [\&cmd_deop,100,'Revoke admin status.'],
	KICK => [\&cmd_kick,50,'Disconnect a user with the given message.'],
	K => [\&cmd_kick,50],
	BAN => [\&cmd_ban,50,'Ban a user by name.'],
	BANIP => [\&cmd_banip,50,'Ban a user by IP.'],
	UNBAN => [\&cmd_unban,100,'Unban a user.'],
	TP => [\&cmd_teleport,20,'Teleport to a player.'],
	TELEPORT => [\&cmd_teleport,20],
	GOTO => [\&cmd_teleport,20],
	SETSPAWN => [\&cmd_setspawn,100,'Set the map\'s default spawn point.'],
	FETCH => [\&cmd_fetch,50,'Teleport another player to you.'],
	RECALL => [\&cmd_fetch,50],
	TREE => [\&cmd_tree,20,'Build trees.'],
	NEW => [\&cmd_new,100,'Create a new flatgrass map.'],
	SAVE => [\&cmd_save,20,'Make a backup on the server.'],
	LOAD => [\&cmd_load,100,'Reload the map.'],
	GENERATE => [\&cmd_generate,200],
	CONFIG => [\&cmd_config,200],
	MUTE => [\&cmd_mute,0,'Mute a player, making them a harmless spectator.'],
	UNMUTE => [\&cmd_unmute,100,'Unmute.'],
	WHERE => [\&cmd_where,0,'Shows you where you are.'],
	MYPOS => [\&cmd_where,0],
	PAINT => [\&cmd_paint,0,'Easily replace blocks.'],
	ADMIN => [\&cmd_admin,200,'Choose an admin level.'],
	DENSE => [\&cmd_dense,20,'Build unbreakable blocks.'],
};

sub cmd_help() {
	my $id = shift;
	&send_msg($id,"Available commands:");
	&send_msg($id,"@ - Whisper a message to the named player.");
	foreach (keys %{$server{'commands'}}) {
		my @cmd = ($server{'commands'}{$_}[1], $server{'commands'}{$_}[2]);
		&send_msg($id,"/$_ - $cmd[1]") if ($cmd[1] && $server{'users'}[$id]{'admin'} >= $cmd[0]);
	}
}

sub cmd_color() {
	my $id = shift;
	&send_msg($id,"Color codes:");
	&send_msg($id,"- &0%c0 &1%c1 &2%c2 &3%c3 &4%c4 &5%c5 &6%c6 &7%c7");
	&send_msg($id,"- &8%c8 &9%c9 &a%ca &b%cb &c%cc &d%cd &e%ce &f%cf");
	&send_msg($id,"Type any of these in your text and everything after it");
	&send_msg($id,"will be in the color you chose.");
}

sub cmd_me() {
	my $id = shift;
	unless (@_) {
		&send_msg($id,"No text to send.");
		return;
	}
	my $msg = "&d* ".$server{'users'}[$id]{'nick'}."&d @_";
	print &strip($msg)."\n";
	foreach (@{$server{'users'}}) {
		next unless defined($_);
		&send_raw($_->{'sock'},13,$id,$msg) if ($_->{'active'});
	}
}

sub cmd_say() {
	my $id = shift;
	unless (@_) {
		&send_msg($id,"No text to send.");
		return;
	}
	&global_msg("@_");
}

sub cmd_op() {
	my $id = shift;
	unless (@_) {
		&send_msg($id,"No user to op.");
		return;
	}
	my $save = 0;
	foreach my $name (@_) {
		$name = lc($name);
		if (($server{'admin'}{$name}||0) >= 100) {
			&send_msg($id,"$name is already an admin.");
			next;
		}
		my $found = 0;
		foreach (@{$server{'users'}}) {
			next unless (defined($_) && lc($_->{'account'}) eq $name);
			$found = 1;
			$save = 1;
			$server{'admin'}{$name} = 100;
			$_->{'admin'} = 100;
			#$_->{'adminbreak'} = 1;
			my $oid = $_->{'id'};
			&send_msg($id,"$name is now an admin.");
			&send_msg($oid,"You are now an admin.");
			&send_msg($oid,"Check &f/help&e again to see what you can do!");
			last;
		}
		&send_msg($id,"$name could not be found.") unless ($found);
	}
	&save_admins() if ($save);
}

sub cmd_deop() {
	my $id = shift;
	unless (@_) {
		&send_msg($id,"No user to deop.");
		return;
	}
	my $save = 0;
	foreach my $name (@_) {
		$name = lc($name);
		if (($server{'admin'}{$name}||0) > ($server{'admin'}{lc($server{'users'}[$id]{'account'})}||0)) {
			&send_msg($id,"$name is higher ranked than you.");
			next;
		}
		my $found = 0;
		foreach (@{$server{'users'}}) {
			next unless (defined($_) && lc($_->{'account'}) eq $name);
			$found = 1;
			$save = 1;
			undef $server{'admin'}{$name};
			$_->{'admin'} = 0;
			undef $_->{'adminbreak'};
			undef $_->{'build'};
			my $oid = $_->{'id'};
			&send_login($oid);
			&send_msg($id,"$name is no longer an admin.") if ($id != $oid);
			&send_msg($oid,"You are no longer an admin.");
			last;
		}
		&send_msg($id,"$name could not be found.") unless ($found);
	}
	&save_admins() if ($save);
}

sub cmd_build() {
	my $id = shift;
	unless (@_) {
		unless ($server{'users'}[$id]{'build'}) {
			&send_msg($id,'Usage: &f/build &bblock type&e - Build the special block types.');
			&send_msg($id,'Available block types:');
			# TODO: Generate this list or something.
			if ($server{'users'}[$id]{'admin'} >= 200) {
				&send_msg($id,'solid/admin, grass, water, lava, gold, iron, coal,');
				&send_msg($id,'lava sponge, dynamite, super sponge, watervator');
			}
			elsif ($server{'users'}[$id]{'admin'} >= 20) {
				&send_msg($id,'solid/admin, grass, gold, iron, coal, lava sponge,');
				&send_msg($id,'dynamite, super sponge, watervator');
			}
			else { &send_msg($id,'grass, gold, iron, coal, lava sponge, super sponge, watervator'); }
			&send_msg($id,'Use &f/build&e again to unset.');
			return;
		}
		undef $server{'users'}[$id]{'build'};
		&send_msg($id,'Now building normally.');
		return;
	}
	my $type = &strip(lc("@_"));
	my $typename = '';
	if ($type =~ /solid|admin/ && $server{'users'}[$id]{'admin'} >= 20) { $type = 7; $typename = 'solid adminium'; }
	elsif ($type =~ /lava\s*sponge/) { $type = -1; $typename = 'lava sponge'; }
	elsif ($type =~ /super\s*sponge/) { $type = -3; $typename = 'super sponge'; }
	elsif ($type =~ /grass/) { $type = 2; $typename = 'grass'; }
	elsif ($type =~ /watervator/) { $type = -4; $typename = 'watervator'; }
	elsif ($type =~ /water/ && $server{'users'}[$id]{'admin'} >= 200) { $type = 8; $typename = 'water'; }
	elsif ($type =~ /lava/ && $server{'users'}[$id]{'admin'} >= 200) { $type = 10; $typename = 'lava'; }
	elsif ($type =~ /gold/) { $type = 14; $typename = 'gold ore'; }
	elsif ($type =~ /iron|copper/) { $type = 15; $typename = 'iron ore'; }
	elsif ($type =~ /coal|oil/) { $type = 16; $typename = 'coal'; }
	elsif ($type =~ /dynamite|tnt|bomb/ && $server{'users'}[$id]{'admin'} >= 20) { $type = -2; $typename = 'dynamite'; }
	else {
		&send_msg($id,"Unknown block type '$type'.");
		return;
	}
	&send_msg($id,"Now building $typename blocks in place of stone.");
	$server{'users'}[$id]{'build'} = $type;
}

sub cmd_solid() {
	my $id = shift;
	if (($server{'users'}[$id]{'build'}||0) == 7) { &cmd_build($id); }
	else { &cmd_build($id,'solid'); }
}

sub cmd_adminbreak() {
	my $id = shift;
	$server{'users'}[$id]{'adminbreak'} = !$server{'users'}[$id]{'adminbreak'};
	&send_login($id);
	if ($server{'users'}[$id]{'adminbreak'}) { &send_msg($id,"You may now break solid admin blocks."); }
	else { &send_msg($id,"You cannot break solid admin blocks."); }
}

sub cmd_kick() {
	my $id = shift;
	my $knick = &strip(lc(shift));
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $knick);
		&kick($_->{'id'},"@_");
		return;
	}
	&send_msg($id,"User '$knick' could not be found.");
}

sub cmd_ban() {
	my $id = shift;
	my $bnick = &strip(lc(shift));
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $bnick);
		$server{'bans'}{$bnick} = 1;
		&save_bans();
		&kick($_->{'id'},'You have been banned.');
		return;
	}
	&send_msg($id,"User '$bnick' could not be found.");
}

sub cmd_unban() {
	my $id = shift;
	my $bnick = &strip(lc(shift));
	if ($server{'bans'}{$bnick}) {
		undef $server{'bans'}{$bnick};
		&send_msg($id,"$bnick has been unbanned.");
	}
	else { &send_msg($id,"$bnick is not in the ban list."); }
}

sub cmd_banip() {
	my $id = shift;
	my $bnick = &strip(lc(shift));
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $bnick);
		$server{'ipbans'}{$_->{'sock'}->peerhost} = $_->{'account'};
		&save_ipbans();
		&kick($_->{'id'},'You have been banned.');
		return;
	}
	&send_msg($id,"User '$bnick' could not be found.");
}

sub cmd_nick() {
	my $id = shift;
	my $nick = "@_";
	if ($server{'users'}[$id]{'nick'} eq $nick) {
		&send_msg($id,"Your name already is '$nick&e'.");
		return;
	}
	$server{'users'}[$id]{'nick'} = $nick;
	if ($nick eq $server{'users'}[$id]{'account'}) { undef $server{'nick'}{lc($server{'users'}[$id]{'account'})}; }
	else { $server{'nick'}{lc($server{'users'}[$id]{'account'})} = $nick; }
	&save_nicks();
	unless ($server{'users'}[$id]{'hide'}) {
		&global_die($id);
		&global_spawn($id,$nick,@{$server{'users'}[$id]{'pos'}},@{$server{'users'}[$id]{'rot'}});
	}
	&send_msg($id,"Your name is now '$nick&e'");
}

sub cmd_onick() {
	my $id = shift;
	my $friend = &strip(lc(shift));
	my $nick = "@_";
	my $fuser;
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $friend);
		$fuser = $_;
		last;
	}
	if ($fuser->{'nick'} eq $nick) {
		&send_msg($id,"Their name is already '$nick&e'.");
		return;
	}
	$fuser->{'nick'} = $nick;
	if ($nick eq $fuser->{'account'}) { undef $server{'nick'}{lc($fuser->{'account'})}; }
	else { $server{'nick'}{lc($fuser->{'account'})} = $nick; }
	$server{'nick'}{lc($fuser->{'account'})} = $nick;
	&save_nicks();
	unless ($fuser->{'hide'}) {
		&global_die($fuser->{'id'});
		&global_spawn($fuser->{'id'},$nick,@{$fuser->{'pos'}},@{$fuser->{'rot'}});
	}
	&send_msg($fuser->{'id'},"An admin set your name to '$nick&e'");
	&send_msg($id,"Their name is now '$nick&e'");
}

sub cmd_hide() {
	my $id = shift;
	$server{'users'}[$id]{'hide'} = !$server{'users'}[$id]{'hide'};
	if ($server{'users'}[$id]{'hide'}) {
		&global_die($id);
		&send_msg($id,'You are now hidden.');
	}
	else {
		&global_spawn($id,$server{'users'}[$id]{'nick'},@{$server{'users'}[$id]{'pos'}},@{$server{'users'}[$id]{'rot'}});
		&send_msg($id,'You are now visible.');
	}
}

sub cmd_showself() {
	my $id = shift;
	$server{'users'}[$id]{'showself'} = !$server{'users'}[$id]{'showself'};
	if ($server{'users'}[$id]{'showself'}) {
		&send_raw($server{'users'}[$id]{'sock'},7,$id,$server{'users'}[$id]{'nick'},@{$server{'users'}[$id]{'pos'}},@{$server{'users'}[$id]{'rot'}});
		&send_msg($id,"Now showing your own movements with network latency.");
	}
	else {
		&send_raw($server{'users'}[$id]{'sock'},12,$id);
		&send_msg($id,"Doppleganger hidden.");
	}
}

sub cmd_teleport() {
	my $id = shift;
	my $nick = lc(shift);
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $nick && $_->{'pos'});
		my @pos = @{$_->{'pos'}};
		my @rot = @{$_->{'rot'}};
		&send_raw($server{'users'}[$id]{'sock'},8,-1,@pos,@rot);
		#@{$server{'users'}[$id]{'pos'}} = @pos;
		#@{$server{'users'}[$id]{'rot'}} = @rot;
		&send_msg($id,"Teleported to $nick.");
		return;
	}
	&send_msg($id,"$nick could not be found.");
}

sub cmd_fetch() {
	my $id = shift;
	my $nick = lc(shift);
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $nick);
		my @pos = @{$server{'users'}[$id]{'pos'}};
		my @rot = @{$server{'users'}[$id]{'rot'}};
		&send_raw($_->{'sock'},8,-1,@pos,@rot);
		#@{$_->{'pos'}} = @pos;
		#@{$_->{'rot'}} = @rot;
		&send_msg($id,"Fetched $nick.");
		return;
	}
	&send_msg($id,"$nick could not be found.");
}

sub cmd_setspawn() {
	my $id = shift;
	my @pos = @{$server{'users'}[$id]{'pos'}};
	my @rot = @{$server{'users'}[$id]{'rot'}};
	$pos[0] = floor($pos[0] / 32);
	$pos[1] = floor($pos[1] / 32);
	$pos[2] = floor($pos[2] / 32);
	$rot[1] = 1;
	@{$server{'map'}{'spawn'}} = (@pos,@rot);
	$pos[0] = $pos[0] * 32 + 16;
	$pos[1] = $pos[1] * 32 + 16;
	$pos[2] = $pos[2] * 32 + 16;
	&send_raw($server{'users'}[$id]{'sock'},8,-1,@pos,@rot);
	&send_msg($id,"Spawn location set.");
}

sub cmd_tree() {
	my $id = shift;
	$server{'users'}[$id]{'tree'} = !$server{'users'}[$id]{'tree'};
	if ($server{'users'}[$id]{'tree'}) { &send_msg($id,"Place a stump to build a tree."); }
	else { &send_msg($id,"Now building normal stumps."); }
}

sub cmd_save() {
	my $id = shift;
	print $server{'users'}[$id]{'account'}." SAVE\n";
	if (($server{'users'}[$id]{'save_time'}||0) < time()+120
	&& $server{'users'}[$id]{'admin'} < 200) {
		&send_msg($id,"You just saved less than two minutes ago!");
		&send_msg($id,"Wait a while before doing this again.");
		return;
	}
	$server{'users'}[$id]{'save_time'} = time();
	&map_save(1);
	#&send_msg($id,"Map saved and backed up as &f$time");
	&send_msg($id,"Remember this code to retrieve it later.");
}

sub cmd_load() {
	my $id = shift;
	my $map_name = shift;
	my $time;
	if (!$map_name) { $map_name = $server{'map_name'}; }
	else { ($map_name,$time) = split(/\//,$map_name); }

	my $path;
	if (!$time) { $path = "maps/$map_name.gz"; }
	else { $path = "maps/backup/$map_name/$time.gz"; }
	unless (&map_find($path)) {
		&send_msg($id,"Failed to load '$time'");
		return;
	}

	&global_msg("- &cLoading a map");
	&global_msg("Please wait...");
	&map_load($path);
	&global_mapchange();
	$server{'map_name'} = $map_name;
}

sub cmd_generate() {
	my $id = shift;
	my $size = uc(shift);
	unless (defined($size)) {
		&send_msg($id,"Usage: &f/generate &csize");
		&send_msg($id,"Sizes: &fSmall&e (64x32x64), &fMedium&e (128x64x128),");
		&send_msg($id,"&fStandard&e (256x64x256), &fLarge&e (256x128x256),");
		&send_msg($id,"&fCustom&e (Put size after it, &cBE CAREFUL&e)");
		return;
	}
	my @size;
	if ($size eq 'SMALL') { @size = (64,32,64); }
	elsif ($size eq 'MEDIUM') { @size = (128,64,128); }
	elsif ($size eq 'STANDARD') { @size = (256,64,256); }
	elsif ($size eq 'LARGE') { @size = (256,128,256); }
	elsif ($size eq 'CUSTOM') { @size = split(/[\sx,]+/,"@_"); }
	else {
		&send_msg($id,"Unknown size '$size'");
		return;
	}
	&global_msg("- &cGenerating a new map");
	&global_msg("Please wait...");
	&map_generate(@size);
	#&map_save(1);
}

sub cmd_new() {
	my $id = shift;
	my $file = shift;
	my $type = uc(shift);
	my @size = split(/[\sx,]+/,"@_");
	unless (defined($type)) {
		&send_msg($id,"Usage: &f/new &cfile_name type width depth height");
		&send_msg($id,"Types: &fFlatgrass&e, &fEmpty&e, &fOcean");
		return;
	}
	unless ($file) { &send_msg($id,"Must include a filename."); return; }
	unless (@size == 3) { &send_msg($id,"Must include a size, file name may not contain spaces."); return; }
	if ($type eq 'EMPTY') { $type = 0; }
	elsif ($type eq 'FLATGRASS') { $type = 1; }
	elsif ($type eq 'OCEAN') { $type = 2; }
	else {
		&send_msg($id,"Unknown map type '$type'");
		return;
	}
	&global_msg("- &cGenerating a new map");
	&global_msg("Please wait...");
	&map_new($type,@size);
	$server{'map_name'} = $file;
	mkdir "maps/backup/$server{'map_name'}";
	#&map_save(1);
}

sub cmd_config() {
	my $id = shift;
	my $name = lc(shift);
	my $value = "@_";
	if ($value eq '') {
		&send_msg($id,"$name is $server{'config'}{$name}");
		return;
	}
	$server{'config'}{$name} = $value;
	&send_msg($id,"Configuration changed.");
	#&save_config();
}

sub cmd_mute() {
	my $id = shift;
	my $name = &strip(lc(shift));
	unless ($name) {
		&send_msg($id,"No user to mute.");
		return;
	}
	if ($server{'users'}[$id]{'admin'} < 100 && time() < ($server{'users'}[$id]{'mute_time'}||0)+(60*30)) {
		&send_msg($id,"Already used your mute a while ago. Too bad...");
		return;
	}
	if (($server{'admin'}{$name}||0) > $server{'users'}[$id]{'admin'}) {
		&send_msg($id,"$name is higher ranked than you.");
		return;
	}
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $name);
		if ($_->{'mute'}) {
			&send_msg($id,"$name is already muted.");
			return;
		}
		$_->{'mute_vote'}++;
		$server{'mute_vote'}{$name} = $_->{'mute_vote'};
		$server{'users'}[$id]{'mute_time'} = time();
		if ($server{'users'}[$id]{'admin'} >= 100 || $_->{'mute_vote'} >= 3) {
			print "Muting ".$_->{'account'}."\n";
			$_->{'mute'} = 1;
			$server{'mute'}{$name} = 1;
			$_->{'mute_vote'} = 0;
			$server{'mute_vote'}{$name} = 0;
			&save_muted();
			&global_msg('- '.$_->{'nick'}."&e is now muted.");
			$_->{'nick'} = '&4[MUTED] '.&strip($_->{'nick'});
			unless ($_->{'hide'}) {
				my $oid = $_->{'id'};
				&global_die($oid);
				&global_spawn($oid,$_->{'nick'},@{$_->{'pos'}},@{$_->{'rot'}});
			}
		}
		&save_mutevote();
		return;
	}
	&send_msg($id,"$name could not be found.");
}

sub cmd_unmute() {
	my $id = shift;
	my $name = &strip(lc(shift));
	unless ($name) {
		&send_msg($id,"No user to unmute.");
		return;
	}
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $name);
		if (!$_->{'mute'}) {
			&send_msg($id,"$name isn't muted.");
			return;
		}
		$_->{'mute'} = 0;
		undef $server{'mute'}{$name};
		$_->{'mute_vote'} = 0;
		$server{'mute_vote'}{$name} = 0;
		$_->{'nick'} = $server{'nick'}{$name} || $_->{'account'};
		&global_msg('- '.$_->{'nick'}."&e is now unmuted.");
		unless ($_->{'hide'}) {
			my $oid = $_->{'id'};
			&global_die($oid);
			&global_spawn($oid,$_->{'nick'},@{$_->{'pos'}},@{$_->{'rot'}});
		}
		&save_muted();
		&save_mutevote();
		return;
	}
}

sub cmd_where() {
	my $id = shift;
	my @pos = @{$server{'users'}[$id]{'pos'}};
	$pos[0] = floor($pos[0]/32);
	$pos[1] = floor($pos[1]/32);
	$pos[2] = floor($pos[2]/32);
	&send_msg($id,"Where: @pos");
}

sub cmd_paint() {
	my $id = shift;
	$server{'users'}[$id]{'paint'} = !$server{'users'}[$id]{'paint'};
	if ($server{'users'}[$id]{'paint'}) { &send_msg($id,"Break blocks to replace them."); }
	else { &send_msg($id,"Returned to normal building."); }
}

sub cmd_dense() {
	my $id = shift;
	$server{'users'}[$id]{'dense'} = !$server{'users'}[$id]{'dense'};
	if ($server{'users'}[$id]{'dense'}) { &send_msg($id,"Now building dense (protected) blocks."); }
	else { &send_msg($id,"Now building normal (breakable) blocks."); }
}

sub cmd_admin() {
	my $id = shift;
	my $name = lc(shift);
	my $level = shift;
	unless ($name) {
		&send_msg($id,"No user to admin.");
		return;
	}
	unless ($level) {
		&send_msg($id,"No level number given.");
		return;
	}
	if (($server{'admin'}{$name}||0) >= $level) {
		&send_msg($id,"$name is already an admin.");
		next;
	}
	my $found = 0;
	foreach (@{$server{'users'}}) {
		next unless (defined($_) && lc($_->{'account'}) eq $name);
		$found = 1;
		$server{'admin'}{$name} = $level;
		$_->{'admin'} = $level;
		#$_->{'adminbreak'} = 1;
		my $oid = $_->{'id'};
		&send_msg($id,"$name is now an admin level $level.");
		&send_msg($oid,"You are now an admin level $level");
		&send_msg($oid,"Check &f/help&e again to see what you can do!");
		last;
	}
	&send_msg($id,"$name could not be found.") unless ($found);
	&save_admins() if ($found);
}

1;
