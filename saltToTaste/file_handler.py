import os
import copy
import yaml
import requests
import hashlib
import shutil
import configparser
from collections import defaultdict, OrderedDict
from datetime import datetime
from zipfile import ZipFile
from flask import current_app
from saltToTaste.parser_handler import argparser_results, configparser_results

argument = argparser_results()
DATA_DIR = os.path.abspath(argument['DATA_DIR'])

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

def hash_file(filename):
    # Make a hash object
    h = hashlib.sha256()

    # Open file for reading in binary mode
    with open(filename, 'rb') as file:
        # Loop until the end of the file
        chunk = 0
        while chunk != b'':
            # Read only 1024 bytes at a time
            chunk = file.read(1024)
            h.update(chunk)

        # Return the hex representation of digest
        return h.hexdigest()

def recipe_importer(directory):
    print (' * Importing recipe files')

    recipe_list = []

    for filename in os.listdir(directory):
        file = os.path.join(directory, filename)
        ext = os.path.splitext(file)[-1].lower()

        if ext == ".yaml":
            with open(file, 'r',  encoding='utf-8') as stream:
                recipe_data = yaml.safe_load(stream)

                if not recipe_data['layout']:
                    print (f'Skipping import of {filename}. No layout specified.')

                if not recipe_data['title']:
                    print (f'Skipping import of {filename}. No title specified.')
                    break

                recipe_data['title_formatted'] = recipe_data['title'].replace(" ", "-").lower()
                recipe_data['filename'] = filename
                recipe_data['file_hash'] = (hash_file(file))
                recipe_list.append(recipe_data)

    return recipe_list

def create_recipe_file(directory, recipe_data):
    recipe_data_copy = copy.deepcopy(recipe_data)
    file = os.path.join(directory, recipe_data_copy['filename'])

    if 'filename' in recipe_data_copy:
        del recipe_data_copy['filename']

    if 'title_formatted' in recipe_data_copy:
        del recipe_data_copy['title_formatted']

    if 'file_hash' in recipe_data_copy:
        del recipe_data_copy['file_hash']

    with open(file, 'w',  encoding='utf-8') as f:
        yaml.add_representer(OrderedDict, lambda dumper, data: dumper.represent_mapping('tag:yaml.org,2002:map', data.items()))
        print (f" + Writing {recipe_data['title']} file to disk.")
        yaml.dump(recipe_data_copy, f, allow_unicode=True, sort_keys=False)

def delete_file(directory, filename):
    file = os.path.join(directory, filename)
    if os.path.exists(file):
        os.remove(file)
        print (f' - Deleting {filename} from disk.')
        return True
    return False

def rename_file(src, dst):
    os.rename(src, dst)

def download_image(url, directory, title_formatted):
    r = requests.head(url)
    ext = url.rsplit('.', 1)[1].lower()

    if 'image' in r.headers.get('content-type'):
        r = requests.get(url)
        filename = f'{title_formatted}.{ext}'
        file = os.path.join(directory, filename)

        open(file, 'wb').write(r.content)
        print (f' + Saved {filename} to disk.')
        return filename
    return False

def save_image(directory, filename, image_data):
    image_data.save(os.path.join(directory, filename))
    print (f' + Saved {filename} to disk.')

def backup_recipe_file(filename):
    date = datetime.today().timestamp()
    config = configparser_results(current_app.config['CONFIG_INI'])
    root_ext = os.path.splitext(filename)
    backup_dir = f"{DATA_DIR}/backups/"
    backup_filename = f"{root_ext[0].lower()}.backup-{date}{root_ext[1].lower()}"
    files = [name for name in os.listdir(backup_dir) if os.path.isfile(os.path.join(backup_dir, name)) if root_ext[0] in name if root_ext[1] in name]

    # Delete oldest backup if the backup_count has been met
    if config.getboolean('general', 'backups_enabled') and config['general']['backup_count']:
        if files and config.getint('general', 'backup_count') <= len(files):
            os.remove(os.path.join(backup_dir, files[0]))

        print (f' + Backing up {filename}')
        shutil.copyfile(f"{current_app.config['RECIPE_FILES']}{filename}", f'{backup_dir}{backup_filename}')

def backup_image_file(filename):
    date = datetime.today().timestamp()
    config = configparser_results(current_app.config['CONFIG_INI'])
    root_ext = os.path.splitext(filename)
    backup_dir = f"{DATA_DIR}/backups/"
    backup_filename = f"{root_ext[0].lower()}.backup-{date}{root_ext[1].lower()}"
    files = [name for name in os.listdir(backup_dir) if os.path.isfile(os.path.join(backup_dir, name)) if root_ext[0] in name if root_ext[1] in name]

    # Delete oldest backup if the backup_count has been met
    if config.getboolean('general', 'backups_enabled') and config['general']['backup_count']:
        if files and config.getint('general', 'backup_count') <= len(files):
            os.remove(os.path.join(backup_dir, files[0]))

        print (f' + Backing up {filename}')
        shutil.copyfile(f"{current_app.config['RECIPE_IMAGES']}{filename}", f'{backup_dir}{backup_filename}')

def backup_database_file():
    date = datetime.today().timestamp()
    config = configparser_results(current_app.config['CONFIG_INI'])
    backup_dir = f"{DATA_DIR}/backups/"
    files = [name for name in os.listdir(backup_dir) if os.path.isfile(os.path.join(backup_dir, name)) if 'database' in name if '.db' in name]

    if config.getboolean('general', 'backups_enabled') and config['general']['backup_count']:
        if files and config.getint('general', 'backup_count') <= len(files):
            os.remove(os.path.join(backup_dir, files[0]))

        print (' + Backing up database.db')
        shutil.copyfile(f'{DATA_DIR}/database.db', f'{backup_dir}database.backup-{date}.db')

def backup_config_file():
    date = datetime.today().timestamp()
    config = configparser_results(current_app.config['CONFIG_INI'])
    backup_dir = f"{DATA_DIR}/backups/"
    files = [name for name in os.listdir(backup_dir) if os.path.isfile(os.path.join(backup_dir, name)) if 'config' in name if '.ini' in name]

    if config.getboolean('general', 'backups_enabled') and config['general']['backup_count']:
        if files and config.getint('general', 'backup_count') <= len(files):
            os.remove(os.path.join(backup_dir, files[0]))

        print (' + Backing up config.ini')
        shutil.copyfile(f'{DATA_DIR}/config.ini', f'{backup_dir}config.backup-{date}.ini')
