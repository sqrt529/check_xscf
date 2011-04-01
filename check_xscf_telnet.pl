#!/usr/bin/perl
# check_xscf_telnet.pl - Check XSCF (Sun M4000/M5000/M8000/M9000) via telnet
#
# Copyright (C) 2010 Joachim "Joe" Stiegler <blablabla@trullowitsch.de>
# 
# This program is free software; you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program;
# if not, see <http://www.gnu.org/licenses/>.
#
# --
# 
# Version: 1.0 - 2010-10-13
#
# You'll need Net::Telnet from CPAN

use warnings;
use strict;
use Getopt::Std;
use Net::Telnet;

sub usage {
	print "$0 [ -tvfadbes ] < -h xscf-host> < -u user> < -p passwd> [ -c 0..100 ] [ -w 0..100 ]\n";
	print "\t-t: temp, -v: volt, -f: Fan, -a: air, -d: Domains, -b: Boards, -e: Hardware, -s: System Init Failures\n";
	exit (1);
}

our ($opt_t, $opt_v, $opt_f, $opt_a, $opt_w, $opt_c, $opt_u, $opt_p, $opt_h, $opt_d, $opt_b, $opt_e, $opt_s);

if (!getopts("tvfaw:c:u:p:h:dbes")) {
	usage();
}

if ( (!defined($opt_h)) && (!defined($opt_u)) && (!defined($opt_p)) ) {
	usage();
}

my $username = $opt_u;
my $passwd = $opt_p;
my $host = $opt_h;

my $warnval = $opt_w;
my $critval = $opt_c;

my $text = "";
my $criticals = 0;
my $warnings = 0;

my $context = "";

my $t = new Net::Telnet (Timeout => 10, Prompt => '/XSCF>/') or die "Error: $!\n";

$t->open($host);
$t->login($username, $passwd);

if (defined($opt_t)) {
	if ( (!defined($opt_c)) || (!defined($opt_w)) ) {
		usage();
	}

	$context = "Temperature";

	my @temp = $t->cmd("showenvironment temp");

	foreach my $temp (@temp) {
		chomp $temp;

		if ($temp =~ /C$/) {

			$temp =~ s/ //g;
			$temp =~ s/C$//g;

			my @line = split(/:/, $temp);
		
			if ($line[1] ge $critval) {
				$text = $text.$line[0].": ".$line[1]." C; ";
				$criticals++;
			}
			elsif ($line[1] ge $warnval) {
				$text = $text.$line[0].": ".$line[1]." C; ";
				$warnings++;
			}
		}
	}
}

if (defined($opt_a)) {
	if ( (!defined($opt_c)) || (!defined($opt_w)) ) {
		usage();
	}

	$context = "Air flow";
	
	my @air = $t->cmd("showenvironment air");
	
	foreach my $air (@air) {
		chomp $air;

		$air =~ s/CMH$//g;

		my @line = split(/:/, $air);

		if ($line[1] <= $critval) {
			$text = $text.$line[0].": ".$line[1]." CHM; ";
			$criticals++;
		}
		elsif ($line[1] <= $warnval) {
			$text = $text.$line[0].": ".$line[1]." CHM; ";
			$warnings++;
		}
	}
}

if (defined($opt_f)) {
	if ( (!defined($opt_c)) || (!defined($opt_w)) ) {
		usage();
	}

	$context = "Fan status";

	my @fan = $t->cmd("showenvironment Fan");

	foreach my $fan (@fan) {
		chomp $fan;

		if ($fan =~ /rpm$/) {

			$fan =~ s/ //g;
			$fan =~ s/rpm$//g;

			my @line = split(/:/, $fan);

			if ($line[1] =~ /speed$/) {
				next;
			}

			if ($line[1] <= $critval) {
				$text = $text.$line[0].": ".$line[1]." RPM; ";
				$criticals++;
			}
			elsif ($line[1] <= $warnval) {
				$text = $text.$line[0].": ".$line[1]." RPM; ";
				$warnings++;
			}
		}
	}
}

if (defined($opt_v)) {
	$context = "Volt status";

	#my @volt = $t->cmd("showenvironment volt");
	print "Not implemented yet :-)\n";
}

if (defined($opt_d)) {
	$context = "Domain status";

	my @domain = $t->cmd("showdomainstatus -a");

	foreach my $domain (@domain) {
		chomp $domain;

		my @line = split(' ', $domain);

		if ($line[0] =~ /^DID/) {
			next;
		}

		if ( (!($line[1] =~ /Running/)) && (!($line[1] =~ /-/)) ) {
			$text = $text."DID: ".$line[0]." ".$line[1]."; ";
			$criticals++;
		}
	}
}

if (defined($opt_b)) {
	$context = "Board status";

	my @boards = $t->cmd("showboards -a");

	foreach my $board (@boards) {
		chomp $board;
		
		my @line = split(' ', $board);
		
		if ( ($line[0] =~ /^XSB/) || ($line[0] =~ /^-/) ) {
			next;
		}

		if ( ($line[5] =~ /y/) && (!($line[7] =~ /Normal/)) ) {
			$text = $text."XSB: ".$line[0]." ".$line[7]."; ";
			$criticals++;
		}
	}
}

if (defined($opt_e)) {
	$context = "Hardware status";
	
	my @status = $t->cmd("showhardconf");

	foreach my $status (@status) {
		chomp $status;
		
		if ($status =~ /Status/) {
			my @line = split(/:/, $status);

			if ($line[0] =~ /\+/) {
				next;
			}

			my @statline = split(/;/, $line[1]);

			if ( (!($statline[0] =~ /Running/)) && (!($statline[0] =~ /Normal/)) && (!($statline[0] =~ /On/)) ) {
				$text = $text.$line[0].": ".$statline[0]."; ";
				$criticals++;
			}
		}
	}
}

if (defined($opt_s)) {
	$context = "System Initialization";

	my @sysinit = $t->cmd("showstatus");

	foreach my $sys (@sysinit) {
		chomp $sys;

		if (!($sys =~ /No failures found in System Initialization./)) {
			$text = $text.$sys."; ";
			$criticals++;
		}
	}
}

if ($criticals >= 1) {
	print "CRITICAL: ".$context.": ".$text, "\n";
	exit (2);
}
elsif ($warnings >= 1) {
	print "WARNING: ".$context.": ".$text, "\n";
	exit (1);
}
else {
	print "OK: $context normal\n";
	exit (0);
}
