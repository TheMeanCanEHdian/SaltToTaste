import os
from datetime import datetime
from collections import OrderedDict
from flask import current_app, Blueprint, render_template, request, send_file, safe_join, abort, session, url_for, redirect, flash, send_from_directory
from flask_login import login_user, logout_user, current_user
from werkzeug.utils import secure_filename
from saltToTaste.extensions import db
from saltToTaste.models import Recipe, Tag, Direction, Ingredient, Note, User
from saltToTaste.forms import AddRecipeForm, UpdateRecipeForm, SettingsForm, LoginForm
from saltToTaste.file_handler import create_recipe_file, save_image, delete_file, rename_file, hash_file, update_configfile
from saltToTaste.database_handler import get_recipes, get_recipe, get_recipe_by_title_f, add_recipe, update_recipe, delete_recipe, search_parser, get_user, get_user_by_id, delete_user_by_id
from saltToTaste.parser_handler import configparser_results
from saltToTaste.decorators import require_login

main = Blueprint('main', __name__)

@main.route("/login", methods=['GET', 'POST'])
def login():
    form = LoginForm()

    if form.validate_on_submit():
        user = get_user(form.username.data, form.password.data)

    return render_template("login.html", form=form)

@main.route("/logout", methods=['GET'])
def logout():
    pass

@main.route("/settings", methods=['GET', 'POST'])
def settings():
    config = configparser_results(current_app.config['CONFIG_INI'])

    user_query = get_user_by_id(1)

    form = SettingsForm()

    if request.method == 'GET':
        form.authentication_enabled.data = config['general']['authentication_enabled']
        if user_query:
            form.username.data = user_query.username
            form.password.data = '**********'
        form.userless_recipes.data = config['general']['userless_recipes']
        form.userless_download.data = config['general']['userless_download']
        form.api_enabled.data = config['general']['api_enabled']
        form.api_key.data = config['general']['api_key']

    if form.validate_on_submit():
        if user_query and form.username.data != '' and form.password.data != ('**********' or ''):
            print ('user_query was true, form had username, password was not placeholder. UPDATING USER.')
            user_query.username = form.username.data
            user_query.password = form.password.data
            db.session.commit()

        elif not user_query and form.username.data != '' and form.password.data !='':
            print ('user_query was false, form had username, form had password. ADDING USER')
            user = User(username=form.username.data, password=form.password.data, role='admin')
            db.session.add(user)
            db.session.commit()

        elif user_query and form.username.data == '' and form.password.data == '':
            print ('username and password removed. DELETING USER')
            delete_user_by_id(user_query.id)

        update_configfile(current_app.config['CONFIG_INI'], form.data, 'general')
        flash('Settings saved.', 'success')

        return redirect(url_for('main.settings'))

    return render_template("settings.html", form=form)

@main.route("/", methods=['GET', 'POST'])
def index():
    recipes = sorted(get_recipes(), key = lambda i: i['title'])

    if request.method == 'POST':
        search_data = request.form.getlist('taggles[]')
        if search_data:
            results = search_parser(search_data)
            return render_template("index.html", recipes=results)

    return render_template("index.html", recipes=recipes)

@main.route("/recipe/<string:title_formatted>")
def recipe(title_formatted):
    recipe = get_recipe_by_title_f(title_formatted)

    return render_template("recipe.html", recipe=recipe)

@main.route("/download/<path:filename>")
def download_recipe(filename):
    filename = filename.lower()
    safe_path = safe_join(current_app.config["RECIPE_FILES"], filename)
    try:
        return send_file(safe_path, as_attachment=True, attachment_filename=filename)
    except FileNotFoundError:
        abort(404)

@main.route("/image/<path:filename>", methods=['GET'])
def image(filename):
    return send_from_directory(current_app.config["RECIPE_IMAGES"], filename)

@main.route("/add", methods=['GET', 'POST'])
@require_login
def add():
    form = AddRecipeForm()

    if form.validate_on_submit():
        title_formatted = form.title.data.replace(" ", "-").lower()
        image_data = form.image.data
        filename = f"{title_formatted}.yaml"
        tags = form.tags.data.split(',')

        while("" in tags) :
            tags.remove("")

        if image_data:
            ext = image_data.filename.rsplit('.', 1)[1].lower()
            image_data.filename = f'{title_formatted}.{ext}'
            image = secure_filename(image_data.filename)
            save_image(current_app.config['RECIPE_IMAGES'], image, image_data)
        else:
            image = None

        recipe = OrderedDict({
            'layout' : form.layout.data or 'recipe',
            'title' : form.title.data,
            'title_formatted' : title_formatted,
            'image' : image,
            'imagecredit' : form.imagecredit.data or None,
            'tags' : [tag.strip(' ') for tag in tags],
            'source' : form.source.data or None,
            'prep' : form.prep.data or None,
            'cook' : form.cook.data or None,
            'ready' : form.ready.data or None,
            'servings' : form.servings.data or None,
            'calories' : form.calories.data or None,
            'description' : form.calories.data or None,
            'ingredients' : [x for x in form.ingredients.data if x != ''],
            'directions' : [x for x in form.directions.data if x != ''],
            'notes' : [x for x in form.notes.data if x != ''],
            'filename' : filename
        })

        create_recipe_file(current_app.config['RECIPE_FILES'], recipe)
        file = os.path.join(current_app.config['RECIPE_FILES'], filename)
        recipe['file_hash'] = hash_file(file)
        add_recipe(recipe)

        if form.save.data:
            return redirect(url_for('main.recipe', title_formatted=title_formatted))
        if form.save_and_add.data:
            flash(f'Recipe {form.title.data} saved.', 'success')
            return redirect(url_for("main.add"))

    return render_template("add.html", form=form)

@main.route("/update/<int:recipe_id>", methods=['GET', 'POST'])
def update(recipe_id):
    # Class to convert recipe dict to obj
    class Struct:
        def __init__(self, **entries):
            self.__dict__.update(entries)

    recipe_query = get_recipe(recipe_id)

    if not recipe_query:
        abort(404)

    recipe_query['tags'] = ", ".join(recipe_query['tags'])
    recipe_obj = Struct(**recipe_query)
    form = UpdateRecipeForm(obj=recipe_obj)

    if form.validate_on_submit():
        title_formatted = form.title.data.replace(" ", "-").lower()
        filename = f"{title_formatted}.yaml"
        image_data = form.image.data
        tags = form.tags.data.split(',')

        while("" in tags) :
            tags.remove("")

        if hasattr(image_data, 'filename'):
            ext_new = image_data.filename.rsplit('.', 1)[1].lower()
            ext_old = recipe_query['image'].rsplit('.', 1)[1].lower

            if ext_new != ext_old:
                delete_file(current_app.config['RECIPE_IMAGES'], recipe_query['image'])

            image_data.filename = f'{title_formatted}.{ext_new}'
            image = secure_filename(image_data.filename)
            save_image(current_app.config['RECIPE_IMAGES'], image, image_data)
        else:
            image = recipe_query['image']

        recipe = OrderedDict({
            'layout' : form.layout.data or recipe_query['layout'],
            'title' : form.title.data,
            'title_formatted' : title_formatted,
            'image' : image,
            'imagecredit' : form.imagecredit.data or None,
            'tags' : [tag.strip(' ') for tag in tags],
            'source' : form.source.data or None,
            'prep' : form.prep.data or None,
            'cook' : form.cook.data or None,
            'ready' : form.ready.data or None,
            'servings' : form.servings.data or None,
            'calories' : form.calories.data or None,
            'description' : form.description.data or None,
            'ingredients' : [x for x in form.ingredients.data if x != ''],
            'directions' : [x for x in form.directions.data if x != ''],
            'notes' : [x for x in form.notes.data if x != ''],
            'filename' : filename
        })

        if recipe['title'] != recipe_query['title']:
            if recipe['title_formatted'] != recipe_query['title_formatted']:
                # Rename image
                ext = image.rsplit('.', 1)[1].lower()
                updated_filename = f'{title_formatted}.{ext}'
                secure_file = secure_filename(updated_filename)
                rename_file(os.path.join(current_app.config['RECIPE_IMAGES'], image), os.path.join(current_app.config['RECIPE_IMAGES'], secure_file))
                recipe['image'] = secure_file

            # Rename file
            rename_file(os.path.join(current_app.config['RECIPE_FILES'], recipe_query['filename']), os.path.join(current_app.config['RECIPE_FILES'], recipe['filename']))

        create_recipe_file(current_app.config['RECIPE_FILES'], recipe)
        file = os.path.join(current_app.config['RECIPE_FILES'], recipe['filename'])
        recipe['file_hash'] = hash_file(file)
        update_recipe(recipe_query['filename'], recipe_query['title'], recipe)

        return redirect(url_for('main.recipe', title_formatted=recipe['title_formatted']))

    return render_template("update.html", form=form, id=recipe_query['id'], image=recipe_query['image'])
