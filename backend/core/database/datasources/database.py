from flask_restful import marshal_with

from ...helpers.string_helper import StringHelper
from ..models.ingredient_model import Ingredient
from ..models.instruction_model import Instruction
from ..models.note_model import Note
from ..models.recipe_model import Recipe, recipe_resource_fields, recipe_list_resource_fields
from ..models.tag_model import Tag
from extensions import db

string_helper = StringHelper()


class Database:
    def add_ingredient(self, ingredient_name):
        ingredient = Ingredient(name=ingredient_name)
        db.session.add(ingredient)
        return ingredient

    def add_instruction(self, instruction_name):
        instruction = Instruction(name=instruction_name)
        db.session.add(instruction)
        return instruction

    def add_note(self, note_name):
        note = Note(name=note_name)
        db.session.add(note)
        return note

    def add_nutrition(self, nutrition_model):
        db.session.add(nutrition_model)
        db.session.commit

    def add_recipe(self, recipe):
        db.session.add(recipe)
        db.session.commit()

    def add_tag(self, tag_name):
        tag = Tag(name=tag_name)
        db.session.add(tag)
        return tag

    def get_ingredients(self, ingredient_name_list):
        ingredients = Ingredient.query.filter(
            Ingredient.name.in_(ingredient_name_list))
        return ingredients

    def get_instructions(self, instruction_name_list):
        instructions = Instruction.query.filter(
            Instruction.name.in_(instruction_name_list))
        return instructions

    def get_notes(self, note_name_list):
        notes = Note.query.filter(Note.name.in_(note_name_list))
        return notes

    @marshal_with(recipe_list_resource_fields)
    def get_recipe_list(self):
        recipe_list = Recipe.query.all()
        return recipe_list

    @marshal_with(recipe_resource_fields)
    def get_recipe_by_title_sanitized(self, title_sanitized):
        recipe = Recipe.query.filter(
            Recipe.title_sanitized == title_sanitized).first()

        if not recipe:
            raise ValueError('No recipe found with that sanitized title.')

        return recipe

    def get_recipe_image(self, title_sanitized):
        query = Recipe.query.filter(
            Recipe.title_sanitized == title_sanitized).first()

        if not query:
            return ''

        return query.image

    @marshal_with(recipe_resource_fields)
    def get_recipes(self):
        recipes = Recipe.query.all()
        return recipes

    def get_tags(self, tag_name_list):
        tags = Tag.query.filter(Tag.name.in_(tag_name_list))
        return tags
