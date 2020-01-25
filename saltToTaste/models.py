import flask_whooshalchemy
from flask_login import UserMixin
from whoosh.analysis import StemmingAnalyzer
from werkzeug.security import generate_password_hash
from saltToTaste.extensions import db

recipe_tag = db.Table('recipe_tag_assoc',
    db.Column('recipe_id', db.Integer, db.ForeignKey('recipe.id'), primary_key=True, nullable=False),
    db.Column('tag_id', db.Integer, db.ForeignKey('tag.id'), primary_key=True, nullable=False)
)
recipe_ingredient = db.Table('recipe_ingredient_assoc',
    db.Column('recipe_id', db.Integer, db.ForeignKey('recipe.id'), primary_key=True, nullable=False),
    db.Column('ingredient_id', db.Integer, db.ForeignKey('ingredient.id'), primary_key=True, nullable=False)
)
recipe_direction = db.Table('recipe_direction_assoc',
    db.Column('recipe_id', db.Integer, db.ForeignKey('recipe.id'), primary_key=True, nullable=False),
    db.Column('direction_id', db.Integer, db.ForeignKey('direction.id'), primary_key=True, nullable=False)
)
recipe_note = db.Table('recipe_note_assoc',
    db.Column('recipe_id', db.Integer, db.ForeignKey('recipe.id'), primary_key=True, nullable=False),
    db.Column('note_id', db.Integer, db.ForeignKey('note.id'), primary_key=True, nullable=False)
)

class Recipe(db.Model):
    __searchable__ = ['title', 'description']
    __analyzer__ = StemmingAnalyzer()
    id = db.Column(db.Integer, primary_key=True)
    layout = db.Column(db.String(15))
    title = db.Column(db.String(100), unique=True, nullable=False)
    title_formatted = db.Column(db.String(100))
    filename = db.Column(db.String(100))
    image = db.Column(db.String(104))
    imagecredit = db.Column(db.String(150))
    source = db.Column(db.String(150))
    description = db.Column(db.String(750))
    prep = db.Column(db.Integer)
    cook = db.Column(db.Integer)
    ready = db.Column(db.Integer)
    servings = db.Column(db.Integer)
    calories = db.Column(db.Integer)
    file_hash = db.Column(db.String())

    tags = db.relationship(
        'Tag',
        secondary=recipe_tag,
        lazy=True,
        backref=db.backref('recipe', lazy=True)
    )
    ingredients = db.relationship(
        'Ingredient',
        secondary=recipe_ingredient,
        lazy=True,
        backref=db.backref('recipe', lazy=True)
    )
    directions = db.relationship(
        'Direction',
        secondary=recipe_direction,
        lazy=True,
        backref=db.backref('recipe', lazy=True)
    )
    notes = db.relationship(
        'Note',
        secondary=recipe_note,
        lazy=True,
        backref=db.backref('recipe', lazy=True)
    )

    def api_model(self):
        tags = []
        for tag in self.tags:
            tags.append(tag.name)

        ingredients = []
        for ingredient in self.ingredients:
            ingredients.append(ingredient.name)

        directions = []
        for direction in self.directions:
            directions.append(direction.name)

        notes = []
        for note in self.notes:
            notes.append(note.name)

        model = {
            'id' : self.id,
            'layout' : self.layout,
            'title' : self.title,
            'title_formatted' : self.title_formatted,
            'filename' : self.filename,
            'image' : self.image,
            'imagecredit' : self.imagecredit,
            'source' : self.source,
            'description' : self.description,
            'prep' : self.prep,
            'cook' : self.cook,
            'ready' : self.ready,
            'servings' : self.servings,
            'calories' : self.calories,
            'file_hash' : self.file_hash,
            'tags' : tags,
            'directions' : directions,
            'ingredients' : ingredients,
            'notes' : notes
        }
        return model

    def __repr__(self):
        return f'<Recipe: {self.title}>'

class Tag(db.Model):
    __searchable__ = ['name']
    __analyzer__ = StemmingAnalyzer()
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(30), nullable=False)

    def __repr__(self):
        return f'<Tag: {self.name}>'

class Ingredient(db.Model):
    __searchable__ = ['name']
    __analyzer__ = StemmingAnalyzer()
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(250), nullable=False)

class Direction(db.Model):
    __searchable__ = ['name']
    __analyzer__ = StemmingAnalyzer()
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(1000), nullable=False)

class Note(db.Model):
    __searchable__ = ['name']
    __analyzer__ = StemmingAnalyzer()
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(500), nullable=False)

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(300), unique=True)
    password_hash = db.Column(db.String(100), nullable=False)
    role = db.Column(db.String(50), nullable=False)

    @property
    def password(self):
        raise AttributeError('Cannot view password')

    @password.setter
    def password(self, password):
        self.password_hash = generate_password_hash(password)
