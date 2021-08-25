#!/usr/bin/perl

# cmd.pl - executes simple URL-based transactions with a FortiManager instance
#
# by Oliver Jones - v1.07
# Last revision: 20.08.2021
#
# Preparation, to ensure the API can be found by the Perl interpreter:
# % export PERL5LIB=/path/to/Fortinet.pm
#
# Usage: cmd.pl [-hostname] [-session] [-id] [-method] [-url] [-params] [-data] [-echo] [-status]
#
# [-hostname]   : Host name  of FortiManager instance to connect to. Retrieved automatically from FORTINET_HOSTNAME environment variable, if present.
# [-insecure]   : Explicitly disable SSL/TLS host/certificate check. Retrieved automatically from FORTINET_INSECURE environment variable, if present.
# [-session]    : Session ID of FortiManager instance to connect to. Retrieved automatically from FORTINET_SESSION  environment variable, if present.
# [-id]         : Transaction ID to begin with (defaults to 1). Optional.
# [-method]     : Fortinet method. Can be exec, add, get, set or delete.
# [-url]        : URL block. Semi-optional. Can be used instead of [-p|--params] when a URL value or array is included as the URL.
# [-params]     : Params block. Semi-optional. Can be used instead of [-u|--url] when a URL key-value pair is included in the params block.
# [-data]       : Data block. Optional.
# [-verbose]    : Controls verbosity of API: Can be enabled or disabled (the default if not specified.) If enabled, all JSON transactions are displayed.
# [-echo]       : Controls output of JSON data structures. Can be 'request', 'result', 'all' or 'off' (the default, if not provided.)
# [-status]     : Controls output of API status structure.
#
# URLs can be a simple string, or a JSON structure. Params and/or data blocks must be JSON structures, if present (these are decoded, and fed straight to the API.)
# This means that url, params and data blocks can also be arrays of objects, as long as the number and type of arguments between URL, params and data blocks match.
#
# Examples:
#
# Simple retrieval of a URL (getting the system status), with both request and result displayed:
# % cmd.pl -m get -u 'sys/status' -e all
#
# Simple retrieval of a URL (as above), with just a parameter block specified (URLs are normally written into the parameter block for convenience, if specified separately.)
# % cmd.pl -m get -p '{"url" : "sys/status"}' -e all
#
# Complex retrieval of several URLs (system status and metrics), simultaneously, with request and result displayed, plus internal API status variables:
# % cmd.pl -m get -u '["/cli/global/system/status", "/cli/global/system/performance", "/cli/global/system/global", "/cli/global/system/interface"]' -e all -status
#
# Simple setting of a URL (creating an IPv4 policy rule), with separate URL and data blocks supplied:
# % cmd.pl -m set -u 'pm/config/adom/muppetlabs/pkg/bunsen_root/firewall/policy' \
# -d '{"action" : 1, "srcintf" : ["zone1"], "dstintf" : ["zone2"], "srcaddr" : ["all"], "dstaddr" : ["all"], "service" : ["PING"], "nat" : 0, "schedule" : ["always"] }'
#
# Simple setting of a URL (creating an IPv4 address object), with separate URL and data blocks supplied:
# % cmd.pl -m set -u '/pm/config/adom/muppetlabs/obj/firewall/address' \
# -d '{"name" : "honeydew", "associated-interface" : ["any"], "subnet" : ["10.0.0.0","255.0.0.0"]}' -e all
#
# Simple setting of a URL (creating a custom service object), with separate URL and data blocks supplied:
# % cmd.pl -m set -u 'pm/config/adom/muppetlabs/obj/firewall/service/custom' \
# -d '{"name" : "RDP", "iprange" : "0.0.0.0", "tcp-portrange" : ["3389"], "protocol" : 5, "category" : ["Remote Access"]}' -e all
#
# Complex setting of several URLs (creating custom service objects, condensed for brevity), simultaneously, with respective data blocks supplied:
# % cmd.pl -m set -u '["pm/config/adom/muppetlabs/obj/firewall/service/custom", "pm/config/adom/muppetlabs/obj/firewall/service/custom"]' \
# -d '[{"name" : "tcp-49152-53247", "tcp-portrange" : "49152-53247", ...}, {"name" : "udp-49152-53247", "udp-portrange" : "49152-53247", ...}]' -e all
#
# Simple deletion of a URL (deleting the IPv4 policy rule with ID 123), with just a URL supplied:
# % cmd.pl -m delete -u 'pm/config/adom/muppetlabs/pkg/bunsen_root/firewall/policy/123'
#
# Simple deletion of a URL (deleting the IPv4 address object named honeydew), with just a URL supplied:
# % cmd.pl -m delete -u 'pm/config/adom/muppetlabs/obj/firewall/address/honeydew'
#
# Simple deletion of a URL (deleting the custom service object named RDP), with just a URL supplied:
# % cmd.pl -m delete -u 'pm/config/adom/muppetlabs/obj/firewall/service/custom/RDP'
#
# Execution of a URL (locking the workspace for a VDOM, committing changes to a locked VDOM and releasing the lock on a VDOM), with just a URL supplied:
# % cmd.pl -m exec -u 'pm/config/adom/muppetlabs/_workspace/lock'
# % cmd.pl -m exec -u 'pm/config/adom/muppetlabs/_workspace/commit'
# % cmd.pl -m exec -u 'pm/config/adom/muppetlabs/_workspace/unlock'
#
# Execution of a URL (deployment of a named policy package), with a respective data block supplied:
# % cmd.pl -m exec -u '/securityconsole/install/package' \
# -d '{"adom" : "muppetlabs", "adom_rev_comments" : "Mimimi", "adom_rev_name" : "v1.0", "pkg" : "bunsen_root", "scope" : {"name" : "bunsen", "vdom" : "root"}}' -e all

use strict;
use warnings;
use Getopt::Long;
use Fortinet;
use JSON;

my (%option, $fortinet);

# Get options from the command line
GetOptions(\%option, 'hostname=s', 'insecure', 'session=s', 'id=i', 'method=s', 'url=s', 'params=s', 'data=s', 'verbose', 'echo=s', 'status');

# Get defaults from environment variables, if present
$option{'hostname'} = $option{'hostname'} // $ENV{'FORTINET_HOSTNAME'};
$option{'session'}  = $option{'session'}  // $ENV{'FORTINET_SESSION'};
$option{'id'}       = $option{'id'}       // $ENV{'FORTINET_ID'};
$option{'verbose'}  = $option{'verbose'}  // $ENV{'FORTINET_VERBOSE'};
$option{'echo'}     = $option{'echo'}     // $ENV{'FORTINET_ECHO'};

# If the insecure option is set via environment variable, it will override the specified option; this will generate a warning
if (!defined($option{'insecure'}) && defined($ENV{'FORTINET_INSECURE'}) && $ENV{'FORTINET_INSECURE'} == 1)
    {
    # Warn user if they have not explicitly requested insecure operation, but if this setting has been inherited from an environment variable
    print STDERR "Warning: SSL/TLS override was not explicitly requested by option, but has been inherited from a prior enabled environment variable.\n";

    # Set SSL/TLS insecure mode
    $option{'insecure'} = 1;
    }

# Check everything required is present
if (!defined($option{'hostname'}) || !defined($option{'session'}) || (!defined($option{'url'}) && !defined($option{'params'})))
    { die 'Hostname, session ID and URL and/or params are required'; }

# Configure JSON
my $json = JSON->new();
$json->canonical(1);

# Evaluate url, param and data arguments
foreach my $param ('url', 'params', 'data')
    {
    # Check if argument was supplied
    if (defined($option{$param}))
        {
        # Check if argument is valid JSON
        if (eval { $json->decode($option{$param}); })
            {
            # Decode JSON argument
            $option{$param} = $json->decode($option{$param});
            }
        else
            {
            # Check if the argument required JSON
            if ($param eq 'params' || $param eq 'data')
                { die 'JSON parse failed for supplied '.$param.' block'; }
            }
        }
    }

# Attempt to start Fortinet instance
if (eval { $fortinet = Fortinet->new(%option); })
    {
    # Create new request for the parameters specified
    my $return = $fortinet->request(%option);

    # Handle status functionality
    if ($option{'status'})
        {
        # Print API status structure
        print "# Fortinet API status:\n".$json->pretty->encode($fortinet->{'status'});
        }

    # Handle error after diagnostics have been output
    if (!$return) { die ($fortinet->{'status'}{'json'}{'message'} // ($fortinet->{'status'}{'http'}{'message'} // 'Catastrophic malfunction')); }

    # Successful exit
    exit (0);
    }

# Handle errors
else { die $@; }
