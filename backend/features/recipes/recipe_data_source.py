import hashlib
from os import listdir
from os.path import isfile, join

import yaml

from core.database.datasources.database import Database
from core.helpers.string_helper import StringHelper
from core.database.models.recipe_model import Recipe

string_helper = StringHelper()
database = Database()
RECIPE_DIRECTORY = 'assets/recipes/'


class RecipeFiles:
    def __hash_file(self, filename):
        # Make a hash object
        h = hashlib.sha256()

        # Open file for reading in binary mode
        with open(f'{RECIPE_DIRECTORY}{filename}', 'rb') as file:
            # Loop until the end of the file
            chunk = 0
            while chunk != b'':
                # Read only 1024 bytes at a time
                chunk = file.read(1024)
                h.update(chunk)

        # Return the hex representation of the digest
        return h.hexdigest()

    #* Return a list of recipe dicts from local files
    def load(self):
        recipe_dicts_list = []
        # Load recipe files from recipes folder
        recipe_files = [
            f for f in listdir(RECIPE_DIRECTORY)
            if isfile(join(RECIPE_DIRECTORY, f))
        ]

        # Use pyyaml to load yaml files as dicts
        for file in recipe_files:
            with open(f'{RECIPE_DIRECTORY}{file}', 'r',
                      encoding='utf8') as stream:
                try:
                    recipe_dict = yaml.safe_load(stream)
                    recipe_dict['file_hash'] = self.__hash_file(file)

                    recipe_dicts_list.append(recipe_dict)
                except yaml.YAMLError as error:
                    print(error)

        return recipe_dicts_list


class RecipeDB:
    # --- Private Functions Start --- #
    def __add_tags_to_recipe_item(self, recipe_item, recipe_tags):
        db_tags = database.get_tags(recipe_tags)

        for recipe_tag in recipe_tags:
            tag = next(
                (db_tag for db_tag in db_tags if db_tag.name == recipe_tag),
                None,
            )
            if not tag:
                tag = database.add_tag(recipe_tag)

            recipe_item.tags.append(tag)

    def __add_ingredients_to_recipe_item(self, recipe_item,
                                         recipe_ingredients):
        db_ingredients = database.get_ingredients(recipe_ingredients)

        for recipe_ingredient in recipe_ingredients:
            ingredient = next(
                (db_ingredient for db_ingredient in db_ingredients
                 if db_ingredient.name == recipe_ingredient),
                None,
            )
            if not ingredient:
                ingredient = database.add_ingredient(recipe_ingredient)

            recipe_item.ingredients.append(ingredient)

    def __add_instructions_to_recipe_item(self, recipe_item,
                                          recipe_instructions):
        db_instructions = database.get_instructions(recipe_instructions)

        for recipe_instruction in recipe_instructions:
            instruction = next(
                (db_instruction for db_instruction in db_instructions
                 if db_instruction.name == recipe_instruction),
                None,
            )
            if not instruction:
                instruction = database.add_instruction(recipe_instruction)

            recipe_item.instructions.append(instruction)

    def __add_notes_to_recipe_item(self, recipe_item, recipe_notes):
        db_notes = database.get_notes(recipe_notes)

        for recipe_note in recipe_notes:
            note = next(
                (db_note
                 for db_note in db_notes if db_note.name == recipe_note),
                None,
            )
            if not note:
                note = database.add_note(recipe_note)

            recipe_item.notes.append(note)

    # --- Private Functions End --- #

    def add_recipe_files_to_db(self, recipe_dict_list):
        for recipe_dict in recipe_dict_list:
            self.add_recipe_to_db(recipe_dict)

    #* Take a recipe_dict, create a Recipe model, and call fucntion to add to database
    def add_recipe_to_db(self, recipe_dict):
        title_sanitized = string_helper.sanitize_title(recipe_dict['title'])

        try:
            database.get_recipe_by_title_sanitized(title_sanitized)
        except ValueError:
            new_recipe = Recipe(
                layout=recipe_dict['layout'],
                title=recipe_dict['title'],
                title_sanitized=title_sanitized,
            )
            new_recipe.image = recipe_dict.get('image')
            new_recipe.image_credit = recipe_dict.get('image_credit')
            new_recipe.source = recipe_dict.get('source')
            new_recipe.description = recipe_dict.get('description')
            new_recipe.prep = recipe_dict.get('prep')
            new_recipe.cook = recipe_dict.get('cook')
            new_recipe.ready = recipe_dict.get('ready')
            new_recipe.servings = recipe_dict.get('servings')
            new_recipe.calories = recipe_dict.get('calories')
            new_recipe.file_hash = recipe_dict.get('file_hash')

            if recipe_dict['tags']:
                self.__add_tags_to_recipe_item(new_recipe, recipe_dict['tags'])

            if recipe_dict['ingredients']:
                self.__add_ingredients_to_recipe_item(
                    new_recipe, recipe_dict['ingredients'])
                #TODO: Update nutrition table
                # update_nutrition(recipe.id, recipe.title, recipe['ingredients'], recipe.servings)

            #TODO: Update to instructions not directions
            if recipe_dict['directions']:
                self.__add_instructions_to_recipe_item(
                    new_recipe, recipe_dict['directions'])

            if recipe_dict['notes']:
                self.__add_notes_to_recipe_item(new_recipe,
                                                recipe_dict['notes'])

            database.add_recipe(new_recipe)