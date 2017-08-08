package Roster::Entry;
use Class::Accessor;
use base qw(Class::Accessor);
Roster::Entry->mk_ro_accessors(qw(from to duration room teacher weeks subject));

sub new {
  my $class = shift;
  my $self = {@_};
  $self->{from} /= 2;
  $self->{ to } /= 2;
  $self->{duration} /= 2;
  bless $self, $class
}

sub get {
  my ($self, $val) = @_;
  $val = $self->{$val};
  return (defined $val and (ref $val or $val =~ /\S/) ? $val : "??");
}

package Roster;

use strict;
use warnings;

use HTML::TreeBuilder;
use LWP::Simple;
use Digest::MD5 qw(md5_hex);

sub _add_class {
	my ($self, $day, $desc) = @_;
	my $aref = ($self->{days}[$day] ||= []);

	@$aref = sort {$a->from <=> $b->from} (@$aref, $desc);
}

sub _contains {
	my ($week, $aref) = @_;
	return (grep $_ == $week, @$aref) > 0;
}

# expand "1-3, 5-7, 9, 11, 13" to [1,2,3,5,6,7,9,11,13]
sub _expand {
 [ map { /(\d+)-(\d+)/ ? ($1..$2) : $_ } split /,\s*/, shift ]
}

sub new {
	my $class = shift;
	my $self = {
		days => [],
		generated => time()
	};
	bless $self, $class;
}

sub new_from_contents {
	my ($class, $ref) = @_;
	$class->new->add_from_contents($ref);
}

sub new_from_url {
	my ($class,$url) = @_;
	my $self = $class->new();
	$self->add_from_url($url);
	return $self;
}

sub add_from_url { 
	my ($self,$url) = @_;
	$self->add_from_contents(\get($url));
}

sub add_from_contents {
	my ($self,$ref) = @_;

	my $contents = $$ref;
	$contents =~ s|.*<td></td><td><font color='#808000'>.*?</font><font color='#808000'>\d+:\d+</font><font color='#808000'>u</font></td><td></td>.*\n||;
	$self->{digest} = md5_hex($contents);

	my $p = HTML::TreeBuilder->new_from_content($contents);
	my $body = $p->find("body");
	my ($prelude,$maintable) = $body->content_list;

	my ($weeks) = $prelude->look_down("_tag" =>"td", sub{ (shift->as_text || "") =~ /geselecteerde weken : (\d+)-(\d+)/ }) or die "Can't find weken!";
	my ($start,$end) = $weeks->as_text =~ /geselecteerde weken : (\d+)-(\d+)/;

	$self->{startweek} = $start;
	$self->{endweek}   = $end;

	my ($sgroep) = $prelude->look_down("_tag" =>"td", sub{ (shift->as_text || "") =~ /uurrooster voor/ }) or die "Can't find sgroep!";
	($self->{sgroep}) = $sgroep->as_text =~ /uurrooster voor studentengroep\s*:(.*)/;

	my @rows = $maintable->content_list;
	my ($starthr,$endhr) = map $_->as_text, ((shift @rows)->content_list)[1,-1];
	s/:(\d+)/$1 == 30 ? ".5" : ""/e,$_*=2 for ($starthr, $endhr);

	$self->{starthr} = $starthr;
	$self->{endhr}   = $endhr;

	my $day = 0;
	while (@rows) {
		# eerste element van de eerste rij heeft een rowspan
		my $rowcount = ($rows[0]->content_list)[0]->attr('rowspan');
		my @to_parse = splice @rows,0,$rowcount;
		$to_parse[0]->splice_content(0,1); #remove <td>$dayname

		foreach my $row (@to_parse) {
			my $i = $starthr;
			foreach my $col ($row->content_list) {
				if (defined (my $duration = $col->attr('colspan'))) {
					# class!
					my (undef,$subj,$room,$weeks,$teacher) = map $_->as_text, $col->find('td');
					print $subj;
					$self->_add_class($day, Roster::Entry->new( subject => $subj, from => $i, to => $i+$duration, duration => $duration, room => $room, teacher => $teacher, weeks => _expand($weeks)));
					$i+= $duration;
				} else {
				$i++;
				}
			}
		}

		$day++;
	}
	return $self;
}

sub day {
	my ($self,$day) = @_;
	return $self->{days}[$day];
}

sub week {
	my ($self, $week) = @_;

	my @res = map { my $day=$_; [grep _contains($week,$_->weeks), @$day] } @{$self->{days}};

	return wantarray ? @res : \@res;
}

sub digest {
	shift->{digest}
}

package Roster::Cache;

use LWP::Simple;
use Digest::MD5 qw(md5_hex);
use Storable qw(store retrieve);
use File::Spec;
use Time::Local;
use URI::Escape;

sub new {
	my ($class, $store) = @_;
	die "\$store is not a directory! ++ungood!\n" unless -d $store;

	my $metapath = File::Spec->catfile($store, "meta");

	my $self = -f $metapath ? retrieve $metapath : {};
	$self->{paths}{root} = $store;
	$self->{paths}{cache} = File::Spec->catfile($store, "cache");
	$self->{paths}{meta} = $metapath;
	-d || mkdir $_ for @{$self->{paths}}{qw(root cache)};
 
	return bless $self, $class;
}

sub _url {
	my ($self, $id) = @_;
	return $self->{urls}{lc $id};
}

sub _cached {
	my ($self,$id) = @_;
	my $path = _cpath($id);
	return retrieve($path);
}

sub _cpath {
	my ($self, $id) = @_;
	return File::Spec->catfile($self->{paths}{cache}, uri_escape($id));
}

sub fetch {
	my ($self, $id) = @_;

	my $url = $self->_url($id);
	return unless defined $url;

	my $cont = get($url);
	$cont =~ s/.*afdrukdatum.*//;
	return $self->_cached($id)
		if defined $self->{digests}{$id}
	     and md5_hex($cont) eq $self->{digests}{$id}
	     and -f $self->_cpath($id);
	
	#damn, it's been changed.
	my $r = Roster->new_from_contents(\$cont);

	$self->{digests}{$id} = $r->digest;

	my $path = $self->_cpath($id);
	store $r, $path;

	store $self, $self->{paths}{meta};

	return $r;
}

sub fetch_callback {
  my ($self, $bot, $event, $id, $time) = @_;

  my $url = $self->_url($id);
  $bot->say($event, "Onbekende richting: $id"),return unless defined $url;

  $bot->getURI($event,$url, sub {
    my ($cont, $event) = @_;
    $cont =~ s/.*afdrukdatum.*//;

    my $r;
    if(defined $self->{digests}{$id} 
      and md5_hex($cont) eq $self->{digests}{$id}
      and -f $self->_cpath($id)) {
      $r = $self->_cached($id);
    } else {
      $r = Roster->new_from_contents(\$cont);

      $self->{digests}{$id} = $r->digest;

      my $path = $self->_cpath($id);
      store $r, $path;

      store $self, $self->{paths}{meta};
    }
    $bot->say($event, format_($r, $time));
  })
}

sub formatEntry {
  my $ref = shift;
  return "Yay! geen les!\n"
    unless (defined $ref and @$ref);

  join " | ", map { sprintf "%s (%d-%d) in %s", $_->subject, $_->from, $_->to, $_->room } @$ref;
}

sub format_ {
  my ($r, $time) = @_;
  my $week = weeknr();
  my $day = ((localtime)[6] - 1) % 7;

  if ($time =~ /^(vandaag|nu)$/) {
  } elsif ($time =~ /^morgen?$/) {
    $day = 0, ++$week if ++$day > 6;
  } elsif ($time =~ /^overmorgen?$/) {
    $day %= 7, ++$week if ($day += 2) > 6;
  } elsif ($time =~ /^gisteren?$/) {
    $day = 6, --$week if --$day < 0;
  } elsif ($time =~ /^eergisteren?$/) {
    $day %= 7, --$week if ($day -= 2) < 0;
  } elsif ($time =~ /^(maan|dins|woens|donder|vrij|zater|zon)dag$/) {
    my %days = qw(maan 0 dins 1 woens 2 donder 3 vrij 4 zater 5 zon 6);
    my $newday = $days{$1};
    $week++ if $newday <= $day;
    $day = $newday;
  } else {
    return "Usage: check uurrooster <richting> <nu|vandaag|weekdag>\n";
  }
	$week = 52 if $week == 0;
	$week = 1  if $week == 53;
  formatEntry($r->week($week)->[$day]);
}

sub weeknr {
  my $time = timelocal(0,0,0,30,8,(localtime)[5]); # 30 sept $current_year
    if ($time > time())
    { $time = timelocal(0,0,0,30,8,(localtime)[5]-1); }

# backtrack to monday
  $time -= 86400 until 1 == (localtime($time))[6];

  return 1+int((time()-$time)/7/86400);
}

sub add_url {
	my ($self, $id) = @_;
	my $escaped = uri_escape($id);
	print $escaped;
	$self->{urls}{lc $id} =
		"http://locus.vub.ac.be:8000/reporting/individual?idtype=name&days=1-7".
		"&template=Student+Set+Individual&objectclass=Student+Set".
		"&width=100&identifier=$escaped&weeks=1-40&periods=0-34";
	return $id;
}

sub add_nick {
  my ($self, $nick, $id) = @_;

	$id = $self->add_url($1) if $id =~ /["'](.*)["']/;
	return unless $self->_url($id);

  $self->{people}{lc $nick} = lc $id;
  store $self, $self->{paths}{meta};
  return 1;
}

sub find_nick {
  my ($self, $nick) = @_;
  return $self->{people}{lc $nick};
}

sub urls {
  my $self = shift;
  return keys %{$self->{urls}};
}

42;
