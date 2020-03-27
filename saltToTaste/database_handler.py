from collections import defaultdict
from datetime import datetime
from saltToTaste.extensions import db
from saltToTaste.models import Recipe, Nutrition, Tag, Ingredient, Direction, Note, User
from saltToTaste.nutrition import fetch_recipe_nutrition

def get_users():
    users = User.query.all()
    return users

def get_user_by_id(id):
    user = User.query.get(id)
    return user

def delete_user_by_id(id):
    User.query.filter(User.id == id).delete()
    db.session.commit()

def get_recipes():
    recipes = Recipe.query.all()
    return [recipe.api_model() for recipe in recipes]

def get_recipe(id):
    recipe = Recipe.query.get(id)
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

def get_recipe_nutrition(recipe_id):
    nutrition = Nutrition.query.filter(Nutrition.recipe_id == recipe_id).first()
    try:
        return nutrition.api_model()
    except:
        False

def check_for_duplicate_title_f(id, title_formatted):
    result = Recipe.query.filter(Recipe.title_formatted == title_formatted, Recipe.id != id).first()
    if result:
        return True
    return False

def add_recipe(recipe_data):
    query = Recipe.query.filter(Recipe.title_formatted == recipe_data['title_formatted']).first()
    if not query:
        print (f" + Inserting {recipe_data['title']} into database.")
        recipe = Recipe(
            layout=recipe_data['layout'],
            title=recipe_data['title'],
            title_formatted=recipe_data['title_formatted'],
            filename = recipe_data['filename']
        )
        recipe.image = recipe_data.get('image')
        recipe.imagecredit = recipe_data.get('imagecredit')
        recipe.source = recipe_data.get('source')
        recipe.description = recipe_data.get('description')
        recipe.prep = recipe_data.get('prep')
        recipe.cook = recipe_data.get('cook')
        recipe.ready = recipe_data.get('ready')
        recipe.servings = recipe_data.get('servings')
        recipe.calories = recipe_data.get('calories')
        recipe.file_hash = recipe_data.get('file_hash')

        db.session.add(recipe)

        if recipe_data['tags']:
            tags = Tag.query.filter(Tag.name.in_(recipe_data['tags']))

            for t in recipe_data['tags']:
                tag = next(iter([item for item in tags if item.name == t]), None)
                if not tag:
                    tag = Tag(name=t)
                    db.session.add(tag)
                # Create Recipe-Tag mapping (creates entry in recipe_tag_assoc)
                recipe.tags.append(tag)

        if recipe_data['ingredients']:
            ingredients = Ingredient.query.filter(Ingredient.name.in_(recipe_data['ingredients']))

            for i in recipe_data['ingredients']:
                ingredient = next(iter([item for item in ingredients if item.name == i]), None)
                if not ingredient:
                    ingredient = Ingredient(name=i)
                    db.session.add(ingredient)
                recipe.ingredients.append(ingredient)

            update_nutrition(recipe.id, recipe.title, recipe_data['ingredients'], recipe.servings)

        if recipe_data['directions']:
            directions = Direction.query.filter(Direction.name.in_(recipe_data['directions']))

            for d in recipe_data['directions']:
                direction = next(iter([item for item in directions if item.name == d]), None)
                if not direction:
                    direction = Direction(name=d)
                    db.session.add(direction)
                recipe.directions.append(direction)

        if recipe_data['notes']:
            notes = Note.query.filter(Note.name.in_(recipe_data['notes']))

            for n in recipe_data['notes']:
                note = next(iter([item for item in notes if item.name == n]), None)
                if not note:
                    note = Note(name=n)
                    db.session.add(note)
                recipe.notes.append(note)

        db.session.commit()
        return True

    return False

def delete_recipe(id):
    recipe = Recipe.query.get(id)
    if recipe:
        print (f' - Removing {recipe.title} from database.')

        recipe.tags.clear()
        recipe.ingredients.clear()
        recipe.directions.clear()
        recipe.notes.clear()

        Nutrition.query.filter(Nutrition.recipe_id == id).delete()
        Recipe.query.filter(Recipe.id == id).delete()
        db.session.commit()
        db_cleanup()
        return True

    return False

def delete_recipe_by_filename(filename):
    recipe = Recipe.query.filter(Recipe.filename == filename).first()
    delete_recipe(recipe.id)

def update_recipe(filename, title, updated_data):
    # Filename and title should be for the ORIGINAL data. If either is being updated this information should be from before the update.
    recipe = Recipe.query.filter(Recipe.filename == filename).first()

    if recipe:
        # Load in exisitng ingredients to determine if they have changed and a new check of nutrition is needed
        previous_ingredients = [r.name for r in recipe.ingredients]

        print (f' + Updating {title} in database.')
        recipe.layout = updated_data['layout']
        recipe.title = updated_data['title']
        recipe.title_formatted = updated_data['title_formatted']
        recipe.filename = updated_data['filename']
        recipe.image = updated_data['image'] or None
        recipe.imagecredit = updated_data['imagecredit'] or None
        recipe.source = updated_data['source'] or None
        recipe.prep = updated_data['prep'] or None
        recipe.cook = updated_data['cook'] or None
        recipe.ready = updated_data['ready'] or None
        recipe.servings = updated_data['servings'] or None
        recipe.calories = updated_data['calories'] or None
        recipe.description = updated_data['description'] or None
        recipe.file_hash = updated_data['file_hash']
        recipe.tags.clear()
        recipe.ingredients.clear()
        recipe.directions.clear()
        recipe.notes.clear()


        if updated_data['tags']:
            tags = Tag.query.filter(Tag.name.in_(updated_data['tags']))

            for t in updated_data['tags']:
                tag = next(iter([item for item in tags if item.name == t]), None)
                if not tag:
                    tag = Tag(name=t)
                    db.session.add(tag)
                # Create Recipe-Tag mapping (creates entry in recipe_tag_assoc)
                recipe.tags.append(tag)

        if updated_data['ingredients']:
            ingredients = Ingredient.query.filter(Ingredient.name.in_(updated_data['ingredients']))

            for i in updated_data['ingredients']:
                ingredient = next(iter([item for item in ingredients if item.name == i]), None)
                if not ingredient:
                    ingredient = Ingredient(name=i)
                    db.session.add(ingredient)
                recipe.ingredients.append(ingredient)

            # Determine if ingredient lists are different and update nutrition information if true
            new_ingredients = [r.name for r in recipe.ingredients]
            if (list(set(previous_ingredients)-set(new_ingredients))) or (list(set(new_ingredients)-set(previous_ingredients))):
                update_nutrition(recipe.id, recipe.title, new_ingredients, recipe.servings)


        if updated_data['directions']:
            directions = Direction.query.filter(Direction.name.in_(updated_data['directions']))

            for d in updated_data['directions']:
                direction = next(iter([item for item in directions if item.name == d]), None)
                if not direction:
                    direction = Direction(name=d)
                    db.session.add(direction)
                recipe.directions.append(direction)

        if updated_data['notes']:
            notes = Note.query.filter(Note.name.in_(updated_data['notes']))

            for n in updated_data['notes']:
                note = next(iter([item for item in notes if item.name == n]), None)
                if not note:
                    note = Note(name=n)
                    db.session.add(note)
                recipe.notes.append(note)

        db.session.commit()
        return True

    return False

def update_nutrition(recipe_id, recipe_title, ingredient_list, recipe_servings=1):
    nutrition = Nutrition.query.filter(Nutrition.recipe_id == recipe_id).first()

    if not nutrition:
        nutrition = Nutrition(recipe_id=recipe_id)

    nutrition_data = fetch_recipe_nutrition(recipe_title, recipe_servings, ingredient_list)

    if nutrition_data:
        nutrition.last_updated = datetime.now()
        nutrition.weight = nutrition_data.get('weight')
        nutrition.calcium = nutrition_data['nutrients'].get('calcium')
        nutrition.carbs = nutrition_data['nutrients'].get('carbs')
        nutrition.cholesterol = nutrition_data['nutrients'].get('cholesterol')
        nutrition.energy = nutrition_data['nutrients'].get('energy')
        nutrition.fat = nutrition_data['nutrients'].get('fat')
        nutrition.fiber = nutrition_data['nutrients'].get('fiber')
        nutrition.folate_equivalent = nutrition_data['nutrients'].get('folate_equivalent')
        nutrition.folate_food = nutrition_data['nutrients'].get('folate_food')
        nutrition.iron = nutrition_data['nutrients'].get('iron')
        nutrition.magnesium = nutrition_data['nutrients'].get('magnesium')
        nutrition.monounsaturated = nutrition_data['nutrients'].get('monounsaturated')
        nutrition.niacin_b3 = nutrition_data['nutrients'].get('niacin_b3')
        nutrition.phosphorus = nutrition_data['nutrients'].get('phosphorus')
        nutrition.polyunsaturated = nutrition_data['nutrients'].get('polyunsaturated')
        nutrition.potassium = nutrition_data['nutrients'].get('potassium')
        nutrition.protein = nutrition_data['nutrients'].get('protein')
        nutrition.riboflavin_b2 = nutrition_data['nutrients'].get('riboflavin_b2')
        nutrition.saturated = nutrition_data['nutrients'].get('saturated')
        nutrition.sodium = nutrition_data['nutrients'].get('sodium')
        nutrition.sugars = nutrition_data['nutrients'].get('sugars')
        nutrition.sugars_added = nutrition_data['nutrients'].get('sugars_added')
        nutrition.thiamin_b1 = nutrition_data['nutrients'].get('thiamin_b1')
        nutrition.trans = nutrition_data['nutrients'].get('trans')
        nutrition.vitamin_a = nutrition_data['nutrients'].get('vitamin_a')
        nutrition.vitamin_b12 = nutrition_data['nutrients'].get('vitamin_b12')
        nutrition.vitamin_b6 = nutrition_data['nutrients'].get('vitamin_b6')
        nutrition.vitamin_c = nutrition_data['nutrients'].get('vitamin_c')
        nutrition.vitamin_d = nutrition_data['nutrients'].get('vitamin_d')
        nutrition.vitamin_e = nutrition_data['nutrients'].get('vitamin_e')
        nutrition.vitamin_k = nutrition_data['nutrients'].get('vitamin_k')

        nutrition.calcium_daily = nutrition_data['daily'].get('calcium')
        nutrition.carbs_daily = nutrition_data['daily'].get('carbs')
        nutrition.cholesterol_daily = nutrition_data['daily'].get('cholesterol')
        nutrition.energy_daily = nutrition_data['daily'].get('energy')
        nutrition.fat_daily = nutrition_data['daily'].get('fat')
        nutrition.fiber_daily = nutrition_data['daily'].get('fiber')
        nutrition.folate_equivalent_daily = nutrition_data['daily'].get('folate_equivalent')
        nutrition.folate_food_daily = nutrition_data['daily'].get('folate_food')
        nutrition.iron_daily = nutrition_data['daily'].get('iron')
        nutrition.magnesium_daily = nutrition_data['daily'].get('magnesium')
        nutrition.monounsaturated_daily = nutrition_data['daily'].get('monounsaturated')
        nutrition.niacin_b3_daily = nutrition_data['daily'].get('niacin_b3')
        nutrition.phosphorus_daily = nutrition_data['daily'].get('phosphorus')
        nutrition.polyunsaturated_daily = nutrition_data['daily'].get('polyunsaturated')
        nutrition.potassium_daily = nutrition_data['daily'].get('potassium')
        nutrition.protein_daily = nutrition_data['daily'].get('protein')
        nutrition.riboflavin_b2_daily = nutrition_data['daily'].get('riboflavin_b2')
        nutrition.saturated_daily = nutrition_data['daily'].get('saturated')
        nutrition.sodium_daily = nutrition_data['daily'].get('sodium')
        nutrition.sugars_daily = nutrition_data['daily'].get('sugars')
        nutrition.sugars_added_daily = nutrition_data['daily'].get('sugars_added')
        nutrition.thiamin_b1_daily = nutrition_data['daily'].get('thiamin_b1')
        nutrition.trans_daily = nutrition_data['daily'].get('trans')
        nutrition.vitamin_a_daily = nutrition_data['daily'].get('vitamin_a')
        nutrition.vitamin_b12_daily = nutrition_data['daily'].get('vitamin_b12')
        nutrition.vitamin_b6_daily = nutrition_data['daily'].get('vitamin_b6')
        nutrition.vitamin_c_daily = nutrition_data['daily'].get('vitamin_c')
        nutrition.vitamin_d_daily = nutrition_data['daily'].get('vitamin_d')
        nutrition.vitamin_e_daily = nutrition_data['daily'].get('vitamin_e')
        nutrition.vitamin_k_daily = nutrition_data['daily'].get('vitamin_k')

        db.session.add(nutrition)
        print (f' * Nutritional information added')

def update_recipes(recipe_list):
    print (' * Checking for altered recipes')
    for recipe in recipe_list:
        query = Recipe.query.filter(Recipe.filename == recipe['filename']).first()
        if query and query.file_hash != recipe['file_hash']:
            update_recipe(recipe['filename'], query.title, recipe)

def add_all_recipes(recipe_list):
    print (' * Initial insert of recipes')
    for recipe in recipe_list:
        add_recipe(recipe)

def add_new_recipes(recipe_list):
    print (' * Checking for new recipes')
    db_recipes = [recipe.filename for recipe in Recipe.query.all()]
    for recipe in recipe_list:
        if recipe['filename'] not in db_recipes:
            add_recipe(recipe)

def remove_missing_recipes(recipe_list):
    print (' * Checking for missing recipes to remove')
    db_recipes = [recipe.filename for recipe in Recipe.query.all()]
    recipe_files = [recipe['filename'] for recipe in recipe_list]
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

def search_parser(search_data):
    # Format search data to allow for AND/OR keywords for Whoosh indexing
    formatted_data = []
    for item in search_data:
        formatted_data.append(item.lower().replace(' or ', ' OR ' ).replace(' and ', ' AND '))
    search_dict = defaultdict(list)
    # Organize search terms
    for item in formatted_data:
        if 'title:' in item:
            search_dict['title'].append(item.replace('title:', ''))
        elif 'tag:' in item:
            search_dict['tag'].append(item.replace('tag:', ''))
        elif 'ingredient:' in item:
            search_dict['ingredient'].append(item.replace('ingredient:', ''))
        elif 'direction:' in item:
            search_dict['direction'].append(item.replace('direction:', ''))
        elif 'calories' in item:
            search_dict['calories'].append(item.replace('calories:', ''))
        elif 'note' in item:
            search_dict['note'].append(item.replace('note:', ''))
        else:
            search_dict['general'].append(item)
    # Process search results
    search_results = defaultdict(list)
    if search_dict['general']:
        for item in search_dict['general']:
            query = Recipe.query.search(item).all()
            for recipe in query:
                if recipe not in search_results['general']:
                    search_results['general'].append(recipe)
    if search_dict['title']:
        for item in search_dict['title']:
            query = Recipe.query.search(item, fields=('title',)).all()
            for recipe in query:
                if recipe not in search_results['title']:
                    search_results['title'].append(recipe)
    if search_dict['tag']:
        for item in search_dict['tag']:
          query = Tag.query.search(item).all()
          for result in query:
              for recipe in result.recipe:
                  if recipe not in search_results['tag']:
                      search_results['tag'].append(recipe)
    if search_dict['ingredient']:
        for item in search_dict['ingredient']:
            query = Ingredient.query.search(item).all()
            for result in query:
                for recipe in result.recipe:
                    if recipe not in search_results['ingredient']:
                        search_results['ingredient'].append(recipe)
    if search_dict['direction']:
        for item in search_dict['direction']:
            query = Direction.query.search(item).all()
            for result in query:
                for recipe in result.recipe:
                    if recipe not in search_results['direction']:
                        search_results['direction'].append(recipe)
    if search_dict['calories']:
        intersection_list = []
        for item in search_dict['calories']:
            result_group = []
            if '<=' in item:
                query = Recipe.query.filter(Recipe.calories <= item.strip('<=')).order_by(Recipe.calories).all()
            elif '<' in item:
                query = Recipe.query.filter(Recipe.calories < item.strip('<')).order_by(Recipe.calories).all()
            elif '>=' in item:
                query = Recipe.query.filter(Recipe.calories >= item.strip('>=')).order_by(Recipe.calories).all()
            elif '>' in item:
                query = Recipe.query.filter(Recipe.calories > item.strip('>')).order_by(Recipe.calories).all()
            else:
                query = Recipe.query.filter(Recipe.calories == item).order_by(Recipe.calories).all()
            for result in query:
                result_group.append(result)
            # Only keep results that show up in every calorie query
            if len(intersection_list) < 1:
                for item in result_group:
                    intersection_list.append(item)
            else:
                set_result = set(intersection_list) & set(result_group)
                intersection_list.clear()
                for result in set_result:
                    intersection_list.append(result)

            search_results['calories'] = intersection_list

        search_results['calories'].sort(key=lambda x: x.calories)
    if search_dict['note']:
        for item in search_dict['note']:
            query = Note.query.search(item).all()
            for result in query:
                for recipe in result.recipe:
                    if recipe not in search_results['note']:
                        search_results['note'].append(recipe)
    # Combine results
    # Create an initial combined_list dict using the first search term results list unless calories is a key (so that results are sorted by calories primarily)
    if search_dict['calories']:
        initial_key = 'calories'
        combined_list = search_results[initial_key]
    else:
        for key in search_dict.keys():
            if search_dict[key]:
                initial_key = key
                combined_list = search_results[initial_key]
                break
    #Process results and only keep items that appear in every list
    for key in search_results:
        if key != initial_key:
            if search_results[key]:
                combined_list = [x for x in combined_list if x in search_results[key]]
    return [recipe.api_model() for recipe in combined_list]
