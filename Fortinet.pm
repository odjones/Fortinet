#!/usr/bin/perl

# Fortinet.pm - provides basic FortiManager JSON API abstraction
#
# by Oliver Jones - v1.07
# Last revision: 20.08.2021
#
# To install required package dependencies (on RHEL / CentOS / Rocky Linux), use:
# yum -y install perl perl-LWP-Protocol-https perl-JSON

package Fortinet;

use strict;
use warnings;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;
use Carp;

# Class constructor
#
# Must be called with sufficient arguments to authenticate to a FortiManager appliance.
# This can be one of two ways:
#
# $x->new
#   (
#   'hostname'      => 'Host name or IP address',
#   'username'      => 'Account username',
#   'password'      => 'Account password'
#   );
#
# Or:
#
# $x->new
#   (
#   'hostname'      => 'Host name or IP address',
#   'session'       => 'Existing session ID'
#   );
#
# It is possible to provide both a session ID and a username / password pair. (In the event both are provided, the session ID is tried first.)
# If authentication with the session ID is unsuccessful, the username / password pair will be used to establish a new session.
#
# Additional options:
#
#   'insecure'      => 1            This will disable SSL/TLS host/certificate checks when attempting to connect. (Not for use in production.)
#   'verbose'       => 1            This will output a copy of every JSON request and response to the terminal. (Mainly useful for debugging.)
#   'echo'          => 'value'      Overrides verbose flag for JSON requests and/or responses. Can be 'all', 'request', 'response' or 'none'.
#   'id'            => integer      This will specify a transaction ID to start from (normally set to 1 by default.)
#
# Upon successful initialisation, the following variables may be used:
#
# $x->{'status'}{'http'}            This contains {'code'} for the HTTP error code, and {'message'} for a description of the HTTP error state.
# $x->{'status'}{'json'}            This contains {'code'} for the JSON error code, and {'message'} for a description of the JSON error state.
# $x->{'result'}                    This contains a structure converted from the JSON result. (Initially, the result for the sys/status call.)
#
# Any authentication errors will usually terminate the calling program. It is possible to trap this using eval(), for graceful error handling.

sub new
    {
    my ($class, %argument) = @_;
    my $self =
        {
        hostname => $argument{'hostname'},
        username => $argument{'username'},
        password => $argument{'password'},
        insecure => $argument{'insecure'},
        session  => $argument{'session'},
        verbose  => $argument{'verbose'} // 0,
        echo     => $argument{'echo'} // 'unset',
        id       => $argument{'id'} // 1,
        browser  => LWP::UserAgent->new,
        secured  => 1,
        json     => JSON->new,
        login    => 0,
        result   => {},
        status   => {'http' => {}, 'json' => {}}
        };

        my $object = bless $self, $class;
        my $result = undef;

        # Enable sorting of keys when encoding JSON
        $self->{'json'}->canonical(1);

        # A hostname, username and password - or hostname and session ID are required
        if (!defined($self->{'hostname'}) || ((!defined($self->{'username'}) || !defined($self->{'password'})) && !defined($self->{'session'})))
            { croak 'Hostname and either username and password or session ID are required'; }

        # Check if SSL/TLS host/certificate checks should be ignored
        if (defined($self->{'insecure'}) && $self->{'insecure'} == 1)
            {
            # Permanently note this status
            $self->{'secured'} = 0;
            }

        # Check if a session ID exists
        if (defined($self->{'session'}))
            {
            # Perform a test operation, to check if the session ID is still valid
            $result = $self->request
                (
                'method' => 'get',
                'url'    => 'sys/status',

                # Hide output unless verbose is set and not overridden
                'echo'   => $self->{'verbose'} == 1 && $self->{'echo'} eq 'unset' ? 'unset' : 'none'
                );
            }

        # If a session ID does not exist, or is stale - but a username and password have also been specified, a login will now be attempted
        if ((!defined($result) || (defined($result) && !$result)) && defined($self->{'username'}) && defined($self->{'password'}))
            {
            # Attempt a login with the specified username and password
            $result = $self->request
                (
                'method' => 'exec',
                'url'    => 'sys/login/user',
                'data'   =>
                    {
                    'user'   => $self->{'username'},
                    'passwd' => $self->{'password'}
                    },

                # Hide output unless verbose is set and not overridden
                'echo'   => $self->{'verbose'} == 1 && $self->{'echo'} eq 'unset' ? 'unset' : 'none'
                );

            # Save session key, if it exists
            $self->{'session'} = $self->{'result'}{'session'} // undef;

            # Flag login attempt
            $self->{'login'} = 1;
            }

    # If a session ID still doesn't exist, or there is an undefined (or error) condition, abort now
    if (!defined($self->{'session'}) || (!defined($result) || (defined($result) && !$result)))
        { croak $self->{'status'}{'json'}{'message'} // ($self->{'status'}{'http'}{'message'} // 'Catastrophic malfunction'); }

    return ($object);
    }

# request() method
#
# Sends a new JSON API request to a FortiManager appliance.
# This can be one of two ways:
#
# $x->request
#   (
#   'method'        => 'Method type',
#   'url'           => 'URL'/['URL']
#   );
#
# Or:
#
# $x->request
#   (
#   'method'        => 'Method type',
#   'params'        => {Param}/[{Param}]
#   );
#
# It is possible to provide both a URL and method - in which case the specified URL will overwrite any specified in the method. If a method is
# supplied, it must contain a URL. URL and data blocks are for convenience: They can be omitted if a complete param block is submitted instead
# (the end result will be the same, as any URL and data blocks are simply copied into a blank param block if one is not specified.)
#
# Additional options:
#
#   'data'          => {Data}/[{Data}]   This will supply a data block to be wrapped in the param block. (Overwrites the existing data block.)
#   'echo'          => 'option'          This will override global verbosity settings. Valid options: 'all', 'none', 'request' and 'response'.
#
# Excepting the method argument, all other arguments must match type and count. Thus, if an array of three elements is passed as URL, then all
# other arguments supplied must also consist of an array of three elements: Supplying a hash in one, and an array of one in another will fail.
#
# This method returns 1 in the event of successful execution, or 0 in the event of any error at the HTTP or JSON level.
#
# After execution, the following variables may be used:
#
# $x->{'status'}{'http'}            This contains {'code'} for the HTTP error code, and {'message'} for a description of the HTTP error state.
# $x->{'status'}{'json'}            This contains {'code'} for the JSON error code, and {'message'} for a description of the JSON error state.
# $x->{'status'}{'json'}{'vector'}  In the event of multiple URLs used in one request, this will contain a hash organised by URL, with offset.
# $x->{'status'}{'json'}{'detail'}  In the event of multiple URLs used in one request, this will contain an array, with a result for each URL.
# $x->{'result'}                    This contains a structure converted from the JSON result. (Initially, the result for the sys/status call.)

sub request
    {
    my ($self, %argument) = @_;
    my $method = $argument{'method'};
    my $url    = $argument{'url'};
    my $params = $argument{'params'};
    my $data   = $argument{'data'};
    my $echo   = $argument{'echo'} // 'unset';

    # Set reasonable defaults
    $self->{'result'} = {};
    $self->{'status'} =
        {
        'http' =>
            {
            'code'    => -1,
            'message' => 'Could not POST to https://'.$self->{'hostname'}.'/jsonrpc'
            },
        'json' =>
            {
            'code'    => -1,
            'message' => undef
            }
        };

    # A method and URL or parameter block is required
    if (!defined($method) || (!defined($url) && !defined($params)))
        { croak 'Method and URL or parameter block are required'; }

    # Check if multiple parameters have been given in arrays
    if (ref($params) eq 'ARRAY' || ref($url) eq 'ARRAY' || ref($data) eq 'ARRAY')
        {
        # Check data types for consistency
        if ((ref($params // []) ne 'ARRAY' || ref($url // []) ne 'ARRAY' || ref($data // []) ne 'ARRAY')
        ||  (defined($params) && defined($url)  && $#{$params} != $#{$url})
        ||  (defined($params) && defined($data) && $#{$params} != $#{$data})
        ||  (defined($url)    && defined($data) && $#{$url}    != $#{$data}))
            { croak 'URL, data and parameter blocks must be of consistent type and number of elements'; }

        # Initialise parameter block if not present
        if (!defined($params)) { $params = []; }

        # Wrap URL in parameter block, if present
        if (defined($url))
            {
            # Copy each index
            for (my $index = 0; $index < $#{$url} + 1; $index++)
                { $params->[$index]{'url'} = $url->[$index]; }
            }

        # Wrap data in array in parameter block, if present
        if (defined($data))
            {
            # Copy each index
            for (my $index = 0; $index < $#{$data} + 1; $index++)
                { $params->[$index]{'data'} = [$data->[$index]]; }
            }
        }
    else
        {
        # Wrap URL in parameter block, if present
        if (defined($url)) { $params->{'url'} = $url; }

        # Wrap data in array in parameter block, if present
        if (defined($data)) { $params->{'data'} = [$data]; }
        }

    # Set up request structure
    my $structure =
        {
        'method' => lc $method,
        'params' => ref($params) eq 'ARRAY' ? $params : [$params],
        'id'     => $self->{'id'}++
        };

    # Add the session ID if it exists
    if (defined($self->{'session'})) { $structure->{'session'} = $self->{'session'}; }

    # Handle verbose output if enabled
    if (($self->{'verbose'} == 1 && uc $echo eq 'UNSET') || $echo =~ m/^(REQUEST|ALL)$/i)
        {
        # Print header only if user has not selected specific output
        if ($echo =~ m/^(UNSET|ALL)$/i)
            { print "# Request:\n"; }

        # Print request structure
        print $self->{'json'}->pretty->encode($structure);
        }

    # Check for SSL/TLS override
    if ($self->{'secured'} == 0)
        {
        # Instruct LWP:UserAgent to ignore SSL checks for this connection
        $self->{'browser'}->ssl_opts('verify_hostname' => 0, 'SSL_verify_mode' => 0x00);
        }

    # Formulate a new request
    my $request = POST 'https://'.$self->{'hostname'}.'/jsonrpc',
        Content_Type => 'application/json',
        Content      => $self->{'json'}->encode($structure);

    # Send request to the HTTP client
    my $result = $self->{'browser'}->request($request);

    # Retrieve HTTP status
    $self->{'status'}{'http'} =
        {
        'code'    => $result->{'_rc'},
        'message' => $result->{'_msg'}
        };

    # Check for success at the HTTP level
    if (($self->{'status'}{'http'}{'code'} // -1) >= 200 && ($self->{'status'}{'http'}{'code'} // -1) <= 299)
        {
        # Decode JSON result
        if (eval { $self->{'result'} = $self->{'json'}->decode($result->{'_content'}); })
            {
            # Handle verbose output if enabled
            if (($self->{'verbose'} == 1 && uc $echo eq 'UNSET') || $echo =~ m/^(RESPONSE|ALL)$/i)
                {
                # Print header only if user has not selected specific output
                if ($echo =~ m/^(UNSET|ALL)$/i)
                    { print "# Response:\n"; }

                # Print response structure
                print $self->{'json'}->pretty->encode($self->{'result'});
                }

            # Check for multiple result blocks
            if (ref($self->{'result'}{'result'}) eq 'ARRAY' && $#{$self->{'result'}{'result'}} > 0)
                {
                # Error count
                my $error = 0;

                # Initialise result detail array
                $self->{'status'}{'json'}{'detail'} = [];

                # Process each result index
                for (my $index = 0; $index < $#{$self->{'result'}{'result'}} + 1; $index++)
                    {
                    # Copy each index, if it exists, in the same order it appeared in the response
                    $self->{'status'}{'json'}{'detail'}[$index] = $self->{'result'}{'result'}[$index]{'status'} // {'code' => -1, 'message' => 'No status available'};

                    # Add URL vectoring
                    $self->{'status'}{'json'}{'vector'}{($self->{'result'}{'result'}[$index]{'url'} // 'unknown_url').
                    ($method =~ m/^(ADD|SET)$/i ? '/'.($data->[$index]{'name'} // '['.$index.']') : '')} = $index;

                    # Track cumulative errors
                    $error += (($self->{'result'}{'result'}[$index]{'status'}{'code'} // -1) == 0 ? 0 : 1);
                    }

                # Populate overview status code and message fields
                $self->{'status'}{'json'}{'code'} = $error == 0 ? 0 : -1;
                $self->{'status'}{'json'}{'message'} = $error == 0 ? 'All URLs were processed successfully' : $error.' URL'.($error == 1 ? ' returned an error' : 's returned errors');
                }
            else
                {
                # Get status subblock from the result block, if it exists
                $self->{'status'}{'json'} = $self->subset('root' => $self->{'result'}, 'set' => 'result', 'key' => 'status', 'null' => {'code' => -1, 'message' => 'No status available'});
                }
            }
        else
            {
            # JSON could not be parsed
            $self->{'status'}{'json'}{'message'} = 'Invalid JSON';
            }

        # Return code will be true for success, or false for failure
        return (($self->{'status'}{'json'}{'code'} // -1) == 0 ? 1 : 0);
        }

    # Return code will be true for success, or false for failure
    return ((($self->{'status'}{'http'}{'code'} // -1) >= 200 && ($self->{'status'}{'http'}{'code'} // -1) <= 299) ? 1 : 0);
    }

# subset() method
#
# Returns the subset of a root hash, given a set and search key.
# This is typically done as follows:
#
# $x->subset
#   (
#   'root'          => {Root hash to search},
#   'set'           => 'Set of root hash',
#   'key'           => 'Key of set to find'
#   );
#
# Given a root hash of either:
#
# a) $h->{'result'}{'result'} {'status'} = { 'code' => 0, 'message' => 'Hello, world' }
# or <---- *1 ----><-- *2 --> <-- *3 -->
# b) $h->{'result'}{'result'}[0]{'status'} = { 'code' => 0, 'message' => 'Hello, world' }
#    <---- *1 ----><-- *2 -->   <-- *3 -->
#
# Given the above and the following parameters:
#
# $r = $x->subset({'root' => $h->{'result'}, 'set' => 'result', 'key' => 'status'});
#                            <---- *1 ---->           <- *2 ->           <- *3 ->
#
# $r would contain the hash { 'code' => 0, 'message' => 'Hello, world' } after execution.
#
# Additional options:
#
#   'url'           => 'URL to match' This will return the first (or only) matching hash, or index of hash, that also contains the matching URL.
#   'index'         => integer This specifies a specific array index to examine - no search. Only effective with root hash with an array.
#   'next'          => integer This specifies a specific array index to resume searching at. Only effective with root hash with an array.
#   'null'          => {Substitute} This will supply a hash to return (defaults to empty), in the event that the search criteria were not met.

sub subset
    {
    my ($self, %argument) = @_;
    my $root  = $argument{'root'};
    my $set   = $argument{'set'};
    my $key   = $argument{'key'};
    my $url   = $argument{'url'};
    my $null  = $argument{'null'};
    my $next  = $argument{'next'};
    my $index = $argument{'index'};

    # Check proper arguments have been supplied
    if (!defined($root) || !defined($set) || !defined($key))
        { croak 'Root, set and key are required'; }

    # Check if set hash is encoded directly in the root hash
    if (ref($root->{$set}) eq 'HASH')
        {
        # Return search hash, or defined or empty structure if the search hash was not found
        return (defined($root->{$set}) && defined($root->{$set}{$key}) && (!defined($url) || $url eq $root->{$set}{'url'} // 'unknown_url') ? $root->{$set}{$key} : $null // {});
        }
    else
        {
        # Check if an index has been specified
        if (!defined($index))
            {
            # Index for arrayed entries
            $index = $next // 0;

            # Limit search to initial array size
            my $limit = $#{$root->{$set}} + 1;

            # Scan set array for search hash
            while (!defined($root->{$set}[$index]{$key}) && (!defined($url) || $url ne $root->{$set}[$index]{'url'} // 'unknown_url') && $index < $limit) { $index++; }
            }

        # Return search hash at the specified index, or defined or empty structure if the search hash was not found
        return (defined($root->{$set}[$index]{$key}) && (!defined($url) || $url eq $root->{$set}[$index]{'url'} // 'unknown_url') ? $root->{$set}[$index]{$key} : $null // {});
        }
    }

# workspace() method
#
# Locks, commits or unlocks a workspace.
# This is typically done as follows:
#
# $r = $x->workspace
#   (
#   'adom'          => ADOM to use,
#   'mode'          => 'lock', 'unlock' or 'commit'
#   );
#
# $r contains 1 upon successful execution, or 0 if an error occurred.

sub workspace
    {
    my ($self, %argument) = @_;
    my $adom = $argument{'adom'};
    my $mode = $argument{'mode'};
    my $echo = $argument{'echo'} // 'Off';

    my $result = undef;

    # Check mode parameter
    if ($mode =~ m/^(LOCK|UNLOCK|COMMIT)$/i)
        {
        # Check for required fields and formatting
        if (defined($adom) && $adom =~ m/^[a-zA-Z0-9_\-]*$/)
            {
            # Request the workspace operation
            $result = $self->request
                (
                'echo'   => $echo,
                'method' => 'exec',
                'url'    => 'pm/config/adom/'.$adom.'/_workspace/'.lc $mode
                );
            }

        # Handle invalid or missing ADOM parameter
        else { croak 'ADOM invalid or missing'; }
        }

    # Handle erroneous action parameters
    else { croak 'Invalid mode supplied'; }

    # Pass return code to caller
    return ($result // 0);
    }

# Destructor.
# Automatically logs out, if a login was attempted.

sub DESTROY
    {
    my ($self) = @_;

    # Check if a login was attempted and a session ID exists
    if ($self->{'login'} == 1 && defined($self->{'session'}))
        {
        # Attempt to log out
        $self->request
            (
            'method' => 'exec',
            'url'    => 'sys/logout',

            # Hide output unless verbose is set and not overridden
            'echo'   => $self->{'verbose'} == 1 && $self->{'echo'} eq 'unset' ? 'unset' : 'none'
            );
        }
    }

1;
