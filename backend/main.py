from flask import Flask, send_file, send_from_directory
from flask_cors import CORS
from flask_restful import Api, Resource, reqparse, abort, fields, marshal_with
from flask_sqlalchemy import SQLAlchemy

from core.database.datasources.database import Database
from core.database.models.recipe_model import Recipe
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

recipe_database_handler.add_recipe_files_to_db(recipe_files_handler.load())


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


class Recipes(Resource):
    def get(self):
        return {
            'result': 'success',
            'data': database_handler.get_recipes(),
        }, 200


class Image(Resource):
    #TODO: Need to allow images to be resized
    def get(self, title_sanitized):
        image_name = database_handler.get_recipe_image(title_sanitized)

        return send_from_directory(
            app.config['RECIPE_IMAGES'],
            filename=image_name,
        )


api.add_resource(Recipes, '/api/recipes')
api.add_resource(Recipe, '/api/recipe/<string:title_sanitized>')
api.add_resource(Image, '/api/image/<string:title_sanitized>')

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)