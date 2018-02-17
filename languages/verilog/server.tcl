# ----------------------------------------------------------------------
# Copyright (c) 2002 by Cadence Design Systems, All Rights Reserved
# 
# This software is provided as is without warranty of any kind.  The 
# entire risk as to the results and performance of this software is 
# assumed by the user.
#
# Cadence Design Systems disclaims all warranties, either express or 
# implied, including but not limited, the implied warranties of 
# merchantability, fitness for a particular purpose, title and
# noninfringement, with respect to this software.
# ----------------------------------------------------------------------


# ----------------------------------------------------------------------
# SimVision remote server.
#
# Usage:
#
#   SimVision> source server.tcl
#   SimVision> startServer 5678
#
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Start up a remote server on the specified port.
# ----------------------------------------------------------------------
proc startServer {port} {
    server::start $port
    return ""
}

# ----------------------------------------------------------------------
# server implementation
#
# All server specific procedures are placed in the "server" namespace
# so as not to overwrite any user defined procedures.  
# 
# To start the server, use the 'startServer' procedure described above.
# ----------------------------------------------------------------------
namespace eval server {
    variable interp [interp create -safe]
    interp alias $interp request {} [namespace code handleRequest]

    variable cid ""
    variable buffer ""
}

# ----------------------------------------------------------------------
# Process remote calls from a client.  
# We use an aliased command so that we aren't directly executing
# commands reading from a socket.
#
# The client must use the request/response protocal we've set up
# so that we don't execute blind commands.
#   request {set a foo}
#
# ----------------------------------------------------------------------
proc server::handleRequest {cmd} {
    uplevel \#0 $cmd
}

# ----------------------------------------------------------------------
# Send a response to the client application.
# ----------------------------------------------------------------------
proc server::sendResponse {code result} {
    variable cid
    puts $cid $result
    return ""
}

# ----------------------------------------------------------------------
# Handle incoming data from a client. The data is evaluated in a
# safe interpreter for a little extra security.
# ----------------------------------------------------------------------
proc server::handleData {} {
    variable cid
    variable buffer
    variable interp

    if {[gets $cid request] < 0} {
	# The client closed the connection. Reset.
	puts "closed remote connection"
	catch {close $cid}
	set cid ""
	set buffer ""
    } else {
	append buffer $request "\n"
	if {[info complete $buffer]} {
	    # A complete command has been recieved.
	    set request $buffer
	    set buffer ""
	    if {[catch {interp eval $interp $request} result]} {
		# the client sent a bad command
		puts stderr "ERROR: remote client - $result"
		set code "error"
	    } else {
		set code "ok"
	    }
	    # return the response to the request
	    sendResponse $code $result
	} else {
	    # partial command, continue waiting for more data	    
	}
    }

    return ""
}

# ----------------------------------------------------------------------
# Called when a client attempts to connect to the server.  
# For security only accept a single client at a time.
#
# This could easily be extended to handle more than one 
# client at a time.  'buffer' would have to change to be an array
# keyed by the client channel id....
# ----------------------------------------------------------------------
proc server::acceptConnection {channel addr port} {
    variable cid
    variable buffer
    
    # only accept a single client at a time.
    if {$cid != ""} {
	puts $channel "connection refused"
	close $channel
	return ""
    }

    set cid $channel

    # Buffer input by line since anything less isn't useful to us.
    fconfigure $cid -buffering line -blocking 0

    # When new data arrives call our data handler.
    fileevent $cid readable [namespace code handleData]

    puts "accepted remote connection"
    return ""
}

# ----------------------------------------------------------------------
# Start up a socket server on a specific port.
# ----------------------------------------------------------------------
proc server::start {port} {
    socket -server [namespace code acceptConnection] $port
    puts "starting server on port $port"
    return ""
}

