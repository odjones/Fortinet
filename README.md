# Fortinet
Library and scripts for automating operations with Fortinet's FortiManager API, with shell scripts and Perl

Original code was lovingly crafted in 2015-2016 for a project with FortiManager 5.4.x, and casked on spinning rust to gather digital dust. With a recent project, I got an opportunity to dig it up, test it with FortiManager 6.4.x, make some enhancements, eliminate some dependencies and fix some bugs. What you see here is the result.

## Deliverables

This project comprises three files:

1) The Fortinet library (Fortinet.pm), which is used by the following two files (and your own Perl projects)
2) The login script (login.pl), which is used to log in and create a new shell with the environment variables to support convenient operations within the same session
3) The command script (cmd.pl), which is used to issue commands to the Fortinet library from the shell

The login script allows the user to log in once with credentials, and use the command script to issue commands to the FortiManager without having to deal with specifying the session ID. (This is preserved in a shell environment variable upon successful login.) Logging out is convenient - simply exit the shell, and the login script will automatically send a logout command to the API, to invalidate the session ID.

The command script is not much more than a friendly interface between the shell and the Fortinet library, which itself is an interface to the Fortinet API. Why use the command script at all? For starters, it picks up environment variables left by the login script, so operation is seamless. Furthermore, it also allows the use of arrays to process multiple objects, and performs the necessary sanity checks for each type of argument. Please read the comments in the command script - plenty of useful Fortinet API examples are included for the curious. (For a comprehensive guide with a complete list of optional parameters for each API call, please ask your friendly Fortinet representative for access to the Fortinet Developer Network.)

## Scripting vs. Ansible

Why bother using this code, instead of something more trendy like Ansible? It depends on what you need to do: If your needs are more procedural (and perhaps you want to write scripts to automate the addition of firewall rules, objects, etc. according to a certain criteria - including validation against other network services or APIs), you may be better off scripting your Fortinet automation than relying on Ansible and friends.

Writing your own code requires only the Fortinet.pm library, if you wish to handle everything from login to command processing yourself (in which case, the login and command scripts also serve as useful examples.) Generally, you will instantiate a new Fortinet class object using the connection credentials (hostname, username, password - or hostname and session) supplied with a call to Fortinet->new(), and be prepared to handle failure (thus, handle the instantiation using eval {} to trap errors gracefully.) The login and command scripts make this look deceptively simple, because they supply a hash to Getopt::Long to collect the arguments needed, and then pass the same hash to Fortinet->new() upon class instantiation.

Performance is good, but how you design your code has by far the biggest influence on speed. Pro tip: Try to build a big array of commands to send in one API call, rather than sending lots of individual calls to the API. Real example: Creating 10,000 service objects with a big array and one API call takes about 72 seconds. Doing the same with 10,000 separate calls to the API will take about 25 minutes. The Fortinet library will check return codes for you, and even if one command out of 10,000 failed, it's easy to tell if any failed (and which ones failed.) The code is well-documented, and apart from my love of Perl conditional expressions, should be reasonably easy to follow.

## Fortinet API example transcripts

Because code is only so useful, below are some example session transcripts to illustrate more clearly how interaction with the FortiManager really works.

### Logging in

A good place to begin is by authenticating with a FortiManager that you want to use. In the following example, we authenticate to the fictional FortiManager appliance bunsen.muppetlabs.com, using the username of beaker and the password Mimimi, with the verbose flag set. Verbose mode shows all transactions, unless overridden - and in this case, it will show the API request used for logging in:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -verbose
# Request:
{
   "id" : 1,
   "method" : "exec",
   "params" : [
      {
         "data" : [
            {
               "passwd" : "Mimimi",
               "user" : "beaker"
            }
         ],
         "url" : "sys/login/user"
      }
   ]
}
# Response:
{
   "id" : 1,
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "sys/login/user"
      }
   ],
   "session" : "5IMP0I1lv3FqZm+UqwHP/V+G6jgXohRPbs2M2leUnqwYl+QnNTGICo8hW2skdZAr4mBzoR/1oF0VdunFfafJ0A=="
}
Login successful with session 5IMP0I1lv3FqZm+UqwHP/V+G6jgXohRPbs2M2leUnqwYl+QnNTGICo8hW2skdZAr4mBzoR/1oF0VdunFfafJ0A==
Please exit this shell to log out.
[oliver@rocky ~]$
```

With a successful login, a new shell is spawned, with the session exported to an environment variable. This is picked up by the command script, so it is not necessary to log in for every command sent to the FortiManager.

### Insecure mode

If you are using a development environment where you have not installed a certificate on your FortiManager (and the corresponding CA trust certificate(s) on your workstation), the TLS host check will prevent you from connecting. This is of course the whole point of the TLS host check, but if connecting to a development FortiManager is more important than security (and you trust your network), it is possible to use the -insecure flag when logging in. This will cause the Fortinet library to ignore TLS host checks, and also export insecure mode as an environment variable for subsequent commands you execute with the session.

There is one intentional built-in annoyance: If you log in with insecure mode, subsequent API calls you make with the command script will also use insecure mode. Because this is definitely not a recommended mode of operation, both the login and command scripts will generate a warning on STDERR if they detect that insecure mode has been set with an environment variable *unless* the -insecure flag is also provided for every invocation. (This is enough to demonstrate you mean business, you haven't made a mistake - and really, *really* intend to use insecure mode.)

### Logging out

Logging out is as simple as exiting the shell that was spawned. In this event, the login script paused until the shell was exited, and when command flow resumes, it will quit. As part of that, the destructor in the Fortinet library will be triggered, and that will automatically send an API call to log out the current session, viz:

```
[oliver@rocky ~]$ exit
exit
Logging out...
# Request:
{
   "id" : 2,
   "method" : "exec",
   "params" : [
      {
         "url" : "sys/logout"
      }
   ],
   "session" : "5IMP0I1lv3FqZm+UqwHP/V+G6jgXohRPbs2M2leUnqwYl+QnNTGICo8hW2skdZAr4mBzoR/1oF0VdunFfafJ0A=="
}
# Response:
{
   "id" : 2,
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "sys/logout"
      }
   ]
}
[oliver@rocky ~]$
```

### Dry run: Creating a service object

In this example, we perform a dry run to create a service object, called "Deutschland 83", with a TCP and UDP port of 1983, of course. This example assumes you are using your FortiManager in workspace mode, which requires the workspace to be locked before any changes can be made. Once locked, changes can be submitted - but in order for changes to persist, the workspace must be committed before it is unlocked: Any uncommitted changes made are discarded when the workspace is unlocked.

First, we log in without verbose mode - but using the echo mode all, which will show user requests and responses. (This user preference is, like verbose mode, saved in an environment variable and honoured by the command script, so it is only necessary to specify it once when logging in.)

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
```

The next step is to lock the workspace (the ADOM we use in this and all subsequent examples is "honeydew"), so we use a special URL with the exec method:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/lock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ],
   "session" : "3ugx3uSCM1IA/ve6x2E0FpRipgN5oxNa4tUsciPQDGyZ3wFGhGz9XCPwOVCqYfEulPUSpZUNXZ4Oow8RBAyb6Q=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ]
}
[oliver@rocky ~]$
```

The next step is to craft the service object. This accepts all IPv4 addresses, and will allow TCP and UDP access on port 1983. (Protocol 5 in this case means TCP/UDP/SCTP.) It is also categorised under General in the services category list.

The set method is used to create objects, and the base URL for custom services is provided:

```
[oliver@rocky ~]$ cmd.pl -m set -u 'pm/config/adom/honeydew/obj/firewall/service/custom' \
> -d '{ "name" : "Deutschland 83", "iprange" : "0.0.0.0", "protocol" : 5, "tcp-portrange" : [1983], "udp-portrange" : [1983], "category" : ["General"]}'
# Request:
{
   "id" : "3",
   "method" : "set",
   "params" : [
      {
         "data" : [
            {
               "category" : [
                  "General"
               ],
               "iprange" : "0.0.0.0",
               "name" : "Deutschland 83",
               "protocol" : 5,
               "tcp-portrange" : [
                  1983
               ],
               "udp-portrange" : [
                  1983
               ]
            }
         ],
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom"
      }
   ],
   "session" : "3ugx3uSCM1IA/ve6x2E0FpRipgN5oxNa4tUsciPQDGyZ3wFGhGz9XCPwOVCqYfEulPUSpZUNXZ4Oow8RBAyb6Q=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "name" : "Deutschland 83"
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom"
      }
   ]
}
[oliver@rocky ~]$
```

The API reports success. Now let's see if we can recall the configuration - just supply the name of the object (including spaces) on the end of the URL and change the method to get, and the API will retrieve just the object with that name:

```
[oliver@rocky ~]$ cmd.pl -m get -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83'
# Request:
{
   "id" : "3",
   "method" : "get",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83"
      }
   ],
   "session" : "3ugx3uSCM1IA/ve6x2E0FpRipgN5oxNa4tUsciPQDGyZ3wFGhGz9XCPwOVCqYfEulPUSpZUNXZ4Oow8RBAyb6Q=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "app-category" : [],
            "app-service-type" : 0,
            "application" : [],
            "category" : [
               "General"
            ],
            "check-reset-range" : 3,
            "color" : 0,
            "comment" : null,
            "fqdn" : null,
            "helper" : 1,
            "iprange" : "0.0.0.0",
            "name" : "Deutschland 83",
            "obj seq" : 90,
            "protocol" : 5,
            "proxy" : 0,
            "sctp-portrange" : [],
            "session-ttl" : "0",
            "tcp-halfclose-timer" : 0,
            "tcp-halfopen-timer" : 0,
            "tcp-portrange" : [
               "1983"
            ],
            "tcp-timewait-timer" : 0,
            "udp-idle-timer" : 0,
            "udp-portrange" : [
               "1983"
            ],
            "visibility" : 1
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83"
      }
   ]
}
[oliver@rocky ~]$
```

You can see that there are many more options in the configuration than those specified - default options not specified are added to the configuration when the object is created.

However, we don't need to keep this service object, so we'll unlock the workspace and this will roll back all the changes we made in this session. We'll also log out when done:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/unlock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ],
   "session" : "3ugx3uSCM1IA/ve6x2E0FpRipgN5oxNa4tUsciPQDGyZ3wFGhGz9XCPwOVCqYfEulPUSpZUNXZ4Oow8RBAyb6Q=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ]
}
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```

At this point, the Deutschland 83 service was removed, as it was never committed. We can check this is the case by logging in again and asking the API to return the service object by name:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
[oliver@rocky ~]$ cmd.pl -m get -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83'
# Request:
{
   "id" : "3",
   "method" : "get",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83"
      }
   ],
   "session" : "wVsVdFWsYjY6sxnpNmOBAWYTRwMGtJAn+YicEAL2UCT//Q8XqKbcUXYNZtkXdD76xNHT+myv94ly93IDrHopzg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : -3,
            "message" : "Object does not exist"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Deutschland 83"
      }
   ]
}
Object does not exist at cmd.pl line 144.
[oliver@rocky ~]$ echo $?
255
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```

There are a couple of points to note:

1) The FortiManager will report the error in the response, in this case JSON code -3 is supplied, with the message "Object does not exist".
2) The command script will check the return code and die if it's not successful, giving the "Object does not exist at cmd.pl line 144" error. It also generates a non-zero return code, making it simple to test for errors in shell scripts.

### Creating a service object (for real, this time)

We will repeat the process above, with a couple of small changes: First of all, we will create a different network service, and secondly we will commit it.

To begin with, we log in and lock the workspace:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/lock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ],
   "session" : "UlRsW70t/bBp+liOG3WpeXxJggdPr2l0i1uykaSn8fkpBkEgzAIIvX6/FFzBJudlVjEB6u8ze2lAEiXhPBwQMQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ]
}
[oliver@rocky ~]$
```

Next, we create a service object called "Big Brother", with a TCP port of 1984 and placed in the category of Network Services.

As before, we use the base custom services URL, and specify the name of the service to create in the data structure:

```
[oliver@rocky ~]$ cmd.pl -m set -u 'pm/config/adom/honeydew/obj/firewall/service/custom' \
> -d '{ "name" : "Big Brother", "iprange" : "0.0.0.0", "protocol" : 5, "tcp-portrange" : [1984], "udp-portrange" : [1984], "category" : ["Network Services"]}'
# Request:
{
   "id" : "3",
   "method" : "set",
   "params" : [
      {
         "data" : [
            {
               "category" : [
                  "Network Services"
               ],
               "iprange" : "0.0.0.0",
               "name" : "Big Brother",
               "protocol" : 5,
               "tcp-portrange" : [
                  1984
               ],
               "udp-portrange" : [
                  1984
               ]
            }
         ],
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom"
      }
   ],
   "session" : "UlRsW70t/bBp+liOG3WpeXxJggdPr2l0i1uykaSn8fkpBkEgzAIIvX6/FFzBJudlVjEB6u8ze2lAEiXhPBwQMQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "name" : "Big Brother"
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom"
      }
   ]
}
[oliver@rocky ~]$
```

All good, so far. Let's check what the FortiManager has, by asking for the configuration for the Big Brother service:

```
[oliver@rocky ~]$ cmd.pl -m get -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother'
# Request:
{
   "id" : "3",
   "method" : "get",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ],
   "session" : "UlRsW70t/bBp+liOG3WpeXxJggdPr2l0i1uykaSn8fkpBkEgzAIIvX6/FFzBJudlVjEB6u8ze2lAEiXhPBwQMQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "app-category" : [],
            "app-service-type" : 0,
            "application" : [],
            "category" : [
               "Network Services"
            ],
            "check-reset-range" : 3,
            "color" : 0,
            "comment" : null,
            "fqdn" : null,
            "helper" : 1,
            "iprange" : "0.0.0.0",
            "name" : "Big Brother",
            "obj seq" : 89,
            "protocol" : 5,
            "proxy" : 0,
            "sctp-portrange" : [],
            "session-ttl" : "0",
            "tcp-halfclose-timer" : 0,
            "tcp-halfopen-timer" : 0,
            "tcp-portrange" : [
               "1984"
            ],
            "tcp-timewait-timer" : 0,
            "udp-idle-timer" : 0,
            "udp-portrange" : [
               "1984"
            ],
            "visibility" : 1
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ]
}
[oliver@rocky ~]$
```

Looks good so far. This time, though, we'd like to keep our changes. So we need to issue a workspace commit - this is done a similar way to locking and unlocking a workspace, viz:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/commit'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ],
   "session" : "UlRsW70t/bBp+liOG3WpeXxJggdPr2l0i1uykaSn8fkpBkEgzAIIvX6/FFzBJudlVjEB6u8ze2lAEiXhPBwQMQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ]
}
[oliver@rocky ~]$
```

Finally, we should unlock the workspace to allow other users to make changes, and we'll also log out afterward:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/unlock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ],
   "session" : "UlRsW70t/bBp+liOG3WpeXxJggdPr2l0i1uykaSn8fkpBkEgzAIIvX6/FFzBJudlVjEB6u8ze2lAEiXhPBwQMQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ]
}
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```

### Creating an IPv4 policy rule

In this step, we will perform quite a few steps: We will create an IPv4 policy rule that allows all Big Brother traffic from port1 to port2, using the service object we created in the previous step. Once we have committed the workspace though, the rule will not be present on the firewall. In order to deploy the rule, we will need to execute a policy install to copy the configuration over to the FortiGate being managed.

To begin with, we log in and lock the workspace:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/lock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ]
}
[oliver@rocky ~]$
```

The next step is to create the IPv4 policy rule itself. Notice how arrays are defined using square brackets: If we wanted to specify more than one service, we would simply specify a list of service names in the "service" value. The same goes for source and destination interfaces and networks:

```
[oliver@rocky ~]$ cmd.pl -m set -u 'pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/' \
> -d '{"action" : 1, "srcintf" : ["port1"], "dstintf" : ["port2"], "srcaddr" : ["all"], "dstaddr" : ["all"], "service" : ["Big Brother"], "nat" : 0, "schedule" : ["always"] }'
# Request:
{
   "id" : "3",
   "method" : "set",
   "params" : [
      {
         "data" : [
            {
               "action" : 1,
               "dstaddr" : [
                  "all"
               ],
               "dstintf" : [
                  "port2"
               ],
               "nat" : 0,
               "schedule" : [
                  "always"
               ],
               "service" : [
                  "Big Brother"
               ],
               "srcaddr" : [
                  "all"
               ],
               "srcintf" : [
                  "port1"
               ]
            }
         ],
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "policyid" : 6502
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/"
      }
   ]
}
[oliver@rocky ~]$
```

Once the IPv4 policy rule is created, the API will tell you what the policy ID is. FortiGate firewalls do not require a name to differentiate policy rules, but a policy ID must be used instead. Therefore, to retrieve the configuration for the IPv4 policy rule we just created, we just append the policy ID on the end of the URL and use the get method, viz:

```
[oliver@rocky ~]$ cmd.pl -m get -u 'pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502'
# Request:
{
   "id" : "3",
   "method" : "get",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "_byte" : 0,
            "_first_hit" : 0,
            "_first_session" : 0,
            "_global-dst-intf" : null,
            "_global-src-intf" : null,
            "_global-vpn" : [],
            "_global-vpn-tgt" : 0,
            "_hitcount" : 0,
            "_last_hit" : 0,
            "_last_session" : 0,
            "_pkts" : 0,
            "_policy_block" : 0,
            "_sesscount" : 0,
            "action" : 1,
            "anti-replay" : 1,
            "app-group" : [],
            "auto-asic-offload" : 1,
            "best-route" : 0,
            "block-notification" : 0,
            "captive-portal-exempt" : 0,
            "capture-packet" : 0,
            "custom-log-fields" : [],
            "delay-tcp-npu-session" : 0,
            "diffserv-forward" : 0,
            "diffserv-reverse" : 0,
            "disclaimer" : 0,
            "dsri" : 0,
            "dstaddr" : [
               "all"
            ],
            "dstaddr-negate" : 0,
            "dstintf" : [
               "port2"
            ],
            "email-collect" : 0,
            "fsso" : 1,
            "fsso-agent-for-ntlm" : [],
            "fsso-groups" : [],
            "geoip-anycast" : 0,
            "groups" : [],
            "inspection-mode" : 1,
            "internet-service" : 0,
            "internet-service-src" : 0,
            "logtraffic" : 3,
            "logtraffic-start" : 0,
            "match-vip" : 0,
            "match-vip-only" : 0,
            "nat" : 0,
            "natip" : [
               "0.0.0.0",
               "0.0.0.0"
            ],
            "np-acceleration" : 1,
            "obj seq" : 1,
            "per-ip-shaper" : [],
            "permit-any-host" : 0,
            "policyid" : 6502,
            "profile-protocol-options" : [
               "default"
            ],
            "profile-type" : 0,
            "radius-mac-auth-bypass" : 0,
            "replacemsg-override-group" : [],
            "reputation-minimum" : 0,
            "rtp-nat" : 0,
            "schedule" : [
               "always"
            ],
            "schedule-timeout" : 0,
            "service" : [
               "Big Brother"
            ],
            "service-negate" : 0,
            "session-ttl" : "0",
            "srcaddr" : [
               "all"
            ],
            "srcaddr-negate" : 0,
            "srcintf" : [
               "port1"
            ],
            "ssl-mirror" : 0,
            "ssl-mirror-intf" : [],
            "ssl-ssh-profile" : [
               "no-inspection"
            ],
            "status" : 1,
            "tcp-mss-receiver" : 0,
            "tcp-mss-sender" : 0,
            "tcp-session-without-syn" : 2,
            "timeout-send-rst" : 0,
            "tos" : "0x00",
            "tos-mask" : "0x00",
            "tos-negate" : 0,
            "traffic-shaper" : [],
            "traffic-shaper-reverse" : [],
            "users" : [],
            "utm-status" : 0,
            "uuid" : "46d7e40c-04c2-51ec-5675-f37cc2228bfa",
            "vlan-cos-fwd" : 255,
            "vlan-cos-rev" : 255,
            "vlan-filter" : null,
            "vpn_dst_node" : null,
            "vpn_src_node" : null,
            "wccp" : 0,
            "webcache-https" : 0,
            "webproxy-forward-server" : [],
            "webproxy-profile" : []
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502"
      }
   ]
}
[oliver@rocky ~]$
```

As with service objects, there are a lot of defaults that are inserted into the configuration if they are not explicitly supplied (or changed!)

Since we wish to keep this new rule, we should now perform a workspace commit:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/commit'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ]
}
[oliver@rocky ~]$
```

Up to this point, all changes we have made have been on the FortiManager only. Since firewall rules are far more useful when they are actually deployed to the device in question, we need to install the policy package. In this example, the policy package is named "bunsen_honeydew", and it is on the hostname "bunsen", with the VDOM being named "honeydew":

```
[oliver@rocky ~]$ cmd.pl -m exec -u '/securityconsole/install/package' \
> -d '{"adom" : "honeydew", "adom_rev_comments" : "Push configuration to the FortiGate", "adom_rev_name" : "v1.07", "pkg" : "bunsen_honeydew", "scope" : {"name" : "bunsen", "vdom" : "honeydew"}}'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "data" : [
            {
               "adom" : "honeydew",
               "adom_rev_comments" : "Push configuration to the FortiGate",
               "adom_rev_name" : "v1.07",
               "pkg" : "bunsen_honeydew",
               "scope" : {
                  "name" : "bunsen",
                  "vdom" : "honeydew"
               }
            }
         ],
         "url" : "/securityconsole/install/package"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "task" : 644
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "/securityconsole/install/package"
      }
   ]
}
[oliver@rocky ~]$
```

With a successful execution, a new task ID is reported by the ID (644 in this case). If you have access to the GUI, you can see the actual progress of installation as it runs. However, this is a background activity - and asynchronous - so we can proceed with unlocking the workspace and logging out while it runs in the background:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/unlock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ],
   "session" : "oGUJMMi+wLsnpd/dcHUXdHixlU9hZ5gtMrG0bJn7hwABTm5kGzRVlkloY0IkGmrsMhz4isZxtYwP70c3Jj2bjg=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ]
}
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```

### Deleting objects that are in use

FortiGate appliances keep track of objects and where they are used. This is also true of the FortiManager, and we can demonstrate this by trying to delete an object that's in use (in this case, the Big Brother service we created in a previous step.)

First, we log in and lock the workspace:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/lock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ],
   "session" : "RCxkY6c799lK5mE9kcsA616xndDsFmiGtCxnlB+CT6sXi7ojOtG+Ly652oMmFjNcGQEyxqL9g+Ja+U13Ujf2NA=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ]
}
[oliver@rocky ~]$
```

Now we'll try to delete the service object named "Big Brother" and see what happens:

```
[oliver@rocky ~]$ cmd.pl -m delete -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother'
# Request:
{
   "id" : "3",
   "method" : "delete",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ],
   "session" : "RCxkY6c799lK5mE9kcsA616xndDsFmiGtCxnlB+CT6sXi7ojOtG+Ly652oMmFjNcGQEyxqL9g+Ja+U13Ujf2NA=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : -10015,
            "message" : "used"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ]
}
used at cmd.pl line 144.
[oliver@rocky ~]$ echo $?
255
[oliver@rocky ~]$
```
The FortiManager will report an error, specifying the offending URL (with the object name on the end), and an error code. The command script will also trap that error and die.

To clean up for this step, we'll unlock the workspace and log out:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/unlock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ],
   "session" : "RCxkY6c799lK5mE9kcsA616xndDsFmiGtCxnlB+CT6sXi7ojOtG+Ly652oMmFjNcGQEyxqL9g+Ja+U13Ujf2NA=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ]
}
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```

### Cleaning up

In this step, we'll delete everything we created. However, knowledge will not be assumed: This step shows how you can interrogate the FortiManager for useful information.

First, we will start by logging in and locking the workspace:

```
[oliver@rocky ~]$ login.pl -hostname bunsen.muppetlabs.com -username beaker -password Mimimi -echo all
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/lock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/lock"
      }
   ]
}
[oliver@rocky ~]$
```

Next, we will attempt to delete the Big Brother service object:

```
[oliver@rocky ~]$ cmd.pl -m delete -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother'
# Request:
{
   "id" : "3",
   "method" : "delete",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : -10015,
            "message" : "used"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ]
}
used at cmd.pl line 144.
[oliver@rocky ~]$ echo $?
255
[oliver@rocky ~]$
```

Too bad: It's in use.

However, we can ask the FortiManager to give us a list of all IPv4 policy rules, and we can perform some neat trickery with jq to filter the output. In this example, we override the Fortinet library output to use echo for responses only (so jq doesn't choke on invalid JSON), and we ask jq to filter all policy IDs that contain the Big Brother service (we search for this by name), viz:

```
[oliver@rocky ~]$ cmd.pl -m get -u 'pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/' -echo response | \
> jq '.result[].data[]' | jq -c '. | select (.service[] | contains("Big Brother"))' | jq '.policyid'
6502
[oliver@rocky ~]$
```

Policy ID 6502 is the one we must delete, first:

```
[oliver@rocky ~]$ cmd.pl -m delete -u 'pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502'
# Request:
{
   "id" : "3",
   "method" : "delete",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/pkg/bunsen_honeydew/firewall/policy/6502"
      }
   ]
}
[oliver@rocky ~]$
```

Success! Now we can try to delete the Big Brother service object, again:

```
[oliver@rocky ~]$ cmd.pl -m delete -u 'pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother'
# Request:
{
   "id" : "3",
   "method" : "delete",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/obj/firewall/service/custom/Big Brother"
      }
   ]
}
[oliver@rocky ~]$
```

With this done, we must first commit our changes:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/commit'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/commit"
      }
   ]
}
[oliver@rocky ~]$
```

To delete the objects from the FortiGate, the policy package must be redeployed:

```
[oliver@rocky ~]$ cmd.pl -m exec -u '/securityconsole/install/package' \
> -d '{"adom" : "honeydew", "adom_rev_comments" : "Push configuration to the FortiGate", "adom_rev_name" : "v1.08", "pkg" : "bunsen_honeydew", "scope" : {"name" : "bunsen", "vdom" : "honeydew"}}'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "data" : [
            {
               "adom" : "honeydew",
               "adom_rev_comments" : "Push configuration to the FortiGate",
               "adom_rev_name" : "v1.08",
               "pkg" : "bunsen_honeydew",
               "scope" : {
                  "name" : "bunsen",
                  "vdom" : "honeydew"
               }
            }
         ],
         "url" : "/securityconsole/install/package"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "data" : {
            "task" : 645
         },
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "/securityconsole/install/package"
      }
   ]
}
[oliver@rocky ~]$
```

With task ID 645 generated, this will be pushed to the FortiGate in the background. All that's left for us is to unlock the workspace and log out, to conclude the demonstration:

```
[oliver@rocky ~]$ cmd.pl -m exec -u 'pm/config/adom/honeydew/_workspace/unlock'
# Request:
{
   "id" : "3",
   "method" : "exec",
   "params" : [
      {
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ],
   "session" : "CU5Z8KKIhGjSRLMSKbrD4f3oZGVuD+trI5aGYD/VWCQ9G+3vVq3trjumJYDgVXFFXfNHdKOI77x+jsekn+mGCQ=="
}
# Response:
{
   "id" : "3",
   "result" : [
      {
         "status" : {
            "code" : 0,
            "message" : "OK"
         },
         "url" : "pm/config/adom/honeydew/_workspace/unlock"
      }
   ]
}
[oliver@rocky ~]$ exit
exit
[oliver@rocky ~]$
```
