#!/usr/bin/env perl

# Copyright 2016, Jernej Kovacic
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



#
# About
#
# The script removes old kernel images and headers on Ubuntu based
# Linux distributions. Only the current and previous kernel are kept.
# The script must be run with super user privileges, i.e.
# prefixed with sudo.
#
# From a shell, run the script as:
#     sudo perl /path/to/rmoldkrnl.pl
#
# USE AT YOUR OWN RISK!
#


use strict;
use warnings;



remove_old_kernels();



# === IMPLEMENTATION OF SUBROUTINES ===

sub remove_old_kernels
{
    # The subroutine is an equivalent of the following sequence of commands:
    #
    # uname -r
    # dpkg --list | grep linux-
    # sudo apt-get purge -y linux-image-x.x.x-x-generic
    # sudo apt-get purge -y linux-headers-x.x.x-x-generic
    # sudo apt-get purge -y linux-headers-x.x.x-x
    #
    # For more details see:
    # https://help.ubuntu.com/community/Lubuntu/Documentation/RemoveOldKernels


    # Paths to system commands. Feel free to edit them if they are installed
    # in other directories:
    my $CMD_UNAME = "/bin/uname";
    my $CMD_DPKG = "/usr/bin/dpkg";
    my $CMD_APTGET = "/usr/bin/apt-get";

    # parameters to apt-get to remove the selected package
    my $PARAM_APTGET_PURGE = "purge -y";

    # Regex pattern of the kernel version (eg. '3.13.0-16'):
    my $VER_PATTERN = '(\d+\.\d+\.\d+\-\d+)';


    # The script can only be run on Linux
    eval { "linux" eq $^O } || die "The script can only be run on Linux!\n";


    # Root privileges are required to remove old kernel images
    eval { 0 == $< } || die "The script requires root privileges!\n";



    # uname -r
    my $full_version_str = qx/$CMD_UNAME -r/;

    # Obtain the current kernel version (without the suffix -generic):
    my $ver_pattern = '^' . $VER_PATTERN . '\-generic$';
    my $re_ver = qr/$ver_pattern/;
    $full_version_str =~ $re_ver || die "Invalid version!\n";
    my $version = $1;
    print "Current kernel: $version\n";


    # This section runs 'dpkg -l linux-*'
    # and "greps" for all installed packages whose names start with
    # 'linux-image-' or 'linux-headers-'.
    # Kernel version is extracted from such package names and stored
    # into a hash (here used as a set with unique entries).

    my %kernels = ();
    my @results = qx/$CMD_DPKG -l linux-*/;

    # Prepare the regex to extract kernel version from appropriate package names:
    my $pkg_ver_pattern = '^ii\s+(linux\-(image|headers)\-' . $VER_PATTERN . ')';
    my $re_pkgver = qr/$pkg_ver_pattern/;

    # Iterate through all lines returned by dpkg -l
    for my $res (@results)
    {
        # Exclude all "unusual" lines...
        next if (length($res)<3 || substr($res, 0, 3) ne "ii ");

        # ...and those that do not match the regex
        $res =~ m/$re_pkgver/ || next;

        # From the matching lines extract the kernel version
        my $ver = $3;

        # If the version is greater than the current one, the OS should be restarted first
        eval { 1 != cmp_versions($ver, $version) } ||
                  die "Reboot the system and run this script again!\n";

        # ...and push the version into the hash with unique versions
        # Note: only the hash's keys are important here.
        $kernels{ $ver } = 0;
    }


    # The next section will iterate through the hash with keys sorted
    # in ascending order. It will attempt to remove all old kernels and headers
    # except the current and the previous one.

    # Size of the hash
    my $N = keys %kernels;

    # An additional counter of iterations is necessary
    my $cntr = 0;

    # Iterate the sorted (in asc. order) list of "keys":
    for my $k ( sort cmp_versions keys %kernels )
    {
        # Increment the counter
        ++$cntr;

        # Skip the rest of the loop if the kernel is current or previous.
        # Additionally check for the current kernel version just to avoid
        # removing the current kernel by accident.

        if ( $version eq $k  ||  $cntr > ($N-2) )
        {
            print "Keeping kernel $k\n";
        }
        else
        {
            print "Kernel $k will be removed...\n";

            # Compose package names to be removed:
            my $imggen_pkg = "linux-image-" . $k. "-generic";
            my $headgen_pkg = "linux-headers-" . $k . "-generic";
            my $head_pkg = "linux-headers-" . $k;

            # and finally remove the packages:
            print "  removing $imggen_pkg\n";
            qx/$CMD_APTGET $PARAM_APTGET_PURGE $imggen_pkg/;
            print "  removing $headgen_pkg\n";
            qx/$CMD_APTGET $PARAM_APTGET_PURGE $headgen_pkg/;
            print "  removing $head_pkg\n";
            qx/$CMD_APTGET $PARAM_APTGET_PURGE $head_pkg/;
        }

    }

}



sub cmp_versions($$)
{
    # This subroutine compares two version strings. Instead of a simple
    # string comparison, the strings are decomposed into sequences of four
    # integers that are subsequently compared element wise. Each string
    # must be in the "x.y.w-z" format.
    #
    # The subroutine returns -1 if $a<$b, 0 if the strings are equal,
    # or 1 if $a>$b

    # check that at least two arguments are passed
    my $N = @_;
    eval { 2 <= $N } || die "Invalid number of parameters!";

    # "Extract" both arguments
    my $a = $_[0];
    my $b = $_[1];

    # Prepare the regex to extract all numeric values from arguments' sequences
    my $re_ver = qr/(\d+)\.(\d+)\.(\d+)\-(\d+)/;

    # and extract the numeric values and store them into arrays @arra nad @arrb:
    $a =~ m/$re_ver/ || die "Invalid format!";
    my @arra = ( $1, $2, $3, $4 );
    $b =~ m/$re_ver/ || die "Invalid format!";
    my @arrb = ( $1, $2, $3, $4 );

    # The for loop iterates both arrays until elements at the same positions
    # are different. Those elements are then compared and $retval
    # is set appropriately.

    # Default value of $retval for the case when $a==$b
    my $retval = 0;
    for ( my $i=0; $i<4; ++$i )
    {
        if ( $arra[$i] ne $arrb[$i] )
        {
            # if elements at the position $i are not equal
            # compare them and exit the loop immmediately.

            $retval = ( $arra[$i] < $arrb[$i] ) ? -1 : 1;
            last;
        }
    }

    return $retval;
}
