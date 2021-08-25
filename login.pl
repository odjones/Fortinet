#!/usr/bin/perl

# login.pl - Logs in to a FortiManager instance
#
# by Oliver Jones - v1.07
# Last revision: 20.08.2021
#
# Preparation, to ensure the API can be found by the Perl interpreter:
# % export PERL5LIB=/path/to/Fortinet.pm
#
# Usage: login.pl [-hostname] [-username] [-password] [-autoexec]
#
# [-hostname]   : Hostname of the FortiManager appliance to connect to. Retrieved automatically from FORTINET_HOSTNAME environment variable, if present.
# [-username]   : Username of the FortiManager account, to log in with. Retrieved automatically from FORTINET_USERNAME environment variable, if present.
# [-password]   : Password of the FortiManager account, to log in with. Retrieved automatically from FORTINET_PASSWORD environment variable, if present.
# [-insecure]   : Disable all future SSL/TLS host/certificate checks when connecting to this server. Useful for development; not advised for production.
# [-autoexec]   : Command or script to execute when login is complete. Optional. If this argument is not supplied, an interactive shell will be spawned.
# [-verbose]    : Controls verbosity of API: Can be enabled or disabled (the default if not specified.) If enabled, all JSON transactions are displayed.
# [-echo]       : Controls output of JSON data structures. Can be one of 'request', 'result', 'all', 'none' (or 'unset' - the default if not specified.)
#
# Successful login will set the authenticated session ID as the FORTINET_SESSION environment variable - and the FortiManager hostname as FORTINET_HOSTNAME -
# in a new spawned shell, with the next transaction ID set as FORTINET_TRANSACTION_ID. Once command execution has completed - and the spawned shell has been
# terminated - logout from the FortiManager instance is handled automatically: An explicit logout is not required.
#
# Example:
#
# Logs in, shows set Fortinet environment variables in the new shell, and then immediately logs out:
# % read -s PASSWORD
# % login.pl -hostname bunsen.muppetlabs.com -username beaker -password ${PASSWORD} -autoexec 'env | grep "^FORTINET_"'

use strict;
use warnings;
use Getopt::Long;
use Fortinet;

my (%option, $fortinet);

# Get options from the command line
GetOptions(\%option, 'hostname=s', 'username=s', 'password=s', 'insecure', 'autoexec=s', 'verbose', 'echo=s');

# Get defaults from environment variables, if present
$option{'hostname'} = $option{'hostname'} // $ENV{'FORTINET_HOSTNAME'};
$option{'username'} = $option{'username'} // $ENV{'FORTINET_USERNAME'};
$option{'password'} = $option{'password'} // $ENV{'FORTINET_PASSWORD'};

# If the insecure option is set via environment variable, it will override the specified option; this will generate a warning
if (!defined($option{'insecure'}) && defined($ENV{'FORTINET_INSECURE'}) && $ENV{'FORTINET_INSECURE'} == 1)
    {
    # Warn user if they have not explicitly requested insecure operation, but if this setting has been inherited from an environment variable
    print STDERR "Warning: SSL/TLS override was not explicitly requested by option, but has been inherited from a prior enabled environment variable.\n";

    # Set SSL/TLS insecure mode
    $option{'insecure'} = 1;
    }

# Attempt to start Fortinet instance with given hostname, username and password
if (eval { $fortinet = Fortinet->new(%option); })
    {
    # If username and/or password are defined as environment variables, delete them for this shell
    if (defined($ENV{'FORTINET_USERNAME'}) && length($ENV{'FORTINET_USERNAME'}) > 0) { delete $ENV{'FORTINET_USERNAME'}; }
    if (defined($ENV{'FORTINET_PASSWORD'}) && length($ENV{'FORTINET_PASSWORD'}) > 0) { delete $ENV{'FORTINET_PASSWORD'}; }

    # Export hostname, session ID and transaction ID
    $ENV{'FORTINET_HOSTNAME'} = $fortinet->{'hostname'};
    $ENV{'FORTINET_SESSION'}  = $fortinet->{'session'};
    $ENV{'FORTINET_ID'}       = $fortinet->{'id'};

    # Export verbosity flag (none if not specified)
    $ENV{'FORTINET_VERBOSE'}  = $fortinet->{'verbose'} // 0;

    # Export echo option (unset if not specified)
    $ENV{'FORTINET_ECHO'}     = $option{'echo'} // 'unset';

    # Handle login notification for interactive sessions
    if (!defined($option{'autoexec'}) && (defined($option{'verbose'}) && $option{'verbose'} == 1))
        { print "Login successful with session ".$fortinet->{'session'}."\nPlease exit this shell to log out.\n"; }

    # Check SSL/TLS security setting
    if ($fortinet->{'secured'} == 0)
        {
        # Export insecure option for subsequent connections
        $ENV{'FORTINET_INSECURE'} = $fortinet->{'insecure'};
        }

    # Run autoexec specification or spawn a new shell
    system ($option{'autoexec'} // $ENV{'SHELL'});

    # Handle logout notification for interactive sessions
    if (!defined($option{'autoexec'}) && (defined($option{'verbose'}) && $option{'verbose'} == 1))
        { print "Logging out...\n"; }
    }

# Handle errors
else { die $@; }
