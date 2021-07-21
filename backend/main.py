from flask import Flask, send_file, send_from_directory
from flask_cors import CORS
from flask_restful import Api, Resource, reqparse, abort, fields, marshal_with, reqparse
# import threading

from core.database.datasources.database import Database
from core.database.models.recipe_model import Recipe
from features.image.image_data_source import ImageDataSource
# from features.nutrition.nutrition_data_source import NutritionDataSource
from features.recipes.recipe_data_source import RecipeFiles, RecipeDB
from features.settings.settings_data_source import SettingsDataSource
from extensions import db

app = Flask(__name__)
CORS(app)
api = Api(app)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///core/database/database.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
#TODO: Setup the ability to do a custom data path
app.config['RECIPE_IMAGES'] = f'assets/recipes/images/'

# Initialize and create the database
db.init_app(app)
db.app = app
db.create_all()

database_handler = Database()
recipe_files_handler = RecipeFiles()
recipe_database_handler = RecipeDB()
image_data_source = ImageDataSource()
# nutrition_data_source = NutritionDataSource()
settings_data_source = SettingsDataSource()

# Set Flask secret key from config.ini
app.config['SECRET_KEY'] = settings_data_source.get_setting(
    'flask',
    'secret_key',
)

recipe_dict_list = recipe_files_handler.load()
recipe_database_handler.add_recipe_files_to_db(recipe_dict_list)
# nutrition_thread = threading.Thread(target=nutrition_data_source.nutrition_queue_action(), name='Get Nutrition')
# nutrition_thread.start()


image_req_args = reqparse.RequestParser()
image_req_args.add_argument(
    'width',
    type=int,
)
image_req_args.add_argument(
    'height',
    type=int,
)

settings_put_args = reqparse.RequestParser()
settings_put_args.add_argument(
    'section',
    help='Section argument is required.',
    required=True,
)
settings_put_args.add_argument(
    'setting',
    help='Setting argument is required.',
    required=True,
)
settings_put_args.add_argument(
    'value',
    help='Value argument is required.',
    required=True,
)


class Image(Resource):
    def get(self, title_sanitized):
        args = image_req_args.parse_args()
        width = args['width']
        height = args['height']

        # Return error on bad arguments
        if ((width and not height) or (height and not width)):
            return {
                'result': 'error',
                'message':
                'When setting width and height both must be specified.',
            }, 400

        # Get Pillow image
        image = image_data_source.get_image(title_sanitized)

        # If width and height are set resize image
        if (width and height):
            image_data_source.resize_image(
                image,
                width,
                height,
            )

        # Save image as BytesIO
        img_io = image_data_source.save_image_as_bytes(image)

        return send_file(img_io, mimetype='image/jpeg')


class Recipe(Resource):
    def get(self, title_sanitized):
        try:
            return {
                'result':
                'success',
                'data':
                database_handler.get_recipe_by_title_sanitized(title_sanitized)
            }, 200
        except ValueError as error:
            return {
                'result': 'error',
                'message': str(error),
            }, 404


class RecipeList(Resource):
    def get(self):
        return {
            'result': 'success',
            'data': database_handler.get_recipe_list(),
        }, 200


class Recipes(Resource):
    def get(self):
        return {
            'result': 'success',
            'data': database_handler.get_recipes(),
        }, 200


class Settings(Resource):
    def get(self):
        return settings_data_source.get_config_dict()

    def put(self):
        args = settings_put_args.parse_args()
        section = args['section']
        setting = args['setting']
        value = args['value']

        result = settings_data_source.update_setting(section, setting, value)

        if result:
            return {'result': 'success'}
        else:
            return {
                'result': 'error',
                'message': 'Failed to update setting',
            }


api.add_resource(Image, '/api/image/<string:title_sanitized>')
api.add_resource(RecipeList, '/api/recipe_list')
api.add_resource(Recipes, '/api/recipes')
api.add_resource(Recipe, '/api/recipe/<string:title_sanitized>')
api.add_resource(Settings, '/api/settings')

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)