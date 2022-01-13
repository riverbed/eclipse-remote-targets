#
# sigwrap.py -- Signal handling wrapper process
#
# Copyright (c) 2022 Riverbed Technology LLC
#
# This software is licensed under the terms and conditions of the MIT License
# accompanying the software ("License").  This software is distributed "AS IS"
# as set forth in the License.
#

import subprocess, sys, os, signal, time

MAJOR_VERSION = 1
MINOR_VERSION = 0

def show_version():
    print "sigwrap version " + str(MAJOR_VERSION) + "." + str(MINOR_VERSION)

def usage():
    show_version()
    print "Usage:"
    print
    print "sigwrap -h | --help       -- Shows this message"
    print "sigwrap -v | --version    -- Shows current version"
    print "sigwrap command [args...] -- Runs command with SIGWRAP_SIGINT_FILE env set"
    print
    print "SIGWRAP_SIGINT_FILE will point to empty file that will be created"
    print "when a SIGINT occurs."

if len(sys.argv) == 1 or sys.argv[1] == '-h' or sys.argv[1] == '--help':
    usage()
    sys.exit(1)
elif sys.argv[1] == "-v" or sys.argv[1] == "--version":
    show_version()
    sys.exit(0)
class InterruptException(Exception):
    pass

def interrupt_handler(signum, frame):
    raise InterruptException

signal.signal(signal.SIGINT, interrupt_handler)

sigwrap_sigint_file = os.path.join(os.environ["TEMP"], "sigint_pid" + str(os.getpid()) + ".txt")
my_env = os.environ.copy()
my_env["SIGWRAP_SIGINT_FILE"] = sigwrap_sigint_file
p = subprocess.Popen(sys.argv[1:], env=my_env)


do_kill = False

while p.poll() is None:
    try:
        if do_kill == True:
            # Create an empty file
            f = open(sigwrap_sigint_file, "w")
            f.close()
            do_kill = False
        time.sleep(0.5)
    except InterruptException:
        # print "SIGINT happened!"
        # print "Kill PID " + str(p.pid)
        do_kill = True
    else:
        pass
return_code = p.wait()
try:
    os.remove(sigwrap_sigint_file)
except OSError:
    pass
sys.exit(return_code)
