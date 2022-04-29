package Substitute;
use strict;
use warnings;

my $aliasfile = "/home/check/checkbot/debuggers_aliases";
my %aliases;

# gets the contents of a file in one go, instead of going line-per-line
sub slurpfile {
	my ($self, $filename) = @_;
	local $/;
	undef $/;
	open(SFILE, "<$filename");
	my $sfile = <SFILE>;
	close(SFILE);
	return $sfile;
}

sub printfile {
	my ($self, $filename, %content) = @_;
	open(OUT, ">$filename");
	for my $k (keys %content) {
		print OUT "$k $content{$k}\n";
	}
	close(OUT);
}

sub aliases {
	my $self = shift;
	unless (keys %aliases) {
		$_ = $self->slurpfile($aliasfile);
		%aliases = split /\n|\s/;
	}
	return %aliases;
}

sub find_real {
  my ($self, $who) = @_;
	my %ali = $self->aliases();
	$who = lc $who;
  return ($ali{$who} or $who);
}

sub find_alias {
  my ($self, $who) = @_;
	my %ali = reverse $self->aliases();
	$who = lc $who;
  return ($ali{$who} or $who);
}

sub alias {
  my ($self, $who, $real) = @_;
	my %ali = $self->aliases();
	$who = lc $who;
	if(defined $real) {
		$real = lc $real;
		$ali{$who} = $real;
		$self->printfile($aliasfile, %ali);
		%aliases = %ali;
		return $real;
	}
  return ($ali{$who} or $who);
}

sub unalias {
  my ($self, $who) = @_;
	my %ali = $self->aliases();
	$who = lc $who;
	return 0 unless $ali{$who};
	delete $ali{$who};
	$self->printfile($aliasfile, %ali);
	%aliases = %ali;
  return 1;
}

2;
