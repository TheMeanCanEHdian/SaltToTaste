import os
from datetime import datetime
from collections import OrderedDict
from urllib.parse import urlparse, urljoin
from flask import current_app, Blueprint, render_template, request, send_file, safe_join, abort, session, url_for, redirect, flash, send_from_directory
from flask_login import login_user, logout_user, current_user
from werkzeug.utils import secure_filename
from werkzeug.security import check_password_hash
from saltToTaste.extensions import db
from saltToTaste.models import Recipe, Tag, Direction, Ingredient, Note, User
from saltToTaste.forms import AddRecipeForm, UpdateRecipeForm, SettingsForm, LoginForm
from saltToTaste.file_handler import create_recipe_file, save_image, delete_file, rename_file, hash_file, backup_recipe_file, backup_image_file, backup_database_file
from saltToTaste.database_handler import get_recipes, get_recipe, get_recipe_by_title_f, get_recipe_nutrition, add_recipe, update_recipe, delete_recipe, search_parser, get_user_by_id, delete_user_by_id
from saltToTaste.configparser_handler import configparser_results, update_configfile, parse_settings, decode_tags, encode_tags
from saltToTaste.decorators import require_login, require_login_recipes

main = Blueprint('main', __name__)

@main.context_processor
def read_config():
    config = configparser_results(current_app.config['CONFIG_INI'])

    return dict(
        user_exists = get_user_by_id(1),
        authentication_enabled = config.getboolean('general', 'authentication_enabled'),
        api_enabled = config.getboolean('general', 'api_enabled'),
        backups_enabled = config.getboolean('general', 'backups_enabled'),
        custom_tags = decode_tags(config)
    )

# Make sure redirect URL is on the server
def is_safe_url(target):
    ref_url = urlparse(request.host_url)
    test_url = urlparse(urljoin(request.host_url, target))
    return test_url.scheme in ('http', 'https') and ref_url.netloc == test_url.netloc

@main.route("/login", methods=['GET', 'POST'])
def login():
    form = LoginForm()

    if form.validate_on_submit():
        user = User.query.filter(User.username == form.username.data).first()
        if user and check_password_hash(user.password_hash, form.password.data):
            login_user(user, remember=form.remember.data)

            next_page = request.args.get('next')
            if next_page and is_safe_url(next_page):
                return redirect(next_page)
            else:
                return redirect(url_for('main.index'))

        else:
            flash("Login failed. Please check username and password.", 'danger')

    return render_template("login.html", form=form)

@main.route("/logout", methods=['GET'])
@require_login
def logout():
    logout_user()
    return redirect(url_for('main.index'))

@main.route("/settings", methods=['GET', 'POST'])
@require_login
def settings():
    config = configparser_results(current_app.config['CONFIG_INI'])

    user_query = get_user_by_id(1)

    form = SettingsForm()

    if form.validate_on_submit():
        config_data = form.data
        parsed_data = parse_settings(config, config_data)
        parsed_data['tags'] = encode_tags(config, form.tag_name.data, form.tag_icon.data, form.tag_color.data, form.tag_bcolor.data)

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

        update_configfile(parsed_data)
        flash('Settings saved.', 'success')

        return redirect(url_for('main.settings'))

    form.authentication_enabled.data = config['general']['authentication_enabled']
    if user_query:
        form.username.data = user_query.username
        form.password.data = '**********'
    form.userless_recipes.data = config['general']['userless_recipes']
    form.api_enabled.data = config['general']['api_enabled']
    form.api_key.data = config['general']['api_key']
    form.backups_enabled.data = config['general']['backups_enabled']
    form.backup_count.data = config['general']['backup_count']
    form.edamam_id.data = config['third_party']['edamam_id']
    form.edamam_key.data = config['third_party']['edamam_key']

    return render_template("settings.html", form=form)

@main.route("/", methods=['GET', 'POST'])
@require_login_recipes
def index():
    recipes = sorted(get_recipes(), key = lambda i: i['title'])

    if request.method == 'POST':
        search_data = request.form.getlist('taggles[]')
        if search_data:
            results = search_parser(search_data)
            return render_template("index.html", recipes=results)

    return render_template("index.html", recipes=recipes)

@main.route("/recipe/<string:title_formatted>")
@require_login_recipes
def recipe(title_formatted):
    recipe = get_recipe_by_title_f(title_formatted)
    nutrition = get_recipe_nutrition(recipe['id'])

    if recipe:
        if not recipe['servings'] or recipe['servings'] <= 0:
            recipe['servings'] = 1
        # Set nutrition structure to stop Jinja template from breaking if there is no entry in nutrition table
        if nutrition == None:
            nutrition = {'nutrients':{}, 'daily':{}}
        return render_template("recipe.html", recipe=recipe, nutrition=nutrition)

    abort(404)

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
            'tags' : [tag.strip(' ').lower() for tag in tags],
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
@require_login
def update(recipe_id):
    # Class to convert recipe dict to obj
    class Struct:
        def __init__(self, **entries):
            self.__dict__.update(entries)

    config = configparser_results(current_app.config['CONFIG_INI'])
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
            if config.getboolean('general', 'backups_enabled'):
                backup_image_file(recipe_query['image'])

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
            'tags' : [tag.strip(' ').lower() for tag in tags],
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

        if config.getboolean('general', 'backups_enabled'):
            backup_recipe_file(recipe_query['filename'])
            backup_database_file()

        create_recipe_file(current_app.config['RECIPE_FILES'], recipe)
        file = os.path.join(current_app.config['RECIPE_FILES'], recipe['filename'])
        recipe['file_hash'] = hash_file(file)
        update_recipe(recipe_query['filename'], recipe_query['title'], recipe)

        return redirect(url_for('main.recipe', title_formatted=recipe['title_formatted']))

    return render_template("update.html", form=form, id=recipe_query['id'], image=recipe_query['image'])

@main.route("/delete/<int:recipe_id>", methods=['GET'])
@require_login
def delete(recipe_id):
    recipe_query = get_recipe(recipe_id)
    config = configparser_results(current_app.config['CONFIG_INI'])

    if recipe_query:
        if config.getboolean('general', 'backups_enabled'):
            backup_recipe_file(recipe_query['filename'])
            backup_database_file()

        delete_file(current_app.config['RECIPE_FILES'], recipe_query['filename'])
        if 'image' in recipe_query and recipe_query['image'] != None:
            if config.getboolean('general', 'backups_enabled'):
                backup_image_file(recipe_query['image'])

            delete_file(current_app.config['RECIPE_IMAGES'], recipe_query['image'])
        delete_recipe(recipe_id)

        flash(f"Recipe \"{recipe_query['title']}\" deleted.", 'success')
        return redirect(url_for('main.index'))

    flash("Recipe not deleted, ID not found.", 'danger')
    return redirect(url_for('main.index'))
