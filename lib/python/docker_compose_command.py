#!/usr/bin/env python3

# This is a helper script which returns the docker compose command prefix with the correct context.

import os
import sys
import subprocess
import json

if subprocess.run(["docker", "compose", "version"], stdout=subprocess.DEVNULL).returncode != 0:
    print("sudo docker-compose")
    quit(0)
else:
    if sys.version_info < (3, 7):
        print("sudo docker compose")
        print("Warning: Docker Contexts are not supported below Python 3.7\n", file=sys.stderr)
        quit(0)

    if len(sys.argv) > 1:
        context_postfix = " -c " + sys.argv[1]
        result = subprocess.run(["docker", "context", "inspect", sys.argv[1]], capture_output=True, text=True)
    else:
        context_postfix = ""
        result = subprocess.run(["docker", "context", "inspect"], capture_output=True, text=True)

    if result.returncode != 0:
        print("Failed to inspect Docker Context")
        quit(-1)
    else:
        try:
            output = json.loads(result.stdout)
            socket = output[0]["Endpoints"]["docker"]["Host"][7:] # Remove unix://
            if os.stat(socket).st_uid == os.getuid():
                print("docker" + context_postfix + " compose")
            else:
                print("sudo docker" + context_postfix + " compose")
            quit(0)
        except json.JSONDecodeError:
            print("Failed to parse Docker Context information")
            quit(-1)
        except KeyError:
            print("Docker Context information is missing a required key")
            quit(-1)
