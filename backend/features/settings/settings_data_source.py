import configparser
import os

#TODO: Get directory from argument parser
DATA_DIR = 'assets'

DEFAULT_CONFIG = {
    'flask': {
        'secret_key': os.urandom(16).hex(),
    },
    'third_party': {
        'edamam_id': '',
        'edamam_key': '',
    }
}

config = configparser.ConfigParser()


class SettingsDataSource:
    def create_default_config_file(self):
        config.read_dict(DEFAULT_CONFIG)
        with open(f'{DATA_DIR}/config.ini', 'w') as config_file:
            config.write(config_file)

    def get_config(self):
        config.read(f'{DATA_DIR}/config.ini')
        return config

    def get_config_dict(self):
        config_dict = {}

        for section in config.sections():
            section_dict = {}

            for item in config.items(section):
                key, value = item
                section_dict[key] = value

            config_dict[section] = section_dict

        return config_dict

    def update_setting(self, section, setting, value):
        try:
            if config.get(section, setting, fallback=None) is not None:
                config.set(section, setting, value)
                with open(f'{DATA_DIR}/config.ini', 'w') as config_file:
                    config.write(config_file)
                return True
            else:
                return False
        except configparser.Error:
            return False

    #TODO: Needs to check that no settings are missing
    def verify_config_file(self):
        try:
            self.get_config()
            return True
        except configparser.Error:
            try:
                self.create_default_config_file()
                return True
            except configparser.Error:
                return False
