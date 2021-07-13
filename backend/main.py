from flask import Flask, send_file, send_from_directory
from flask_cors import CORS
from flask_restful import Api, Resource, reqparse, abort, fields, marshal_with, reqparse

from core.database.datasources.database import Database
from core.database.models.recipe_model import Recipe
from features.image.image_data_source import ImageDataSource
from features.recipes.recipe_data_source import RecipeFiles, RecipeDB
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

recipe_database_handler.add_recipe_files_to_db(recipe_files_handler.load())

image_req_args = reqparse.RequestParser()
image_req_args.add_argument(
    'width',
    type=int,
)
image_req_args.add_argument(
    'height',
    type=int,
)


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


api.add_resource(RecipeList, '/api/recipe_list')
api.add_resource(Recipes, '/api/recipes')
api.add_resource(Recipe, '/api/recipe/<string:title_sanitized>')
api.add_resource(Image, '/api/image/<string:title_sanitized>')

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)