from flask_restful import fields
from sqlalchemy.orm import backref

from .ingredient_model import Ingredient
from .instruction_model import Instruction
from .note_model import Note
from .tag_model import Tag
from extensions import db

recipe_resource_fields = {
    'id': fields.Integer,
    'layout': fields.String,
    'title': fields.String,
    'title_sanitized': fields.String,
    # 'filename': fields.String,
    'image': fields.String,
    'image_credit': fields.String,
    'source': fields.String,
    'description': fields.String,
    'prep': fields.String,
    'cook': fields.String,
    'ready': fields.String,
    'servings': fields.String,
    'calories': fields.String,
    'file_hash': fields.String,
}

# Set up association tables for Recipe
RECIPE_ID = 'recipe.id'

recipe_ingredient = db.Table(
    'recipe_ingredient_assoc',
    db.Column('recipe_id',
              db.Integer,
              db.ForeignKey(RECIPE_ID),
              primary_key=True,
              nullable=False),
    db.Column('ingredient_id',
              db.Integer,
              db.ForeignKey('ingredient.id'),
              primary_key=True,
              nullable=False),
)
recipe_instruction = db.Table(
    'recipe_instruction_assoc',
    db.Column('recipe_id',
              db.Integer,
              db.ForeignKey(RECIPE_ID),
              primary_key=True,
              nullable=False),
    db.Column('instruction_id',
              db.Integer,
              db.ForeignKey('instruction.id'),
              primary_key=True,
              nullable=False),
)
recipe_note = db.Table(
    'recipe_note_assoc',
    db.Column('recipe_id',
              db.Integer,
              db.ForeignKey(RECIPE_ID),
              primary_key=True,
              nullable=False),
    db.Column('note_id',
              db.Integer,
              db.ForeignKey('note.id'),
              primary_key=True,
              nullable=False),
)
recipe_tag = db.Table(
    'recipe_tag_assoc',
    db.Column(
        'recipe_id',
        db.Integer,
        db.ForeignKey(RECIPE_ID),
        primary_key=True,
        nullable=False,
    ),
    db.Column(
        'tag_id',
        db.Integer,
        db.ForeignKey('tag.id'),
        primary_key=True,
        nullable=False,
    ),
)


class Recipe(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    layout = db.Column(db.String(15))
    title = db.Column(db.String(100), unique=True, nullable=False)
    title_sanitized = db.Column(db.String(100), unique=True, nullable=False)
    image = db.Column(db.String(104))
    image_credit = db.Column(db.String(150))
    source = db.Column(db.String(150))
    description = db.Column(db.String(750))
    prep = db.Column(db.Integer)
    cook = db.Column(db.Integer)
    ready = db.Column(db.Integer)
    servings = db.Column(db.Integer)
    calories = db.Column(db.Integer)
    file_hash = db.Column(db.String())

    ingredients = db.relationship(
        'Ingredient',
        secondary=recipe_ingredient,
        lazy=True,
        backref=db.backref('recipe', lazy=True),
    )
    instructions = db.relationship(
        'Instruction',
        secondary=recipe_instruction,
        lazy=True,
        backref=db.backref('recipe', lazy=True),
    )
    notes = db.relationship(
        'Note',
        secondary=recipe_note,
        lazy=True,
        backref=db.backref('recipe', lazy=True),
    )
    tags = db.relationship(
        'Tag',
        secondary=recipe_tag,
        lazy=True,
        backref=db.backref('recipe', lazy=True),
    )
