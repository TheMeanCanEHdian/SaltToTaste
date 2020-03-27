import os
import sys
from flask import Flask, Blueprint
import flask_whooshalchemy as wa
from string import capwords
from saltToTaste.extensions import db, login_manager
from saltToTaste.views.main import main
from saltToTaste.views.api import api
from saltToTaste.models import Recipe, Ingredient, Note, User, Tag, Direction
from saltToTaste.database_handler import add_all_recipes, update_recipes, add_new_recipes, remove_missing_recipes, db_cleanup
from saltToTaste.file_handler import recipe_importer
from saltToTaste.argparser_handler import argparser_results
from saltToTaste.configparser_handler import configparser_results, create_default_configfile, verify_configfile

def create_app(config_file='settings.py'):
    argument = argparser_results()
    DATA_DIR = os.path.abspath(argument['DATA_DIR'])

    app = Flask(__name__)
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = True
    app.config['SQLALCHEMY_ECHO'] = False
    app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{DATA_DIR}/database.db'
    app.config['WHOOSH_INDEX_PATH'] = f'{DATA_DIR}/whooshIndex'
    app.config['WHOOSH_ANALYZER'] = 'StemmingAnalyzer'
    app.config['DATA_DIR'] = DATA_DIR
    app.config['RECIPE_FILES'] = f'{DATA_DIR}/_recipes/'
    app.config['RECIPE_IMAGES'] = f'{DATA_DIR}/_images/'
    app.config['CONFIG_INI'] = f'{DATA_DIR}/config.ini'
    app.jinja_env.filters['capwords'] = capwords

    if not os.path.isfile(app.config['CONFIG_INI']):
        create_default_configfile()

    verify_configfile()
    config = configparser_results(app.config['CONFIG_INI'])

    try:
        app.config['SECRET_KEY'] = config.get('flask', 'secret_key')
    except TypeError:
        print ('Error: Could not find Flask secret_key in config.ini.')
        sys.exit()

    # Register blueprints
    app.register_blueprint(main)
    app.register_blueprint(api, url_prefix='/api')

    # Create indexes of database tables
    wa.search_index(app, Recipe)
    wa.search_index(app, Tag)
    wa.search_index(app, Ingredient)
    wa.search_index(app, Direction)
    wa.search_index(app, Note)

    # Initalize and create the DB
    db.init_app(app)
    db.app = app
    db.create_all()

    # Initalize the login manager plugin
    login_manager.init_app(app)
    login_manager.login_view = 'main.login'
    login_manager.login_message_category = 'info'

    @login_manager.user_loader
    def load_user(user_id):
        return User.query.get(user_id)

    db_cleanup()

    # Import phyiscal recipe files
    recipe_list = recipe_importer(app.config['RECIPE_FILES'])

    # Sync physical recipe files with database
    if not Recipe.query.first():
        add_all_recipes(recipe_list)
    else:
        add_new_recipes(recipe_list)
        remove_missing_recipes(recipe_list)
        update_recipes(recipe_list)
        db_cleanup()

    return app
