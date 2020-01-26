import os
import argparse
from datetime import datetime
from functools import wraps
from collections import OrderedDict
from flask import current_app, Blueprint, jsonify, request, abort
from werkzeug.utils import secure_filename
from . import api_key
from saltToTaste.models import Recipe
from saltToTaste.database_handler import get_recipes, get_recipe, delete_recipe, add_recipe, update_recipe, search_parser, check_for_duplicate_title_f
from saltToTaste.file_handler import delete_file, create_recipe_file, download_image, rename_file, hash_file

api = Blueprint('api', __name__)

# Create decorator to require API key
def require_apikey(view_function):
    @wraps(view_function)
    def decorated_function(*args, **kwargs):
        if request.headers.get('X-Salt-to-Taste-API-Key') and request.headers.get('X-Salt-to-Taste-API-Key') == api_key:
            return view_function(*args, **kwargs)
        else:
            abort(401)
    return decorated_function

@api.route('/recipe', methods=['GET'])
@require_apikey
def get_recipes_json():
    return jsonify({'recipes' : get_recipes()})

@api.route('/recipe/<int:recipe_id>', methods=['GET'])
@require_apikey
def get_recipe_json(recipe_id):
    recipe = get_recipe(recipe_id)
    if recipe is False:
        return jsonify({'error' : 'ID not found'})
    else:
        return jsonify({'recipe' : recipe})

@api.route('/search', methods=['GET'])
@require_apikey
def search_parser_json():
    search_data = request.args.get('data').split(',')
    search_data = [x.strip(' ') for x in search_data]
    return jsonify({'recipe' : search_parser(search_data)})

@api.route('/add', methods=['POST'])
@require_apikey
def add_recipe_json():
    data = request.get_json()
    downloadImage = request.args.get('downloadImage')

    if not data.get('layout'):
        return jsonify({'error' : 'layout missing'})

    if not data.get('title'):
        return jsonify({'error' : 'title missing'})

    title_formatted = data.get('title').replace(" ", "-").lower()
    filename = f'{title_formatted}.yaml'

    recipe = OrderedDict({
        'layout' : data.get('layout'),
        'title' : data.get('title'),
        'title_formatted' : title_formatted,
        'image' : data.get('image'),
        'imagecredit' : data.get('imagecredit'),
        'tags' : data.get('tags'),
        'source' : data.get('source'),
        'prep' : data.get('prep'),
        'cook' : data.get('cook'),
        'ready' : data.get('ready'),
        'servings' : data.get('servings'),
        'calories' : data.get('calories'),
        'description' : data.get('description'),
        'ingredients' : data.get('ingredients'),
        'directions' : data.get('directions'),
        'notes' : data.get('notes'),
        'filename' : filename
    })

    if downloadImage:
        if downloadImage != "true":
            return jsonify({'error' : 'downloadImage set but has invalid value'})
        if not recipe['imagecredit']:
            return jsonify({'error' : 'downloadImage set but imagecredit is empty'})
        image = download_image(recipe['imagecredit'], current_app.config['RECIPE_IMAGES'], recipe['title_formatted'])
        if not image:
            return jsonify({'error' : 'image download failed', 'message' : 'check imagecredit value'})
        recipe['image'] = image

    create_recipe_file(current_app.config['RECIPE_FILES'], recipe)
    file = os.path.join(current_app.config['RECIPE_FILES'], recipe['filename'])
    recipe['file_hash'] = hash_file(file)
    add_recipe(recipe)

    return jsonify({'success' : 'Recipe added'})

@api.route('/update/<int:recipe_id>', methods=['PUT'])
@require_apikey
def update_recipes_json(recipe_id):
    data = request.get_json()
    downloadImage = request.args.get('downloadImage')

    recipe_query = get_recipe(recipe_id)

    if not recipe_query:
        return jsonify({'error' : 'recipe ID not found'})

    if not data.get('layout'):
        return jsonify({'error' : 'layout missing'})

    if not data.get('title'):
        return jsonify({'error' : 'title missing'})

    title_formatted = data.get('title').replace(" ", "-").lower()
    filename = f'{title_formatted}.yaml'

    if check_for_duplicate_title_f(recipe_id, title_formatted):
        return jsonify({'error' : 'recipe name must be unique'})

    recipe = OrderedDict({
        'layout' : data.get('layout'),
        'title' : data.get('title'),
        'title_formatted' : title_formatted,
        'image' : data.get('image'),
        'imagecredit' : data.get('imagecredit'),
        'tags' : data.get('tags'),
        'source' : data.get('source'),
        'prep' : data.get('prep'),
        'cook' : data.get('cook'),
        'ready' : data.get('ready'),
        'servings' : data.get('servings'),
        'calories' : data.get('calories'),
        'description' : data.get('description'),
        'ingredients' : data.get('ingredients'),
        'directions' : data.get('directions'),
        'notes' : data.get('notes'),
        'filename' : filename
    })

    if downloadImage:
        if downloadImage != "true":
            return jsonify({'error' : 'downloadImage set but has invalid value'})
        if not recipe['imagecredit']:
            return jsonify({'error' : 'downloadImage set but imagecredit is empty'})
        image = download_image(recipe['imagecredit'], current_app.config['RECIPE_IMAGES'], recipe['title_formatted'])
        if not image:
            return jsonify({'error' : 'image download failed', 'message' : 'check imagecredit value'})
        recipe['image'] = image

    if recipe['title'] != recipe_query['title']:
        if recipe['title_formatted'] != recipe_query['title_formatted']:
            # Rename image
            ext = recipe['image'].rsplit('.', 1)[1].lower()
            updated_filename = f'{title_formatted}.{ext}'
            secure_file = secure_filename(updated_filename)
            rename_file(os.path.join(current_app.config['RECIPE_IMAGES'], recipe_query['image']), os.path.join(current_app.config['RECIPE_IMAGES'], secure_file))
            recipe['image'] = secure_file

        # Rename file
        rename_file(os.path.join(current_app.config['RECIPE_FILES'], recipe_query['filename']), os.path.join(current_app.config['RECIPE_FILES'], recipe['filename']))

    create_recipe_file(current_app.config['RECIPE_FILES'], recipe)
    file = os.path.join(current_app.config['RECIPE_FILES'], recipe['filename'])
    recipe['file_hash'] = hash_file(file)
    update_recipe(recipe_query['filename'], recipe_query['title'], recipe)

    return jsonify({'success' : 'recipe updated'})

@api.route('/delete/<int:recipe_id>', methods=['DELETE'])
@require_apikey
def delete_recipe_json(recipe_id):
    recipe_query = get_recipe(recipe_id)

    if recipe_query:
        delete_file(current_app.config['RECIPE_FILES'], recipe_query['filename'])
        if 'image' in recipe_query:
            delete_file(current_app.config['RECIPE_IMAGES'], recipe_query['image'])
        delete_recipe(recipe_id)

        return jsonify({'success' : 'recipe deleted'})

    return jsonify({'error' : 'recipe ID not found'})
