#!/bin/bash

echo
echo "install these packages:"
echo "zlib1g-dev libwww-perl"
echo

ln -s /home/check/checkbot/perl/lib/perl5 /home/check/perl5

perl -MCPAN -e 'my $c = "CPAN::HandleConfig"; $c->load(doit => 1, autoconfig => 1); $c->edit(pushy_https => 1); $c->edit(prerequisites_policy => "follow"); $c->edit(build_requires_install_policy => "yes"); $c->commit'
if ! which cpanm
then
	cpan -i App::cpanminus
fi

cpanm $@ \
	Algorithm::Diff \
	Spiffy \
	YAML \
	Log::Log4perl \
	CPAN \
	CPAN::DistnameInfo \
	Try::Tiny \
	Mozilla::CA \
	WWW::Shorten \
	Net::SSLeay \
	XML::LibXML \
	IO::Socket::SSL::Utils \
	LWP::Protocol::https \
	LWP::UserAgent \
	JSON::Parse \
	WWW::Shorten::TinyURL

echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!                                        !!"
echo "!!    Run 'cpanm -v Net::IRC' manually    !!"
echo "!!    because it requires manual input    !!"
echo "!!                                        !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo
