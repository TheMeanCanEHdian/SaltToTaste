from saltToTaste.extensions import db
from saltToTaste.models import Recipe, Tag, Ingredient, Direction, Note

def get_recipes():
    recipes = Recipe.query.all()
    return [recipe.api_model() for recipe in recipes]

def get_recipe(recipe_id):
    recipe = Recipe.query.get(recipe_id)
    try:
        return recipe.api_model()
    except:
        return False

def get_recipe_by_title(title):
    recipe = Recipe.query.filter(Recipe.title == title).first()
    try:
        return recipe.api_model()
    except:
        return False

def get_recipe_by_title_f(title_formatted):
    recipe = Recipe.query.filter(Recipe.title_formatted == title_formatted).first()
    try:
        return recipe.api_model()
    except:
        return False

def check_for_duplicate_title(id, title):
    result = Recipe.query.filter(Recipe.title == title, Recipe.id != id).first()
    if result:
        return True
    return False

def add_recipe(recipe_data):
    if not Recipe.query.filter(Recipe.filename == recipe_data['filename']).first():
        print (f' + Inserting {recipe_data["filename"]} into database')
        recipe = Recipe(layout=recipe_data['layout'], title=recipe_data['title'], title_formatted=recipe_data['title'].lower().replace(' ', '_'))
        if recipe_data['image']:
            recipe.image_path = recipe_data['image']
        if recipe_data['imagecredit']:
            recipe.image_credit = recipe_data['imagecredit']
        if recipe_data['source']:
            recipe.source = recipe_data['source']
        if recipe_data['description']:
            recipe.description = recipe_data['description']
        if recipe_data['prep']:
            recipe.prep = recipe_data['prep']
        if recipe_data['cook']:
            recipe.cook = recipe_data['cook']
        if recipe_data['ready']:
            recipe.ready = recipe_data['ready']
        if recipe_data['servings']:
            recipe.servings = recipe_data['servings']
        if recipe_data['calories']:
            recipe.calories = recipe_data['calories']
        if recipe_data['last_modified']:
            recipe.file_last_modified = recipe_data['last_modified']
        if recipe_data['filename']:
            recipe.filename = recipe_data['filename']
        db.session.add(recipe)

        if recipe_data['tags']:
            for t in recipe_data['tags']:
                if not Tag.query.filter(Tag.name == t).first():
                    tag = Tag(name=t)
                    db.session.add(tag)
                # Create Recipe-Tag mapping (creates entry in recipe_tag_assoc)
                tag = Tag.query.filter(Tag.name == t).first()
                recipe.tags.append(tag)

            if recipe_data['ingredients']:
                for i in recipe_data['ingredients']:
                    if not Ingredient.query.filter(Ingredient.name == i).first():
                        ingredient = Ingredient(name=i)
                        db.session.add(ingredient)
                    ingredient = Ingredient.query.filter(Ingredient.name == i).first()
                    recipe.ingredients.append(ingredient)

            if recipe_data['directions']:
                for d in recipe_data['directions']:
                    if not Direction.query.filter(Direction.name == d).first():
                        direction = Direction(name=d)
                        db.session.add(direction)
                    direction = Direction.query.filter(Direction.name == d).first()
                    recipe.directions.append(direction)

            if recipe_data['notes']:
                for n in recipe_data['notes']:
                    if not Note.query.filter(Note.name == n).first():
                        note = Note(name=n)
                        db.session.add(note)
                    note = Note.query.filter(Note.name == n).first()
                    recipe.notes.append(note)

        db.session.commit()

def delete_recipe(id):
    recipe = Recipe.query.filter(Recipe.id == id).first()
    if recipe:
        print (f' - Removing {recipe.title} from database')

        recipe.tags.clear()
        recipe.ingredients.clear()
        recipe.directions.clear()
        recipe.notes.clear()

        Recipe.query.filter(Recipe.id == id).delete()
        db.session.commit()
        return True

    return False

def delete_recipe_by_filename(filename):
    recipe = Recipe.query.filter(Recipe.filename == filename).first()
    delete_recipe(recipe.id)

def update_recipe(old_data, updated_data):
    print (f' + Updating {old_data["title"]}')
    recipe_query = Recipe.query.filter(Recipe.filename == old_data['filename']).first()

    recipe_query.layout = updated_data['layout']
    recipe_query.title = updated_data['title']
    recipe_query.title_formatted = updated_data['formatted_title']
    recipe_query.filename = updated_data['filename']
    recipe_query.image_path = updated_data['image']
    recipe_query.source = updated_data['source'] or None
    recipe_query.prep = updated_data['prep'] or None
    recipe_query.cook = updated_data['cook'] or None
    recipe_query.ready = updated_data['ready'] or None
    recipe_query.servings = updated_data['servings'] or None
    recipe_query.calories = updated_data['calories'] or None
    recipe_query.description = updated_data['description'] or None
    recipe_query.file_last_modified = updated_data['last_modified']
    recipe_query.tags.clear()
    recipe_query.ingredients.clear()
    recipe_query.directions.clear()
    recipe_query.notes.clear()

    for t in updated_data['tags']:
        if not Tag.query.filter(Tag.name == t).first():
            tag = Tag(name=t)
            db.session.add(tag)
        tag = Tag.query.filter(Tag.name == t).first()
        recipe_query.tags.append(tag)

    for i in updated_data['ingredients']:
        if not Ingredient.query.filter(Ingredient.name == i).first():
            ingredient = Ingredient(name=i)
            db.session.add(ingredient)
        ingredient = Ingredient.query.filter(Ingredient.name == i).first()
        recipe_query.ingredients.append(ingredient)

    for d in updated_data['directions']:
        if not Direction.query.filter(Direction.name == d).first():
            direction = Direction(name=d)
            db.session.add(direction)
        direction = Direction.query.filter(Direction.name == d).first()
        recipe_query.directions.append(direction)

    for n in updated_data['notes']:
        if not Note.query.filter(Note.name == n).first():
            note = Note(name=n)
            db.session.add(note)
        note = Note.query.filter(Note.name == n).first()
        recipe_query.notes.append(note)

    db.session.commit()

def update_recipes(recipe_list):
    print (' * Checking for altered recipes')
    for recipe in recipe_list:
        recipe_query = Recipe.query.filter(Recipe.filename == recipe['filename']).first()
        if recipe_query.file_last_modified != recipe['last_modified']:
            # This will work for now since its has the same name on lookup
            update_recipe(recipe, recipe)

def add_all_recipes(recipe_list):
    print (' * Initial insert of recipes')
    for recipe in recipe_list:
        add_recipe(recipe)

def add_new_recipes(recipe_list):
    print (' * Checking for new recipes')
    db_recipes = [x.filename for x in Recipe.query.all()]
    for recipe in recipe_list:
        if recipe['filename'] not in db_recipes:
            add_recipe(recipe)

def remove_missing_recipes(recipe_list):
    print (' * Checking for missing recipes to remove')
    db_recipes = [x.filename for x in Recipe.query.all()]
    recipe_files = [x['filename'] for x in recipe_list]
    for filename in db_recipes:
        if filename not in recipe_files:
            delete_recipe_by_filename(filename)

def db_cleanup():
    print (f' * Cleaning up database')
    tags = Tag.query.all()
    ingredients = Ingredient.query.all()
    directions = Direction.query.all()
    notes = Note.query.all()

    if tags:
        for t in tags:
            if not t.recipe:
                Tag.query.filter(Tag.id == t.id).delete()
    if ingredients:
        for i in ingredients:
            if not i.recipe:
                Ingredient.query.filter(Ingredient.id == i.id).delete()
    if directions:
        for d in directions:
            if not d.recipe:
                Direction.query.filter(Direction.id == d.id).delete()
    if notes:
        for n in notes:
            if not n.recipe:
                Note.query.filter(Note.id == n.id).delete()
    db.session.commit()
