import os
from datetime import datetime
from flask import current_app, Blueprint, render_template, request, send_file, safe_join, abort, session, url_for, redirect, flash, send_from_directory
from flask_login import login_user, logout_user, current_user, login_required
from werkzeug.utils import secure_filename
from saltToTaste.extensions import db
from saltToTaste.models import Recipe, Tag, Direction, Ingredient, Note
from saltToTaste.forms import AddRecipeForm, UpdateRecipeForm
from saltToTaste.search_handler import search_parser
from saltToTaste.recipe_handler import add_recipe_file, delete_recipe_file
from saltToTaste.database_handler import get_recipes, get_recipe, get_recipe_by_title_f, add_recipe, update_recipe, delete_recipe
from saltToTaste.parser_handler import argparser_results

argument = argparser_results()
DATA_DIR = os.path.abspath(argument['DATA_DIR'])

main = Blueprint('main', __name__)

@main.route("/", methods=['GET', 'POST'])
def index():
    recipes = sorted(get_recipes(), key = lambda i: i['title'])

    if request.method == 'POST':
        search_data = request.form.getlist('taggles[]')
        if search_data:
            results = search_parser(search_data)
            return render_template("index.html", recipes=results)

    return render_template("index.html", recipes=recipes)

@main.route("/recipe/<string:recipe_link>")
def recipe(recipe_link):
    recipe = get_recipe_by_title_f(recipe_link)

    return render_template("recipe.html", recipe=recipe)

@main.route("/download/<path:filename>")
# @login_required
def download_recipe(filename):
    filename = filename.lower()
    safe_path = safe_join(current_app.config["RECIPE_FILES"], filename)
    try:
        return send_file(safe_path, as_attachment=True, attachment_filename=filename)
    except FileNotFoundError:
        abort(404)

@main.route("/image/<path:filename>", methods=['GET'])
def image_path(filename):
    return send_from_directory(current_app.config["RECIPE_IMAGES"], filename)

@main.route("/add", methods=['GET', 'POST'])
def add():
    form = AddRecipeForm()

    if form.validate_on_submit():
        title_formatted = form.title.data.replace(" ", "_").lower()
        image = form.image.data

        if image:
            image_extension = image.filename.rsplit('.', 1)[1].lower()
            image.filename = f'{title_formatted}.{image_extension}'
            filename = secure_filename(image.filename)
            image.save(os.path.join(current_app.config['RECIPE_IMAGES'], filename))
        else:
            filename = None

        tags = form.tags.data.split(',')
        # Remove empty strings from tags that are a result of no tags in form
        while("" in tags) :
            tags.remove("")

        print (tags)

        recipe = {
            'layout' : form.layout.data or 'recipe',
            'title' : form.title.data,
            'formatted_title' : title_formatted,
            'image' : filename,
            'imagecredit' : form.image_credit.data, # this is the link to image to download
            'tags' : [tag.strip(' ') for tag in tags],
            'source' : form.source.data,
            'prep' : form.prep.data,
            'cook' : form.cook.data,
            'ready' : form.ready.data,
            'servings' : form.servings.data,
            'calories' : form.calories.data,
            'description' : form.description.data,
            'ingredients' : form.ingredients.data,
            'directions' : form.directions.data,
            'notes' : form.notes.data,
            'filename' : f'{title_formatted}.txt'
        }

        add_recipe_file(recipe)
        recipe['last_modified'] = datetime.fromtimestamp(os.stat(f'{DATA_DIR}/_recipes/{recipe["filename"]}').st_mtime)
        add_recipe(recipe)

        if form.save.data:
            return redirect(url_for('main.recipe', recipe_link=title_formatted))
        if form.save_and_add.data:
            flash(f'Recipe {form.title.data} saved.', 'success')
            return redirect(url_for("main.add"))

    return render_template("add.html", form=form)

@main.route("/update/<int:recipe_id>", methods=['GET', 'POST'])
def update(recipe_id):
    # Class to convert recipe dict to string
    class Struct:
        def __init__(self, **entries):
            self.__dict__.update(entries)

    recipe_dict = get_recipe(recipe_id)

    if not recipe_dict:
        abort(404)

    recipe_dict['tags'] = ", ".join(recipe_dict['tags'])

    recipe_obj = Struct(**recipe_dict)

    form = UpdateRecipeForm(obj=recipe_obj)

    if form.validate_on_submit():
        title_formatted = form.title.data.replace(" ", "_").lower()
        image = form.image.data

        if image:
            image_extension = image.filename.rsplit('.', 1)[1].lower()
            image.filename = f'{title_formatted}.{image_extension}'
            filename = secure_filename(image.filename)
            image.save(os.path.join(current_app.config['RECIPE_IMAGES'], filename))
        else:
            filename = recipe_dict['image_path']

        if form.tags.data:
            tags = form.tags.data.split(',')
        else:
            tags = []

        recipe = {
            'layout' : form.layout.data or 'recipe',
            'title' : form.title.data,
            'formatted_title' : title_formatted,
            'image' : filename,
            'imagecredit' : form.image_credit.data, # this is the link to image to download
            'tags' : [tag.strip(' ') for tag in tags],
            'source' : form.source.data,
            'prep' : form.prep.data,
            'cook' : form.cook.data,
            'ready' : form.ready.data,
            'servings' : form.servings.data,
            'calories' : form.calories.data,
            'description' : form.description.data,
            'ingredients' : form.ingredients.data,
            'directions' : form.directions.data,
            'notes' : form.notes.data,
            'filename' : f'{title_formatted}.txt'
        }

        if form.title.data != recipe_dict['title']:
            if title_formatted != recipe_dict['title_formatted']:
                extension = filename.rsplit('.', 1)[1].lower()
                new_filename = f'{title_formatted}.{extension}'
                secure_name = secure_filename(new_filename)
                os.rename(os.path.join(current_app.config['RECIPE_IMAGES'], filename), os.path.join(current_app.config['RECIPE_IMAGES'], secure_name))
                recipe['image'] = secure_name

            # Rename file
            os.rename(os.path.join(current_app.config['RECIPE_FILES'], recipe_dict['filename']), os.path.join(current_app.config['RECIPE_FILES'], recipe['filename']))
            add_recipe_file(recipe)
            recipe['last_modified'] = datetime.fromtimestamp(os.stat(f'{DATA_DIR}/_recipes/{recipe["filename"]}').st_mtime)
            update_recipe(recipe_dict, recipe)

        add_recipe_file(recipe)
        recipe['last_modified'] = datetime.fromtimestamp(os.stat(f'{DATA_DIR}/_recipes/{recipe["filename"]}').st_mtime)
        update_recipe(recipe_dict, recipe)

        return redirect(url_for('main.recipe', recipe_link=title_formatted))

    return render_template("update.html", form=form, id=recipe_dict['id'], image_path=recipe_dict['image_path'])
