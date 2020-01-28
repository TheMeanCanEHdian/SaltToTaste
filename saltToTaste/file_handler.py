import os
import copy
import yaml
import requests
import hashlib
import configparser
from collections import defaultdict, OrderedDict
from datetime import datetime
from saltToTaste.parser_handler import argparser_results, configparser_results

argument = argparser_results()
DATA_DIR = os.path.abspath(argument['DATA_DIR'])

def create_default_configfile(file):
    config_data = {
        'flask' : {
            'secret_key' : os.urandom(16).hex() # actually makes a string 32 characters long
        },
        'general' : {
            'api_enabled' : False,
            'api_key' : os.urandom(16).hex()
        }
    }

    config = configparser.ConfigParser()
    config.read_dict(config_data)

    with open(file, 'w') as configfile:
        config.write(configfile)
        print (' + Creating config file')

def update_configfile(file, dict, section):
    config = configparser_results(file)

    if config:
        for k,v in dict.items():
            if config.has_option(section, k):
                config.set(section, k, str(v))

        with open(file, 'w') as configfile:
            config.write(configfile)
            print (' * Updating config file')

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
        ext = os.path.splitext(os.path.join(directory, filename))[-1].lower()

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
