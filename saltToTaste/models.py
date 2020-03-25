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
    calcium = db.Column(db.Integer)
    calcium_daily = db.Column(db.Integer)
    carbs = db.Column(db.Integer)
    carbs_daily = db.Column(db.Integer)
    cholesterol = db.Column(db.Integer)
    cholesterol_daily = db.Column(db.Integer)
    energy = db.Column(db.Integer)
    energy_daily = db.Column(db.Integer)
    fat = db.Column(db.Integer)
    fat_daily = db.Column(db.Integer)
    fiber_daily = db.Column(db.Integer)
    fiber = db.Column(db.Integer)
    folate_equivalent = db.Column(db.Integer)
    folate_equivalent_daily = db.Column(db.Integer)
    folate_food = db.Column(db.Integer)
    folate_food_daily = db.Column(db.Integer)
    iron = db.Column(db.Integer)
    iron_daily = db.Column(db.Integer)
    magnesium = db.Column(db.Integer)
    magnesium_daily = db.Column(db.Integer)
    monounsaturated = db.Column(db.Integer)
    monounsaturated_daily = db.Column(db.Integer)
    niacin_b3 = db.Column(db.Integer)
    niacin_b3_daily = db.Column(db.Integer)
    phosphorus = db.Column(db.Integer)
    phosphorus_daily = db.Column(db.Integer)
    polyunsaturated = db.Column(db.Integer)
    polyunsaturated_daily = db.Column(db.Integer)
    potassium = db.Column(db.Integer)
    potassium_daily = db.Column(db.Integer)
    protein = db.Column(db.Integer)
    protein_daily = db.Column(db.Integer)
    riboflavin_b2 = db.Column(db.Integer)
    riboflavin_b2_daily = db.Column(db.Integer)
    saturated = db.Column(db.Integer)
    saturated_daily = db.Column(db.Integer)
    sodium = db.Column(db.Integer)
    sodium_daily = db.Column(db.Integer)
    sugars = db.Column(db.Integer)
    sugars_daily = db.Column(db.Integer)
    sugars_added = db.Column(db.Integer)
    sugars_added_daily = db.Column(db.Integer)
    thiamin_b1 = db.Column(db.Integer)
    thiamin_b1_daily = db.Column(db.Integer)
    trans = db.Column(db.Integer)
    trans_daily = db.Column(db.Integer)
    vitamin_a = db.Column(db.Integer)
    vitamin_a_daily = db.Column(db.Integer)
    vitamin_b12 = db.Column(db.Integer)
    vitamin_b12_daily = db.Column(db.Integer)
    vitamin_b6 = db.Column(db.Integer)
    vitamin_b6_daily = db.Column(db.Integer)
    vitamin_c = db.Column(db.Integer)
    vitamin_c_daily = db.Column(db.Integer)
    vitamin_d = db.Column(db.Integer)
    vitamin_d_daily = db.Column(db.Integer)
    vitamin_e = db.Column(db.Integer)
    vitamin_e_daily = db.Column(db.Integer)
    vitamin_k = db.Column(db.Integer)
    vitamin_k_daily = db.Column(db.Integer)


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
