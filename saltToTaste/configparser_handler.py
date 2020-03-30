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
        },
        'tags' : {}
    }

    config = configparser.ConfigParser()
    config.read_dict(config_data)

    with open(f'{DATA_DIR}/config.ini', 'w') as configfile:
        config.write(configfile)
        print (' + Creating config file')

def update_configfile(dict):
    config = configparser_results(f'{DATA_DIR}/config.ini')

    if config:
        for section in dict:
            if config.has_section(section):
                # Remove any options that are in the config but not in the settings dict
                for option in config.options(section):
                    if option not in dict[section].keys():
                        config.remove_option(section, option)
                # Add/update config with items from settings dict
                for k,v in dict[section].items():
                    config.set(section, k, str(v))

        with open(f'{DATA_DIR}/config.ini', 'w') as configfile:
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
        },
        'tags' : {}
    }

    for section in default_config:
        if not config.has_section(section):
            config.add_section(section)
        for k, v in default_config[section].items():
            if not config.has_option(section, k):
                config.set(section, k, str(v))

    with open(file, 'w') as configfile:
        config.write(configfile)

def parse_settings(config, settings_dict):
    parsed_dict = {}

    del settings_dict['tag_bcolor']
    del settings_dict['tag_color']
    del settings_dict['tag_name']
    del settings_dict['tag_icon']

    for section in config:
        if section not in ('DEFAULT', 'flask'):
            parsed_dict[section] = {}
        for key in settings_dict:
            if config.has_option(section, key):
                parsed_dict[section][key] = settings_dict[key]

    return parsed_dict

def decode_tags(config):
    tag_dict = {}
    for tag in config['tags']:
        values = config['tags'][tag].split(',')
        tag_dict[tag] = {
            'icon' : values[0].strip(' ') if values[0].strip(' ') != 'none' else False,
            'color' : values[1].strip(' '),
            'b_color' : values[2].strip(' ')
        }

    return tag_dict

def encode_tags(config, name_list, icon_list, color_list, bcolor_list):
    tag_dict = {}
    encoded_tags = {}

    for idx, val in enumerate(name_list):
        tag_dict[val] = {
            'icon' : icon_list[idx].strip(' ') if icon_list[idx].strip(' ') != '' else 'none',
            'color' : color_list[idx].strip(' '),
            'b_color' : bcolor_list[idx].strip(' ')
        }

    for tag in tag_dict:
        encoded_tags[tag] = f"{tag_dict[tag]['icon']},{tag_dict[tag]['color']},{tag_dict[tag]['b_color']}"

    return encoded_tags
