from flask_restful import fields

from extensions import db

ingredient_resource_fields = {
    'id': fields.Integer,
    'name': fields.String,
    'quantity': fields.Float,
    'unit': fields.String,
    'comment': fields.String,
    'original_string': fields.String,
}


class Ingredient(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(250))
    quantity = db.Column(db.Float)
    unit = db.Column(db.String(15))
    comment = db.Column(db.String(250))
    original_string = db.Column(db.String(250), nullable=False)