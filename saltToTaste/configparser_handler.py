import os
import sys
import configparser
from flask import current_app
from saltToTaste.argparser_handler import argparser_results

argument = argparser_results()
DATA_DIR = os.path.abspath(argument['DATA_DIR'])

def configparser_results(file):
    config = configparser.ConfigParser()

    config.read(file)

    if not config.has_section('flask'):
        print ('Error: Issue reading config.ini')
        sys.exit()

    return config

def create_default_configfile():
    config_data = {
        'flask' : {
            'secret_key' : os.urandom(16).hex() # actually makes a string 32 characters long
        },
        'general' : {
            'authentication_enabled' : False,
            'userless_recipes' : False,
            'api_enabled' : False,
            'api_key' : os.urandom(16).hex(),
            'backups_enabled' : True,
            'backup_count' : 5
        },
        'third_party' : {
            'edamam_id' : '',
            'edamam_key' : ''
        }
    }

    config = configparser.ConfigParser()
    config.read_dict(config_data)

    with open(current_app.config['CONFIG_INI'], 'w') as configfile:
        config.write(configfile)
        print (' + Creating config file')

def update_configfile(dict):
    config = configparser_results(current_app.config['CONFIG_INI'])

    if config:
        for section in dict:
            if config.has_section(section):
                for k,v in dict[section].items():
                    if config.has_option(section, k):
                        config.set(section, k, str(v))

        with open(current_app.config['CONFIG_INI'], 'w') as configfile:
            config.write(configfile)
            print (' * Updating config file')

            return True

def verify_configfile():
    file = f'{DATA_DIR}/config.ini'
    config = configparser_results(file)

    default_config = {
        'flask' : {
            'secret_key' : os.urandom(16).hex() # actually makes a string 32 characters long
        },
        'general' : {
            'authentication_enabled' : False,
            'userless_recipes' : False,
            'api_enabled' : False,
            'api_key' : os.urandom(16).hex(),
            'backups_enabled' : True,
            'backup_count' : 5
        },
        'third_party' : {
            'edamam_id' : '',
            'edamam_key' : ''
        }
    }

    for section in default_config:
        if not config.has_section(section):
            config.add_section(section)
        for k, v in default_config[section].items():
            if not config.has_option(section, k):
                config.set(section, k, str(v))

    with open(file, 'w') as configfile:
        config.write(configfile)
