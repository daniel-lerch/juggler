#!/usr/bin/env python3

# This is a helper script for Juggler which extracts variable usages
# from Docker Compose files and prints them to the console for interop

# There are several ways of variable substitution to look for:
# https://docs.docker.com/compose/environment-variables/

import sys
import yaml

def addVariablesFromString(string, variables):
    done = 0
    while True:
        index = string.find('$', done)
        if index == -1 or index >= len(string) + 1:
            break
        elif string[index + 1] == '$':
            done = index + 2
        elif string[index + 1] == '{':
            endIndex = string.find('}', index + 2)
            if endIndex != -1:
                variables.add(string[index + 2:endIndex])
                done = endIndex + 1
        else:
            print("Variable substitution without curly brackets is not supported", file=sys.stderr)
            done = index + 2

def addVariablesRecursive(obj, variables):
    if isinstance(obj, dict):
        for key in obj.keys():
            addVariablesFromString(key, variables)
            addVariablesRecursive(obj[key], variables)
    elif isinstance(obj, list):
        for item in obj:
            addVariablesRecursive(item, variables)
    elif isinstance(obj, str):
        addVariablesFromString(obj, variables)
    # Numbers and booleans cannot contain variables

def addServiceVariables(compose, variables):
    if 'services' in compose and isinstance(compose['services'], dict):
        for serviceName in compose['services']:
            service = compose['services'][serviceName]
            if isinstance(service, dict) and 'environment' in service and isinstance(service['environment'], list):
                for variable in service['environment']:
                    if isinstance(variable, str) and not '=' in variable:
                        variables.add(variable)

if len(sys.argv) <= 1:
    print("ERROR: Please specify a file")
    quit(-1)

with open(sys.argv[1], 'r') as f:
    try:
        compose = yaml.safe_load(f)
        variables = set()
        addVariablesRecursive(compose, variables)
        addServiceVariables(compose, variables)
        for variable in variables:
            print(variable)
    except yaml.YAMLError as exc:
        print(exc, file=sys.stderr)
