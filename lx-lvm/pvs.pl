#!/usr/bin/env perl
#******************************************************************************
# @(#) pvs.pl
#******************************************************************************
# @(#) Copyright (C) 2016 by KUDOS BVBA <info@kudos.be>.  All rights reserved.
#
# This program is a free software; you can redistribute it and/or modify
# it under the same terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details
#******************************************************************************
# This script will display HP-UX LVM information in Linux style
# 
# Based on https://jreypo.wordpress.com/2010/02/16/linux-lvm-commands-in-hp-ux/
#
# @(#) HISTORY: see perldoc 'pvs.pl'
# -----------------------------------------------------------------------------
# DO NOT CHANGE THIS FILE UNLESS YOU KNOW WHAT YOU ARE DOING!
#******************************************************************************

#******************************************************************************
# PRAGMA's & LIBRARIES
#******************************************************************************

use strict;
use warnings;
use POSIX qw(uname);
use Getopt::Long;
use Pod::Usage;
$|++;


#******************************************************************************
# DATA structures
#******************************************************************************

my ($os, $version, $footer);
my %options;
my (@pvol, @vgdisplay);


#******************************************************************************
# SUBroutines
#******************************************************************************

sub parse_pvols {

    my @pvol = @_;
	my @pvdisplay;

	unless (@pvol) {
		print "-- no disks found --\n";
		return;
	}
	
	foreach my $pvol (@pvol) {

		my $pv_lvm = 1;
	
		chomp ($pvol);
	
		@pvdisplay = `/usr/sbin/pvdisplay -F /dev/disk/${pvol} 2>&1`;
		$pv_lvm = 0 if ($?) and (grep (/cannot display physical volume/i, @pvdisplay));
    
		# loop over pvdisplay
		if ($pv_lvm) {
    
			foreach my $pv_entry (@pvdisplay) {
        
				my ($vg_name, $pv_status)= ("","");
				my ($pv_total_pe, $pv_size_pe, $pv_free_pe, $pv_stale_pe) = (0,0,0,0);
				my ($pv_size, $pv_free) = (0,0);
    
				my @pv_data = split (/:/, $pv_entry);

				# loop over PVOL data
				foreach my $pv_field (@pv_data) {

					$vg_name     = $1 if ($pv_field =~ m%^vg_name=/dev/(.*)%);
					$pv_status   = $1 if ($pv_field =~ m%^pv_status=(.*)%);
					$pv_total_pe = $1 if ($pv_field =~ m%^total_pe=(.*)%);
					$pv_size_pe  = $1 if ($pv_field =~ m%^pe_size=(.*)%);
					$pv_free_pe  = $1 if ($pv_field =~ m%^free_pe=(.*)%);
					$pv_stale_pe = $1 if ($pv_field =~ m%^stale_pe=(.*)%);
				}
				# calculate sizes
				$pv_size = $pv_total_pe * $pv_size_pe;
				$pv_size /= 1024 unless ($options{'size'} =~ /MB/i);            
				$pv_free = $pv_free_pe * $pv_size_pe;
				$pv_free /= 1024 unless ($options{'size'} =~ /MB/i);

				# report data
				printf STDOUT ("%-20s %-12s %-15s %-7d %-8d %-8d %-8d\n",
					"/dev/disk/${pvol}",
					${vg_name},
					${pv_status},
					${pv_size_pe},
					${pv_size},
					${pv_free},
					${pv_stale_pe})
			}
		} else {
			unless ($options{'active'}) {
				printf STDOUT ("%-20s %-12s %-15s\n", "/dev/disk/${pvol}",
					"n/a",
					"not active/not LVM");
			}
		}
	}
}


#******************************************************************************
# MAIN routine
#******************************************************************************

# where and what am I?
die ("ERROR: must be invoked as root\n") if ($<);
($os, $version) = (uname())[0,2];
die ("ERROR: only runs on HP-UX v11.31") unless ($os eq 'HP-UX' and $version eq 'B.11.31');

# process command-line options
if ( @ARGV > 0 ) {
    Getopt::Long::Configure('prefix_pattern=(--|-|\/)', 'bundling', 'no_ignore_case');
    GetOptions( \%options,
            qw(
                help|h|?
                size|s=s
                vg|g=s
				active|a
            ));
}
# check options
if ($options{'help'}) {
    pod2usage(-verbose => 3);
    exit (0);
};
unless ($options{'size'}) {
    $options{'size'} = 'GB';
};

# print header
printf STDOUT ("\n%-20s %-12s %-15s %-7s %-8s %-8s %-8s\n", 
        "PV", "VG", "Status", "PE Size", "PV Size", "PV Free", "Stale PE");

# fetch PVOLs (non-boot)
if ($options{'vg'}) {
    @pvol = `/usr/sbin/vgdisplay -vF "/dev/${options{'vg'}}" 2>/dev/null | grep "^pv_name"  | cut -f1 -d':' | cut -f2 -d'=' | cut -f4 -d '/'`;
	die "failed to execute: $!" if ($?);
	parse_pvols (@pvol);
} else {
    @pvol = `/usr/sbin/ioscan -kFN -C disk 2>/dev/null | cut -f9,13 -d':' | tr -d ':'`; 
	die "failed to execute: $!" if ($?);
	parse_pvols (@pvol);
	
	# fetch PVOLs (boot)
	print "\n-- Boot disk(s):\n";
	@pvol = `/usr/sbin/lvlnboot -v 2>/dev/null | grep 'Boot Disk' | awk '{ print \$1 }' | cut -f4 -d '/'`;
	die "failed to execute: $!" if ($?);
	parse_pvols (@pvol);
}

# footer
$footer = qq{
Note 1: 'PE Size' values are expressed in MB
Note 2: 'PV Size' & 'PV Free' values are expressed in GB by default (see --help)
Note 3: more detailed information can be obtained by running the pvdisplay(1M), vgdisplay(1M), lvdisplay(1M) commands

};
print STDOUT $footer;

exit (0);

#******************************************************************************
# End of SCRIPT
#******************************************************************************
__END__
#******************************************************************************
# POD
#******************************************************************************

# -----------------------------------------------------------------------------

=head1 NAME

pvs.pl - Show physical volume information in a terse way (Linux style).

=head1 SYNOPSIS

    pvs.pl [-h|--help] 
           [(-g|--vg)=<vg_name>]
           [(-s|--size)=<MB|GB>]
		   [(-a|--active)]

=head1 OPTIONS

=over 2

=item -h | --help

S<       >Show the help page.

=item -a | --active

S<       >Hide non-active and non-LVM disks

=item -g | --vg

S<       >Display physical volumes for a specific volume group. Volume group name should be specified without the "/dev/" prefix

=item -s | --size

S<       >Show physical volume size in MB or GB (default is GB).

=head1 AUTHOR

(c) KUDOS BVBA - Patrick Van der Veken

=head1 history

@(#) 2016-04-12: VRF 1.0.0: first version [Patrick Van der Veken]
@(#) 2016-04-27: VRF 1.0.1: small fixes [Patrick Van der Veken]
@(#) 2016-04-27: VRF 1.1.0: show all PVOLs & option --active added [Patrick Van der Veken]