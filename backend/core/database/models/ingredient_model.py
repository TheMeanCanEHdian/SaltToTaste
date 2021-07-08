from flask_restful import fields

from extensions import db

ingredient_resource_fields = {
    'id': fields.Integer,
    'name': fields.String,
}


class Ingredient(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(250), nullable=False)